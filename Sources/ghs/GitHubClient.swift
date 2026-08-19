import Foundation

enum GitHubError: LocalizedError {
    case notAuthenticated
    case badStatus(Int)
    case api(String)
    case rateLimited(resetAt: Date?)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "No GitHub token. Run `gh auth login`, or add a token in Settings."
        case .badStatus(let code):
            return "GitHub returned HTTP \(code)."
        case .api(let message):
            return message
        case .rateLimited(let reset):
            guard let reset else { return "Rate limited by GitHub." }
            let f = RelativeDateTimeFormatter()
            return "Rate limited — resets \(f.localizedString(for: reset, relativeTo: Date()))."
        }
    }
}

/// One GraphQL search covers every watched repo at once, so adding a repo to the
/// watch list costs nothing extra against the hourly rate limit.
struct GitHubClient {
    let token: String
    private let endpoint = URL(string: "https://api.github.com/graphql")!

    private static let query = """
    query($q: String!, $cursor: String) {
      viewer { login }
      search(query: $q, type: ISSUE, first: 50, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          ... on PullRequest {
            id
            number
            title
            url
            createdAt
            additions
            deletions
            author { login avatarUrl(size: 64) }
            repository { nameWithOwner }
            headRefOid
            reviewDecision
            viewerLatestReview { state commit { oid } }
            latestOpinionatedReviews(first: 50, writersOnly: true) { nodes { state } }
            reviewRequests(first: 25) {
              nodes {
                requestedReviewer {
                  ... on User { login }
                  ... on Team { name }
                }
              }
            }
            timelineItems(last: 1, itemTypes: [READY_FOR_REVIEW_EVENT]) {
              nodes { ... on ReadyForReviewEvent { createdAt } }
            }
          }
        }
      }
    }
    """

    struct Snapshot {
        var pullRequests: [PullRequest] = []
        var viewerLogin: String?
    }

    func fetchOpenPullRequests(in repos: [WatchedRepo]) async throws -> Snapshot {
        guard !repos.isEmpty else { return Snapshot() }

        // `draft:false` and `archived:false` are cheap server-side filters. We
        // deliberately don't add `review:required` here: repos with no branch
        // protection report a null reviewDecision and would be filtered out,
        // so the blocked-on-review decision happens client side instead.
        let scope = repos.map { "repo:\($0.nameWithOwner)" }.joined(separator: " ")
        let q = "is:open is:pr draft:false archived:false \(scope)"

        var snapshot = Snapshot()
        var cursor: String?
        var page = 0

        repeat {
            let response = try await send(query: Self.query, variables: ["q": q, "cursor": cursor])
            snapshot.viewerLogin = response.data.viewer?.login
            snapshot.pullRequests.append(
                contentsOf: response.data.search.nodes.compactMap(PullRequest.init(node:))
            )
            cursor = response.data.search.pageInfo.hasNextPage ? response.data.search.pageInfo.endCursor : nil
            page += 1
        } while cursor != nil && page < 4  // 200 open PRs is plenty for a menu

        return snapshot
    }

    private func send(query: String, variables: [String: String?]) async throws -> GraphQLResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ghs-menubar", forHTTPHeaderField: "User-Agent")
        let jsonVariables = variables.mapValues { $0.map { $0 as Any } ?? NSNull() }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": query, "variables": jsonVariables] as [String: Any]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.badStatus(0) }

        if http.statusCode == 403 || http.statusCode == 429 {
            let reset = (http.value(forHTTPHeaderField: "X-RateLimit-Reset")).flatMap(Double.init)
                .map { Date(timeIntervalSince1970: $0) }
            throw GitHubError.rateLimited(resetAt: reset)
        }
        guard (200..<300).contains(http.statusCode) else { throw GitHubError.badStatus(http.statusCode) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GraphQLResponse.self, from: data)
        if let message = decoded.errors?.first?.message { throw GitHubError.api(message) }
        return decoded
    }
}

// MARK: - Wire format

private struct GraphQLResponse: Decodable {
    struct Errors: Decodable { let message: String }
    let data: DataBlock
    let errors: [Errors]?

    struct DataBlock: Decodable {
        let search: Search
        let viewer: Viewer?
    }
    struct Viewer: Decodable { let login: String }
    struct Search: Decodable {
        let pageInfo: PageInfo
        let nodes: [Node]
    }
    struct PageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }

    struct Node: Decodable {
        struct Author: Decodable {
            let login: String
            let avatarUrl: URL?
        }
        struct Repository: Decodable { let nameWithOwner: String }
        struct Review: Decodable { let state: String }
        struct Reviews: Decodable { let nodes: [Review]? }
        struct Commit: Decodable { let oid: String? }
        struct ViewerReviewNode: Decodable {
            let state: String?
            let commit: Commit?
        }
        struct Reviewer: Decodable {
            let login: String?
            let name: String?
            var displayName: String? { login ?? name }
        }
        struct ReviewRequest: Decodable { let requestedReviewer: Reviewer? }
        struct ReviewRequests: Decodable { let nodes: [ReviewRequest]? }
        struct TimelineEvent: Decodable { let createdAt: Date? }
        struct Timeline: Decodable { let nodes: [TimelineEvent]? }

        let id: String?
        let number: Int?
        let title: String?
        let url: URL?
        let createdAt: Date?
        let additions: Int?
        let deletions: Int?
        let author: Author?
        let repository: Repository?
        let headRefOid: String?
        let reviewDecision: ReviewDecision?
        let viewerLatestReview: ViewerReviewNode?
        let latestOpinionatedReviews: Reviews?
        let reviewRequests: ReviewRequests?
        let timelineItems: Timeline?
    }
}

private extension PullRequest {
    /// `search(type: ISSUE)` can also return issues, which decode as empty
    /// nodes — returning nil here drops them.
    init?(node: GraphQLResponse.Node) {
        guard let id = node.id, let number = node.number, let title = node.title,
              let url = node.url, let createdAt = node.createdAt,
              let repo = node.repository?.nameWithOwner
        else { return nil }

        self.id = id
        self.number = number
        self.title = title
        self.url = url
        self.createdAt = createdAt
        self.repo = repo
        self.author = node.author?.login ?? "ghost"
        self.authorAvatar = node.author?.avatarUrl
        self.additions = node.additions ?? 0
        self.deletions = node.deletions ?? 0
        self.readyAt = node.timelineItems?.nodes?.compactMap(\.createdAt).last ?? createdAt
        self.approvals = node.latestOpinionatedReviews?.nodes?.filter { $0.state == "APPROVED" }.count ?? 0
        self.requestedReviewers = node.reviewRequests?.nodes?.compactMap { $0.requestedReviewer?.displayName } ?? []
        self.decision = node.reviewDecision
        self.viewerReview = node.viewerLatestReview.flatMap { review in
            guard let state = review.state.flatMap(ViewerReview.State.init(rawValue:)) else { return nil }
            // Either side being unknown counts as covering head: better to
            // treat a review as done than to re-request work already done.
            let coversHead: Bool
            if let reviewed = review.commit?.oid, let head = node.headRefOid {
                coversHead = reviewed == head
            } else {
                coversHead = true
            }
            return ViewerReview(state: state, coversHead: coversHead)
        }
    }
}
