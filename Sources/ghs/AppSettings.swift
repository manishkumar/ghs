import Foundation
import Observation

@Observable
final class AppSettings {
    private enum Key {
        static let repos = "watchedRepos"
        static let interval = "pollIntervalSeconds"
        static let urgentAfterDays = "urgentAfterDays"
        static let includeUnreviewed = "includeUnreviewed"
    }

    /// GitHub allows 5000 points/hour; one poll is one point. Even so, nothing
    /// below 60s — a resident menu bar app polls forever.
    static let minimumInterval: TimeInterval = 60

    // Clamping happens in explicit setters, never in `didSet`.
    //
    // `@Observable` rewrites a stored property into a computed one over hidden
    // storage, so assigning to the property from inside its own `didSet` goes
    // back through the public setter and recurses until the stack overflows.
    // Plain stored properties don't behave that way, which is what makes the
    // pattern look safe. Do not reintroduce it.

    private var storedRepos: [WatchedRepo]
    private var storedPollInterval: TimeInterval
    private var storedUrgentAfterDays: Double
    private var storedIncludeUnreviewed: Bool

    var repos: [WatchedRepo] {
        get { storedRepos }
        set {
            storedRepos = newValue
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.repos)
        }
    }

    var pollInterval: TimeInterval {
        get { storedPollInterval }
        set {
            let clamped = max(Self.minimumInterval, newValue)
            storedPollInterval = clamped
            defaults.set(clamped, forKey: Key.interval)
        }
    }

    /// Age at which the urgency ramp saturates. Beyond this everything looks
    /// equally hot, rather than the scale stretching out forever.
    var urgentAfterDays: Double {
        get { storedUrgentAfterDays }
        set {
            let clamped = min(max(newValue, 1), 365)
            storedUrgentAfterDays = clamped
            defaults.set(clamped, forKey: Key.urgentAfterDays)
        }
    }

    /// Repos with no branch protection report no `reviewDecision` at all, so
    /// GitHub never says their PRs need review. Off, such a PR only counts once
    /// somebody is formally requested — which silently hides open PRs in
    /// personal repos, where nobody ever requests anyone.
    var includeUnreviewed: Bool {
        get { storedIncludeUnreviewed }
        set {
            storedIncludeUnreviewed = newValue
            defaults.set(newValue, forKey: Key.includeUnreviewed)
        }
    }

    /// Settings live in an explicitly named suite, not `.standard`.
    ///
    /// A bare `swift build` binary and the packaged `.app` have different
    /// process identities, so `.standard` gives them different stores — and
    /// `ghs --list`, whose whole job is to explain what the menu bar is doing,
    /// would report "no repositories watched" while the app showed a full
    /// queue. Naming the suite makes both read the same file.
    static let suiteName = "com.manishkumar.ghs"
    static let sharedDefaults = UserDefaults(suiteName: suiteName) ?? .standard

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppSettings.sharedDefaults) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Key.repos)
            .flatMap { try? JSONDecoder().decode([WatchedRepo].self, from: $0) }
        self.storedRepos = stored ?? []
        let interval = defaults.double(forKey: Key.interval)
        self.storedPollInterval = interval > 0 ? max(Self.minimumInterval, interval) : 120
        let urgent = defaults.double(forKey: Key.urgentAfterDays)
        self.storedUrgentAfterDays = urgent > 0 ? min(max(urgent, 1), 365) : 7
        self.storedIncludeUnreviewed = defaults.object(forKey: Key.includeUnreviewed) as? Bool ?? true
    }

    @discardableResult
    func addRepo(_ input: String) -> Bool {
        guard let repo = WatchedRepo(input: input) else { return false }
        guard !repos.contains(repo) else { return true }
        repos.append(repo)
        repos.sort { $0.nameWithOwner.localizedCaseInsensitiveCompare($1.nameWithOwner) == .orderedAscending }
        return true
    }

    func removeRepos(_ ids: Set<WatchedRepo.ID>) {
        repos.removeAll { ids.contains($0.id) }
    }

}
