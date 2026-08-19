# ghs — GitHub PR Review Queue (macOS status bar app)

A macOS status bar app whose purpose is **to get pull requests reviewed in a
team**, not merely to list them. Every design decision should be judged against
that: does it make an individual more likely to go and review something?

The core insight the app is built on: a shared backlog diffuses responsibility,
so aggregate counts don't motivate. Personal obligation and visible reciprocity
do. Hence the popover opens with the balance line — what you owe, next to what
you are owed — and the list is topped by a single costed recommendation.

The **status bar shows one number: the whole queue**, coloured by the oldest PR
in it. It carried two (yours·team) and that was tested and rejected: a reader
has to stop and work out which figure is which, and a menu bar item gets a
glance, not a read. The personal count lives in the popover and the tooltip,
where there is room to label it.

**Rejected on purpose — do not add without an explicit decision to reverse
this**: leaderboards, reviewer rankings, review-count scores, and one-click
approve. They optimise reviews-submitted at the expense of code-actually-read,
and make rubber-stamping the path of least resistance.

It surfaces pull requests **blocked waiting on review** across a user-configured
set of watched repositories.

"Waiting on review" = GitHub's own `reviewDecision` is `REVIEW_REQUIRED` (which
accounts for branch protection and CODEOWNERS), or — for repos with no
protection rule — a reviewer is requested and nobody has approved.

## Decisions already made

- **Scope**: all PRs blocked on review in watched repos, not just ones assigned
  to the user. The **You** filter chip narrows to the user's own requests.
- **Auth**: SSH keys authenticate git transport only; the GitHub API rejects
  them. Token order is `gh auth token` → `GH_TOKEN`/`GITHUB_TOKEN` → Keychain
  PAT. Never store a token outside the Keychain, never log one.
- **One GraphQL search covers every watched repo**, so adding repos costs no
  extra rate limit. Never poll faster than 60s.
- **Status bar images must be templates unless colour is carrying meaning.**
  The menu bar is translucent over the wallpaper, so a fixed colour washes out
  and cannot adapt to a dark bar or a highlighted item. `StatusItemController`
  draws a template mark by default and switches to a coloured rail only past an
  urgency threshold; the numerals turn later still, because brass on a pale
  wallpaper is the weakest thing in the palette. Never use `tertiaryLabelColor`
  in the menu bar — subordinate is not the same as invisible.
  `StatusItemController.appearance` is a pure function precisely so
  `--render` can draw every state over both menu bar grounds for inspection.
- **An `.accessory` app must still install `NSApp.mainMenu`.** It shows no menu
  bar, but ⌘V/⌘C/⌘X/⌘A/⌘Z are dispatched by the main menu's key equivalents, so
  without one the standard editing shortcuts silently do nothing in every text
  field while right-click → Paste still works. See `MainMenu.swift`.
- **Repos without branch protection report no `reviewDecision`.** The
  `includeUnreviewed` setting (default on) decides whether their unapproved PRs
  count. With it off, open PRs in personal repos are invisible.
- **Settings live in an explicitly named `UserDefaults` suite**
  (`AppSettings.suiteName`), not `.standard`. A bare `swift build` binary and
  the packaged `.app` have different process identities, so `.standard` gave
  them separate stores and `--list` reported "no repositories watched" while the
  menu bar showed a full queue.
- **Read `reviewDecision`; never call the branch-protection API** — it needs
  admin on the repo and 403s on most repos a user watches.
- **Never clamp or normalise a property inside its own `didSet`.** `@Observable`
  rewrites stored properties into computed ones over hidden storage, so
  assigning to the property from inside its `didSet` re-enters the public setter
  and recurses until the stack overflows. This crashed the app on every poll
  interval change. Put clamping in an explicit `set`, over a private stored
  property. See `AppSettings`.
- **A PR you have already reviewed stays in the queue but settles.** Read via
  `viewerLatestReview { state commit { oid } }` against `headRefOid`. It is
  still blocked, so the count and the rail column keep it; but `awaits()`
  returns false, so it leaves **You**, the balance line and `nextUp`, and
  `QueueRow` dims it (`Theme.settledRail` / `Theme.settledContent`). Rows are
  **not** reordered by this — the rails must stay a monotonic age gradient.
  A comment-only review settles; `PENDING`/`DISMISSED` don't; a push since the
  review un-settles it, and an unknown commit on either side counts as covering
  head so an unknown never invents an obligation.
