import Foundation

/// A repository the user has asked us to watch, stored as `owner/name`.
struct WatchedRepo: Codable, Hashable, Identifiable {
    let owner: String
    let name: String

    var id: String { nameWithOwner }
    var nameWithOwner: String { "\(owner)/\(name)" }

    /// Accepts `owner/repo`, a browser URL, or an SSH remote and normalizes them
    /// all to the same value. Returns nil for anything we can't make sense of.
    init?(input rawInput: String) {
        var s = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        if let range = s.range(of: "github.com") {
            s = String(s[range.upperBound...])
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ":/"))
        if s.hasSuffix(".git") { s.removeLast(4) }

        let parts = s.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[0], name = parts[1]
        guard !owner.isEmpty, !name.isEmpty, owner != "..", name != ".." else { return nil }

        self.owner = owner
        self.name = name
    }
}

/// GitHub's own verdict on whether a PR still needs review. This already
/// accounts for branch protection rules and CODEOWNERS, which is why we read it
/// instead of trying to compare approval counts against protection settings
/// ourselves (that API requires admin on the repo).
enum ReviewDecision: String, Codable {
    case reviewRequired = "REVIEW_REQUIRED"
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
}

/// The viewer's own last review on a pull request.
///
/// This exists so the queue can tell "nobody has looked at this" apart from
/// "you looked, it still needs someone else". The PR stays in the queue either
/// way — it is genuinely still blocked — but only the first kind should be
/// allowed to nag you personally.
struct ViewerReview: Hashable {
    enum State: String, Codable {
        case pending = "PENDING"
        case commented = "COMMENTED"
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case dismissed = "DISMISSED"
    }

    let state: State
    /// False when the author has pushed since you reviewed, so there is code
    /// here you haven't read. Null commits (GitHub omits them on some older
    /// reviews) count as covering, so an unknown never invents an obligation.
    let coversHead: Bool
}

struct PullRequest: Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let author: String
    let repo: String
    let createdAt: Date
    /// When the PR actually entered the review queue. For PRs opened as drafts
    /// this is the "ready for review" moment, not creation — a PR that sat in
    /// draft for weeks isn't urgent the second it opens.
    let readyAt: Date
    let approvals: Int
    let requestedReviewers: [String]
    let decision: ReviewDecision?
    let authorAvatar: URL?
    let additions: Int
    let deletions: Int
    let viewerReview: ViewerReview?

    /// True when you have already done your part on this one.
    ///
    /// A submitted review of any kind counts — a comment-only pass is still
    /// having read the code. A pending (unsubmitted) draft doesn't, and neither
    /// does a dismissed review, because the team no longer has your verdict.
    var isSettledForViewer: Bool {
        guard let viewerReview, viewerReview.coversHead else { return false }
        switch viewerReview.state {
        case .commented, .approved, .changesRequested: return true
        case .pending, .dismissed: return false
        }
    }

    /// True when the PR is blocked on review.
    ///
    /// When GitHub has an opinion — the repo has a protection rule — that
    /// opinion decides. When it doesn't, `includeUnreviewed` picks the rule:
    /// on, any unapproved PR counts; off, only ones with a reviewer requested.
    func isBlockedOnReview(includeUnreviewed: Bool) -> Bool {
        switch decision {
        case .reviewRequired:
            return true
        case .approved, .changesRequested:
            return false
        case nil:
            guard approvals == 0 else { return false }
            return includeUnreviewed || !requestedReviewers.isEmpty
        }
    }

    var age: TimeInterval { Date().timeIntervalSince(readyAt) }

    /// True when the signed-in user is personally on the hook for this one.
    ///
    /// Reviewing settles the obligation even when the PR stays blocked: GitHub
    /// usually drops the review request once you submit, but a repo needing two
    /// approvals keeps it, and being asked twice for work you have done is
    /// exactly the nagging this avoids.
    func awaits(_ login: String?) -> Bool {
        guard let login, !isSettledForViewer else { return false }
        return requestedReviewers.contains { $0.caseInsensitiveCompare(login) == .orderedSame }
    }

    var totalChanges: Int { additions + deletions }

    /// A rough read on how long this will take, so the queue can offer a next
    /// action with a real cost attached rather than an undifferentiated list.
    /// Deliberately coarse — it exists to separate "before coffee" from "block
    /// out the afternoon", not to be accurate.
    var estimatedMinutes: Int {
        Int(min(max((3.0 + Double(totalChanges) / 25.0).rounded(), 2), 90))
    }

    var sizeDescription: String {
        totalChanges < 1000
            ? "\(totalChanges) lines"
            : String(format: "%.1fk lines", Double(totalChanges) / 1000)
    }

    /// Compact so it never crowds the age out of the row: 1240 reads as 1.2k.
    var churn: String {
        func short(_ n: Int) -> String {
            n < 1000 ? String(n) : String(format: "%.1fk", Double(n) / 1000)
        }
        return "±\(short(additions + deletions))"
    }

    var ageDescription: String {
        let hours = age / 3600
        if hours < 1 { return "\(max(1, Int(age / 60)))m" }
        if hours < 24 { return "\(Int(hours))h" }
        let days = Int(hours / 24)
        return days < 365 ? "\(days)d" : "\(days / 365)y"
    }

    /// Picks the one PR to put in front of someone.
    ///
    /// A backlog is paralysing; a single recommendation with a cost attached is
    /// not. Prefers what is genuinely yours, then what nobody has claimed, and
    /// within that balances age against size — an old, small review is the one
    /// most worth clearing right now.
    static func nextUp(from queue: [PullRequest], threshold: Double, viewer: String?) -> PullRequest? {
        // Never recommend work you have already done. If that empties the
        // queue there is no next action to offer, and the card should go.
        let live = queue.filter { !$0.isSettledForViewer }
        guard !live.isEmpty else { return nil }

        let requested = live.filter { $0.awaits(viewer) }
        let unclaimed = live.filter { $0.requestedReviewers.isEmpty && $0.author != viewer }
        let pool = !requested.isEmpty ? requested : (!unclaimed.isEmpty ? unclaimed : live)

        return pool.max { a, b in
            let sa = a.nextUpScore(threshold: threshold), sb = b.nextUpScore(threshold: threshold)
            // Older wins ties, so the choice is stable between refreshes.
            return sa == sb ? a.readyAt > b.readyAt : sa < sb
        }
    }

    /// Age dominates; size breaks the deadlock between similarly stale PRs.
    func nextUpScore(threshold: Double) -> Double {
        let age = min(max(age / (max(1, threshold) * 86_400), 0), 1)
        let smallness = 1 / (1 + Double(totalChanges) / 200)
        return age * 0.7 + smallness * 0.3
    }

    /// Spelled out for the tooltip and for accessibility, where the terse
    /// badge would be guesswork.
    var ageSpelled: String {
        let hours = age / 3600
        if hours < 1 { return "opened minutes ago" }
        if hours < 24 { return "opened \(Int(hours)) hours ago" }
        let days = Int(hours / 24)
        return "waiting \(days) day\(days == 1 ? "" : "s")"
    }
}
