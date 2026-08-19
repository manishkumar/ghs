import Foundation

/// `ghs --list` runs the whole data path (token resolution → GraphQL → the
/// blocked-on-review filter) and prints the result, without launching any UI.
/// Handy for checking auth and repo config when the menu shows nothing.
enum DebugCLI {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--list") else { return }

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            defer { semaphore.signal() }

            guard let credential = GitHubAuth.resolve() else {
                print(GitHubError.notAuthenticated.localizedDescription)
                return
            }
            print("auth: \(credential.source.rawValue)")

            let settings = AppSettings()
            // `--repos owner/name,owner/name` checks a set of repos without
            // touching the saved config — useful before anything is configured,
            // and it keeps the documentation captures off private repos.
            let repos = repoOverride() ?? settings.repos
            guard !repos.isEmpty else {
                print("no repositories watched")
                return
            }
            print("watching: \(repos.map(\.nameWithOwner).joined(separator: ", "))")

            do {
                let snapshot = try await GitHubClient(token: credential.token)
                    .fetchOpenPullRequests(in: repos)
                let all = snapshot.pullRequests
                let blocked = all
                    .filter { $0.isBlockedOnReview(includeUnreviewed: settings.includeUnreviewed) }
                    .sorted { $0.readyAt < $1.readyAt }
                print("open: \(all.count)  blocked on review: \(blocked.count)\n")
                for pr in blocked.prefix(15) {
                    let decision = pr.decision?.rawValue ?? "no-policy"
                    let title = pr.title.count > 56 ? pr.title.prefix(55) + "…" : pr.title
                    print("  \(pr.ageDescription.padded(4)) \(pr.repo)#\(pr.number)  \(title)")
                    print("       \(decision), \(pr.approvals) approvals, reviewers: \(pr.requestedReviewers.joined(separator: ", "))")
                }
            } catch {
                print("error: \(error.localizedDescription)")
            }
        }
        semaphore.wait()
        exit(0)
    }

    private static func repoOverride() -> [WatchedRepo]? {
        guard let index = CommandLine.arguments.firstIndex(of: "--repos"),
              CommandLine.arguments.count > index + 1
        else { return nil }
        let parsed = CommandLine.arguments[index + 1]
            .split(separator: ",")
            .compactMap { WatchedRepo(input: String($0).trimmingCharacters(in: .whitespaces)) }
        return parsed.isEmpty ? nil : parsed
    }
}

private extension String {
    func padded(_ width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