- **Age is measured from `ReadyForReviewEvent`**, falling back to `createdAt`.
- **AppKit `NSStatusItem` + `NSPopover`, not SwiftUI `MenuBarExtra`**: the
  status item's appearance changes with queue age, and `SettingsLink` /
  `openSettings` silently do nothing from a `MenuBarExtra` in an `.accessory`
  app. Settings is a real `NSWindow` that explicitly activates the app.

## Visual system

Defined in `Theme.swift`; do not introduce colours outside it.

- **Oxidation ramp** — patina `#3F8F7C` → brass `#B99B2E` → oxide `#C25E2A` →
  rust `#C0341C`, with separate light/dark stops. Deliberately not a green→red
  traffic light: it reads as a material ageing.
- **Signature element**: the rails on the left of each row are full-bleed and
  rows are flush, so they join into one continuous decay column. Nothing else
  in the UI is coloured except the stale count and the status bar count.
- **Type**: SF Pro for prose, SF Mono for *every* number, uppercase mono
  eyebrows (`.eyebrowStyle()`) for structural labels only.
- Use `String(n)`, never `Text("\(n)")`, for numbers — `Text` applies locale
  digit grouping and turns PR #10423 into #10,423.

## Layout

```
Sources/ghs/
  main.swift                  AppDelegate, .accessory policy, debug flags
  StatusItemController.swift  NSStatusItem + NSPopover, age-tinted count
  SettingsWindowController.swift  real NSWindow (fixes the Settings bug)
  QueueView.swift             popover: balance line, next-up card, chips, list, footer
  QueueRow.swift              one PR row, including the oxidation rail
  SettingsView.swift          Repositories / Queue / Account panes
  MainMenu.swift              invisible main menu; makes ⌘V etc. work
  Theme.swift                 the whole visual system
  GitHubClient.swift          GraphQL search + decoding
  GitHubAuth.swift            token resolution
  PRStore.swift               @Observable store, poll loop
  AvatarLoader.swift          in-memory avatar cache
  DebugCLI.swift  DebugRender.swift   verification harnesses (DEBUG only)
Tests/ghsTests/               swift-testing suites
```

README interface screenshots come from `--render` with fixed sample data, so
regenerate them with `scripts/make-screenshots.py` whenever the popover or the
settings panes change. `SettingsView` takes a `height` override purely so the
renderer can show a whole pane at once — the Queue pane is taller than the
window and scrolls in the real app.

Crash reports land in `~/Library/Logs/DiagnosticReports/ghs-*.ips`; they are
JSON after the first line, and the faulting thread's frames name the cycle
directly for recursion crashes.

## Verifying UI changes

`screencapture` on this machine returns only the desktop wallpaper — Screen
Recording permission is not granted — so screenshots cannot verify the UI.
Use the harnesses instead:

```sh
./.build/debug/ghs --render <dir>   # renders views offscreen through AppKit
./.build/debug/ghs --diagnose       # status item + window state, then exits
./.build/debug/ghs --list           # data path only, no UI
```

`--render` uses `NSHostingView` + `cacheDisplay`, not `ImageRenderer`:
`ImageRenderer` draws buttons and text fields as yellow placeholder blocks and
scroll views as empty space.

## Commands

```sh
swift build
swift test                     # swift-testing; no Xcode on this machine, so no XCTest
./scripts/make-app.sh          # assemble build/ghs.app (LSUIElement, icon, ad-hoc signed)
python3 scripts/make-icon.py          # regenerate Resources/AppIcon.icns (needs Pillow)
python3 scripts/make-screenshots.py   # regenerate docs/ README images from --render
./scripts/make-terminal-svgs.sh       # regenerate docs/terminal-*.svg from real output
```

Terminal screenshots are SVG, captured from real command runs: `script -q` under
a pty keeps ANSI colour alive, `scripts/ansi2svg.mjs` draws the frame. The
script is lifted from `reins` with one fix — `\r` overwrites the line instead of
being deleted, so `swift build` progress output doesn't concatenate into one
enormous line. Captures run against **public** repos (`--list --repos
cli/cli,sharkdp/bat`) so documentation never carries private repository names,
and `script` is always given `</dev/null` or it intermittently echoes a literal
`^D` and exits non-zero on a command that succeeded.
