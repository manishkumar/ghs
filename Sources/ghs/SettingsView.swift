import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var store: PRStore
    @State private var tab: Tab

    /// The settings window's size. The Queue pane is taller than this and
    /// scrolls; the documentation renderer overrides `height` so a screenshot
    /// can show a whole pane at once.
    static let windowWidth: CGFloat = 480
    static let windowHeight: CGFloat = 500

    private let height: CGFloat

    init(store: PRStore, initialTab: Tab = .repositories, height: CGFloat = SettingsView.windowHeight) {
        self.store = store
        self.height = height
        _tab = State(initialValue: initialTab)
    }

    enum Tab: String, CaseIterable, Identifiable {
        case repositories = "Repositories"
        case queue = "Queue"
        case account = "Account"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .repositories: return "square.stack.3d.up"
            case .queue: return "flame"
            case .account: return "key"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            picker
            Divider()
            Group {
                switch tab {
                case .repositories: RepositoriesPane(store: store)
                case .queue: QueuePane(store: store)
                case .account: AccountPane(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.windowWidth, height: height)
        .background(.ultraThinMaterial)
    }

    private var picker: some View {
        HStack(spacing: 2) {
            Spacer()
            ForEach(Tab.allCases) { candidate in
                Button {
                    tab = candidate
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: candidate.symbol).font(.system(size: 14, weight: .regular))
                        Text(candidate.rawValue).font(.system(size: 10, weight: .medium))
                    }
                    .frame(width: 78, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(tab == candidate ? Color.primary.opacity(0.09) : .clear)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(tab == candidate ? .primary : .secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 28)
        .padding(.bottom, 8)
    }
}

// MARK: - Repositories

private struct RepositoriesPane: View {
    @Bindable var store: PRStore
    @State private var draft = ""
    @State private var selection: Set<WatchedRepo.ID> = []
    @State private var rejected: String?
    @FocusState private var fieldFocused: Bool

    private var settings: AppSettings { store.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Watched repositories").eyebrowStyle()

                HStack(spacing: 6) {
                    TextField("owner/repo, or paste a GitHub URL", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }

                if let rejected {
                    Label("\(rejected) isn't a repository ghs can read. Use owner/repo.",
                          systemImage: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            .padding(16)

            Divider()

            if settings.repos.isEmpty {
                VStack(spacing: 6) {
                    Text("No repositories yet")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add one above. Every watched repo is covered by the same\nsingle API call, so the list can be as long as you like.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(settings.repos) { repo in
                            RepoRow(
                                repo: repo,
                                openCount: store.pullRequests.filter { $0.repo == repo.nameWithOwner }.count,
                                isSelected: selection.contains(repo.id),
                                onSelect: { selection = [repo.id] },
                                onRemove: { remove([repo.id]) }
                            )
                            Divider()
                        }
                    }
                }
            }

            Divider()
            HStack {
                Text(String(settings.repos.count) + " watched")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove") { remove(selection) }
                    .disabled(selection.isEmpty)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear { fieldFocused = true }
    }

    private func add() {
        let input = draft.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }
        if settings.addRepo(input) {
            draft = ""
            rejected = nil
            Task { await store.refresh() }
        } else {
            rejected = input
        }
    }

    private func remove(_ ids: Set<WatchedRepo.ID>) {
        settings.removeRepos(ids)
        selection = []
        Task { await store.refresh() }
    }
}

private struct RepoRow: View {
    let repo: WatchedRepo
    let openCount: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(repo.owner + "/").foregroundStyle(.secondary)
                + Text(repo.name).foregroundStyle(.primary)
            Spacer()
            if openCount > 0 {
                Text(String(openCount))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    .help(String(openCount) + " waiting on review")
            }
            Button(action: onRemove) {
                Image(systemName: "minus.circle").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0)
            .help("Stop watching \(repo.nameWithOwner)")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.15)
                    : hovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Urgency

private struct QueuePane: View {
    @Bindable var store: PRStore
    @Environment(\.colorScheme) private var scheme

    private var settings: AppSettings { store.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What counts").eyebrowStyle()
                Toggle(isOn: Binding(
                    get: { settings.includeUnreviewed },
                    set: { settings.includeUnreviewed = $0; Task { await store.refresh() } }
                )) {
                    Text("Include pull requests nobody has been asked to review")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Text("Repos without branch protection never tell GitHub that a review is needed, so their open pull requests are invisible unless a reviewer is formally requested. Personal repos are usually like this.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Ageing").eyebrowStyle()
                Text("A pull request starts at patina and oxidises to rust as it waits. Pick how long that takes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                RampPreview(days: settings.urgentAfterDays)

                HStack {
                    Slider(
                        value: Binding(
                            get: { settings.urgentAfterDays },
                            set: { settings.urgentAfterDays = $0.rounded() }
                        ),
                        in: 1...21, step: 1
                    )
                    Text(String(Int(settings.urgentAfterDays)) + "d")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 32, alignment: .trailing)
                }
                Text("Age counts from when a pull request became ready for review, not when it was created — time spent in draft isn't review debt.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Checking").eyebrowStyle()
                Picker("", selection: Binding(
                    get: { settings.pollInterval },
                    set: { settings.pollInterval = $0; store.restart() }
                )) {
                    Text("Every minute").tag(TimeInterval(60))
                    Text("Every 2 minutes").tag(TimeInterval(120))
                    Text("Every 5 minutes").tag(TimeInterval(300))
                    Text("Every 15 minutes").tag(TimeInterval(900))
                }
                .labelsHidden()
                .frame(width: 180)
                Text("One check covers every watched repo and costs 1 of GitHub's 5,000 hourly API calls.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Divider()

            LaunchAtLoginToggle()

            Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

/// The ramp, shown at the real scale with real day markers, so the setting is
/// legible before it's applied.
private struct RampPreview: View {
    let days: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(0..<60, id: \.self) { step in
                        Rectangle().fill(Theme.oxidation(
                            Theme.fraction(forAge: Double(step) / 59 * days * 86_400, threshold: days),
                            scheme: scheme
                        ))
                    }
                }
                .frame(width: geo.size.width)
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            HStack {
                Text("fresh").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                Spacer()
                Text(String(Int(days / 2)) + "d").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                Spacer()
                Text("rust at " + String(Int(days)) + "d").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Open ghs at login", isOn: $enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: enabled) { _, wanted in
                    do {
                        wanted ? try SMAppService.mainApp.register()
                               : try SMAppService.mainApp.unregister()
                        problem = nil
                    } catch {
                        // Registration only works from a signed bundle in a
                        // stable location, so say where it has to live.
                        problem = "Move ghs to /Applications and try again."
                        enabled = SMAppService.mainApp.status == .enabled
                    }
                }
            if let problem {
                Text(problem).font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Account

private struct AccountPane: View {
    @Bindable var store: PRStore
    @State private var patDraft = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Authentication").eyebrowStyle()

            HStack(spacing: 7) {
                Image(systemName: store.tokenSource == nil ? "xmark.seal.fill" : "checkmark.seal.fill")
                    .foregroundStyle(store.tokenSource == nil ? .orange : .green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.tokenSource == nil ? "Not signed in" : "Signed in")
                        .font(.system(size: 12, weight: .semibold))
                    Text(store.tokenSource?.rawValue ?? "ghs found no token on this Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))

            Text("""
            SSH keys sign git operations only — GitHub's API doesn't accept them. \
            ghs borrows the GitHub CLI's token when `gh` is installed, which needs \
            no setup at all.
            """)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Personal access token").eyebrowStyle()
                Text("Only needed if you don't use `gh`. Requires the `repo` scope. Stored in your Keychain.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    SecureField("ghp_…", text: $patDraft)
                        .textFieldStyle(.roundedBorder)
                    Button(saved ? "Saved" : "Save") {
                        Keychain.write(patDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                        patDraft = ""
                        saved = true
                        Task {
                            await store.refresh()
                            try? await Task.sleep(for: .seconds(1.5))
                            saved = false
                        }
                    }
                    .disabled(patDraft.isEmpty)
                }
                Button("Forget stored token") {
                    Keychain.delete()
                    Task { await store.refresh() }
                }
                .controlSize(.small)
            }

            Spacer()
        }
        .padding(16)
    }
}
