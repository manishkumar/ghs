import AppKit
import Foundation
import Observation

/// Single source of truth for everything the UI renders.
@MainActor
@Observable
final class PRStore {
    internal(set) var pullRequests: [PullRequest] = []
    private(set) var isRefreshing = false
    internal(set) var lastRefresh: Date?
    private(set) var lastError: String?
    internal(set) var tokenSource: GitHubAuth.Source?
    /// PRs that appeared since the last successful poll, so the menu can flag
    /// what just landed in the queue.
    internal(set) var newlyArrived: Set<PullRequest.ID> = []
    internal(set) var viewerLogin: String?

    let settings: AppSettings
    private var pollTask: Task<Void, Never>?
    private var knownIDs: Set<PullRequest.ID> = []
    private var hasCompletedFirstLoad = false

    init(settings: AppSettings) {
        self.settings = settings
        observeWake()
    }

    var blockedCount: Int { pullRequests.count }

    /// PRs where this user is personally the blocker. The number that should
    /// drive action — a team total is a weather report, not an obligation.
    var awaitingViewer: [PullRequest] {
        pullRequests.filter { $0.awaits(viewerLogin) }
    }

    /// This user's own PRs, blocked on somebody else. Shown next to the number
    /// above so the imbalance is visible; that asymmetry is the whole point.
    var authoredByViewer: [PullRequest] {
        guard let viewerLogin else { return [] }
        return pullRequests.filter { $0.author.caseInsensitiveCompare(viewerLogin) == .orderedSame }
    }

    var nextUp: PullRequest? {
        PullRequest.nextUp(
            from: pullRequests,
            threshold: settings.urgentAfterDays,
            viewer: viewerLogin
        )
    }

    /// Age fraction of the oldest PR waiting on this user.
    var viewerUrgency: Double {
        urgency(of: awaitingViewer)
    }

    /// Age fraction of the oldest PR in the whole queue. This is what the
    /// status bar colours, because the status bar shows the whole queue.
    var queueUrgency: Double {
        urgency(of: pullRequests)
    }

    private func urgency(of prs: [PullRequest]) -> Double {
        prs
            .map { Theme.fraction(forAge: $0.age, threshold: settings.urgentAfterDays) }
            .max() ?? 0
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = self?.settings.pollInterval ?? 120
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Restart the cadence immediately — used when the poll interval changes so
    /// the new value takes effect without waiting out the old sleep.
    func restart() { start() }

    func refresh() async {
        guard !isRefreshing else { return }

        guard let credential = GitHubAuth.resolve() else {
            tokenSource = nil
            lastError = GitHubError.notAuthenticated.localizedDescription
            pullRequests = []
            return
        }
        tokenSource = credential.source

        guard !settings.repos.isEmpty else {
            pullRequests = []
            lastError = nil
            lastRefresh = Date()
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let snapshot = try await GitHubClient(token: credential.token)
                .fetchOpenPullRequests(in: settings.repos)
            viewerLogin = snapshot.viewerLogin
            let includeUnreviewed = settings.includeUnreviewed
            let blocked = snapshot.pullRequests
                .filter { $0.isBlockedOnReview(includeUnreviewed: includeUnreviewed) }
                .sorted { $0.readyAt < $1.readyAt }  // oldest first: most urgent on top

            let ids = Set(blocked.map(\.id))
            // Don't flood the "new" flag on the very first load of a session.
            newlyArrived = hasCompletedFirstLoad ? ids.subtracting(knownIDs) : []
            knownIDs = ids
            hasCompletedFirstLoad = true

            pullRequests = blocked
            lastError = nil
            lastRefresh = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func open(_ pr: PullRequest) {
        NSWorkspace.shared.open(pr.url)
        newlyArrived.remove(pr.id)
    }

    /// Waking from sleep means the data is stale by however long the lid was
    /// shut, so poll straight away instead of waiting out the timer.
    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restart() }
        }
    }
}
