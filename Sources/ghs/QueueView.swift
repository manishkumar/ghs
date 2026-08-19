import AppKit
import SwiftUI

struct QueueView: View {
    @Bindable var store: PRStore
    var onOpenSettings: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var search = ""
    @State private var scope: Scope = .all
    @State private var selection: PullRequest.ID?
    @State private var listHeight: CGFloat = 0
    @FocusState private var searchFocused: Bool

    enum Scope: String, CaseIterable {
        case all = "All"
        case mine = "You"
        case stale = "Stale"
    }

    var body: some View {
        VStack(spacing: 0) {
            balance
            controls
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: Theme.popoverWidth)
        .background(.ultraThinMaterial)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return) { openSelected(); return .handled }
        .onKeyPress(.escape) { search = ""; return .handled }
        .background {
            // Invisible buttons purely to register the shortcuts; the popover
            // has no menu bar of its own to hang them on.
            VStack {
                Button("") { Task { await store.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                Button("") { onOpenSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                Button("") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
            }
            .opacity(0)
        }
    }

    // MARK: Balance

    /// Reciprocity, stated plainly.
    ///
    /// The asymmetry between what you owe and what you are owed is the
    /// strongest lever available here: it needs no manager, no leaderboard and
    /// no nagging, because nobody wants to be the person everyone is waiting
    /// on. A team total can't do this; only your own position can.
    @ViewBuilder
    private var balance: some View {
        if store.viewerLogin != nil, !store.pullRequests.isEmpty {
            let owed = store.awaitingViewer.count
            let waiting = store.authoredByViewer.count

            HStack(spacing: 5) {
                if owed == 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green.opacity(0.8))
                    Text("Nothing waiting on you")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(owed))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(owedTint)
                    Text(owed == 1 ? "review waiting on you" : "reviews waiting on you")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                }

                if waiting > 0 {
                    Text("·").foregroundStyle(.tertiary)
                    Text(String(waiting))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(waiting == 1 ? "of yours waiting on others" : "of yours waiting on others")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 11)
        }
    }

    private var owedTint: Color {
        let urgency = store.viewerUrgency
        return urgency < 0.5 ? .primary : Theme.oxidation(urgency, scheme: scheme)
    }

    /// The colour of the oldest thing in the queue.
    private var oldestTint: Color {
        guard let oldest = store.pullRequests.first else { return .secondary }
        return Theme.oxidation(
            forAge: oldest.age,
            threshold: store.settings.urgentAfterDays,
            scheme: scheme
        )
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 6) {
            ForEach(Scope.allCases, id: \.self) { candidate in
                ScopeChip(
                    title: candidate.rawValue,
                    count: count(for: candidate),
                    isSelected: scope == candidate,
                    // Only the stale count is coloured — it is the one number
                    // here that means something is going wrong.
                    countTint: candidate == .stale && count(for: .stale) > 0 ? oldestTint : nil
                ) {
                    scope = candidate
                }
                .disabled(candidate != .all && count(for: candidate) == 0)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextField("Filter", text: $search)
                    .textFieldStyle(.plain)
                    .font(Theme.meta)
                    .focused($searchFocused)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .frame(width: 132)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 9)
        .padding(.bottom, 10)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let error = store.lastError {
            EmptyStateView(
                symbol: "exclamationmark.triangle",
                headline: "Can't reach GitHub",
                message: error,
                actionTitle: "Open settings",
                action: onOpenSettings
            )
        } else if store.settings.repos.isEmpty {
            EmptyStateView(
                symbol: "tray",
                headline: "Watch a repository",
                message: "Add the repos you review for and ghs will keep their open pull requests here.",
                actionTitle: "Add a repository",
                action: onOpenSettings
            )
        } else if store.pullRequests.isEmpty {
            EmptyStateView(
                symbol: "checkmark.seal",
                headline: "Queue is clear",
                message: "Nothing in \(store.settings.repos.count) watched repositor\(store.settings.repos.count == 1 ? "y" : "ies") is waiting on review."
            )
        } else if visible.isEmpty {
            EmptyStateView(
                symbol: "line.3.horizontal.decrease",
                headline: "No matches",
                message: "Nothing in the queue matches this filter.",
                actionTitle: "Clear filter",
                action: { search = ""; scope = .all }
            )
        } else {
            VStack(spacing: 0) {
                if let candidate = recommendation {
                    NextUpCard(
                        pr: candidate,
                        threshold: store.settings.urgentAfterDays,
                        onOpen: { store.open(candidate) }
                    )
                    Divider()
                }
                list
            }
        }
    }

    /// Drawn from what is actually on screen, so the recommendation can never
    /// point at something the current filter has hidden.
    private var recommendation: PullRequest? {
        guard search.isEmpty, scope != .stale, visible.count > 1 else { return nil }
        return PullRequest.nextUp(
            from: visible,
            threshold: store.settings.urgentAfterDays,
            viewer: store.viewerLogin
        )
    }

    /// The recommendation is lifted out of the list rather than repeated in it,
    /// so the card reads as taking one off the top of the pile.
    private var listItems: [PullRequest] {
        guard let recommendation else { return visible }
        return visible.filter { $0.id != recommendation.id }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Zero spacing so the oxidation rails of adjacent rows form one
                // unbroken column down the left edge. Sorted oldest first, that
                // column reads as a decay gradient: rust at the top, patina at
                // the bottom.
                LazyVStack(spacing: 0) {
                    ForEach(listItems) { pr in
                        QueueRow(
                            pr: pr,
                            isNew: store.newlyArrived.contains(pr.id),
                            awaitsViewer: pr.awaits(store.viewerLogin),
                            isSelected: selection == pr.id,
                            threshold: store.settings.urgentAfterDays,
                            onOpen: { store.open(pr) }
                        )
                        .id(pr.id)
                        .onHover { if $0 { selection = pr.id } }

                        Divider().padding(.leading, Theme.railWidth)
                    }
                }
                // Measured rather than estimated: a per-row guess leaves a
                // sliver of dead space under the last row, or clips it.
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: ListHeightKey.self, value: geometry.size.height)
                    }
                )
            }
            .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
            // Sized to the rows so a short queue gets a short popover instead
            // of a tall pane of empty space. No floor: with a single PR the
            // recommendation card takes it and the list is genuinely empty, and
            // a floor there is 54pt of nothing under the card.
            .frame(height: min(maxListHeight, listHeight))
            .onChange(of: selection) { _, new in
                guard let new else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    /// How tall the scrolling list is allowed to get before it starts
    /// scrolling. Screen-aware rather than a flat number, because a popover
    /// taller than the menu bar's screen gets repositioned by AppKit and ends
    /// up covering the item that opened it. The subtraction is the chrome
    /// around the list — balance line, chips, next-up card, footer — plus room
    /// to breathe under the popover's arrow.
    private var maxListHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return min(560, max(300, screen - 220))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.lastError == nil ? Color.green.opacity(0.7) : Color.orange)
                .frame(width: 5, height: 5)
            Text(statusLine)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()

            iconButton("arrow.clockwise", help: "Check now (⌘R)") {
                Task { await store.refresh() }
            }
            .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
            .animation(store.isRefreshing
                       ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                       : .default,
                       value: store.isRefreshing)

            iconButton("gearshape", help: "Settings (⌘,)", action: onOpenSettings)

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
        }
        .padding(.leading, Theme.gutter)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
    }

    private var statusLine: String {
        guard let last = store.lastRefresh else { return "Waiting for first check" }
        let elapsed = Date().timeIntervalSince(last)
        let when: String
        if elapsed < 45 {
            // RelativeDateTimeFormatter says "in 0 seconds" for a fresh check,
            // which reads as a bug.
            when = "just now"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            when = formatter.localizedString(for: last, relativeTo: Date())
        }
        guard let source = store.tokenSource else { return "Checked \(when)" }
        return "Checked \(when) · \(source.shortLabel)"
    }

    // MARK: Filtering & keyboard

    private func matches(_ pr: PullRequest, _ scope: Scope) -> Bool {
        switch scope {
        case .all: return true
        case .mine: return pr.awaits(store.viewerLogin)
        case .stale: return Theme.fraction(forAge: pr.age, threshold: store.settings.urgentAfterDays) >= 1
        }
    }

    private func count(for scope: Scope) -> Int {
        store.pullRequests.filter { matches($0, scope) }.count
    }

    private var visible: [PullRequest] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.pullRequests.filter { pr in
            guard matches(pr, scope) else { return false }
            guard !query.isEmpty else { return true }
            return pr.title.lowercased().contains(query)
                || pr.repo.lowercased().contains(query)
                || pr.author.lowercased().contains(query)
                || "\(pr.number)".contains(query)
        }
    }

    private func move(_ delta: Int) {
        let rows = listItems
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selection } ?? -1
        let next = min(max(current + delta, 0), rows.count - 1)
        selection = rows[next].id
    }

    private func openSelected() {
        guard let id = selection, let pr = listItems.first(where: { $0.id == id }) else { return }
        store.open(pr)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Next up

/// One recommendation with a cost attached. A backlog of forty is paralysing;
/// "this one, about five minutes" is a decision someone can actually make.
private struct NextUpCard: View {
    let pr: PullRequest
    let threshold: Double
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Theme.oxidation(forAge: pr.age, threshold: threshold, scheme: scheme))
                .frame(width: Theme.railWidth)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Next up").eyebrowStyle()
                    Spacer()
                    Text("~\(pr.estimatedMinutes) min")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(pr.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text("\(pr.repo) #" + String(pr.number) + " · \(pr.ageSpelled) · \(pr.sizeDescription)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 11)
            .padding(.vertical, 9)

            Spacer(minLength: 8)

            Button("Review", action: onOpen)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .padding(.trailing, 11)
        }
        .background(Color.primary.opacity(0.045))
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next up: \(pr.title), \(pr.ageSpelled), about \(pr.estimatedMinutes) minutes")
    }
}

private struct ListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Scope chip

private struct ScopeChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    var countTint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(String(count))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(countTint ?? (isSelected ? Color.primary : Color.secondary.opacity(0.6)))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isSelected ? Color.primary.opacity(0.11) : .clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    let symbol: String
    let headline: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(headline).font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(Theme.meta)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
    }
}
