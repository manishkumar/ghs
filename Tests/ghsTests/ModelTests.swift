import Foundation
import Testing
@testable import ghs

@Suite struct WatchedRepoTests {
    @Test(arguments: [
        "cli/cli",
        "  cli/cli  ",
        "https://github.com/cli/cli",
        "https://github.com/cli/cli/pull/123",
        "git@github.com:cli/cli.git",
        "github.com/cli/cli",
    ])
    func normalizesAcceptedInput(_ input: String) {
        #expect(WatchedRepo(input: input)?.nameWithOwner == "cli/cli")
    }

    @Test(arguments: ["", "cli", "/", "https://github.com/cli", "../.."])
    func rejectsIncompleteInput(_ input: String) {
        #expect(WatchedRepo(input: input) == nil)
    }
}

@Suite struct PullRequestTests {
    private func makePR(
        decision: ReviewDecision?,
        approvals: Int = 0,
        reviewers: [String] = [],
        daysOld: Double = 1,
        additions: Int = 0,
        deletions: Int = 0,
        viewerReview: ViewerReview? = nil
    ) -> PullRequest {
        let date = Date().addingTimeInterval(-daysOld * 86_400)
        return PullRequest(
            id: "1", number: 1, title: "t",
            url: URL(string: "https://github.com/a/b/pull/1")!,
            author: "a", repo: "a/b", createdAt: date, readyAt: date,
            approvals: approvals, requestedReviewers: reviewers, decision: decision,
            authorAvatar: nil, additions: additions, deletions: deletions,
            viewerReview: viewerReview
        )
    }

    @Test(arguments: [true, false])
    func githubsVerdictWinsWhateverTheSetting(_ includeUnreviewed: Bool) {
        #expect(makePR(decision: .reviewRequired).isBlockedOnReview(includeUnreviewed: includeUnreviewed))
        #expect(!makePR(decision: .approved).isBlockedOnReview(includeUnreviewed: includeUnreviewed))
        // Changes requested is blocked on the author, not on a reviewer.
        #expect(!makePR(decision: .changesRequested).isBlockedOnReview(includeUnreviewed: includeUnreviewed))
    }

    /// The case that hid the user's own PRs: a personal repo with no branch
    /// protection and nobody formally requested.
    @Test func unprotectedRepoWithNoReviewerCountsOnlyWhenIncluded() {
        let pr = makePR(decision: nil)
        #expect(pr.isBlockedOnReview(includeUnreviewed: true))
        #expect(!pr.isBlockedOnReview(includeUnreviewed: false))
    }

    @Test func unprotectedRepoWithAReviewerAlwaysCounts() {
        let pr = makePR(decision: nil, reviewers: ["someone"])
        #expect(pr.isBlockedOnReview(includeUnreviewed: true))
        #expect(pr.isBlockedOnReview(includeUnreviewed: false))
    }

    @Test(arguments: [true, false])
    func anApprovalUnblocksAnUnprotectedRepo(_ includeUnreviewed: Bool) {
        let pr = makePR(decision: nil, approvals: 1, reviewers: ["someone"])
        #expect(!pr.isBlockedOnReview(includeUnreviewed: includeUnreviewed))
    }

    @Test func awaitsViewerIgnoringCase() {
        let pr = makePR(decision: .reviewRequired, reviewers: ["ManishKumar"])
        #expect(pr.awaits("manishkumar"))
        #expect(!pr.awaits("someone-else"))
        #expect(!pr.awaits(nil))
    }

    /// The whole point of tracking the viewer's own review: a repo that needs
    /// two approvals keeps asking you for one you already gave.
    @Test func reviewingSettlesTheObligationEvenWhileThePRStaysBlocked() {
        let pr = makePR(
            decision: .reviewRequired,
            reviewers: ["me"],
            viewerReview: ViewerReview(state: .approved, coversHead: true)
        )
        #expect(pr.isBlockedOnReview(includeUnreviewed: true))
        #expect(pr.isSettledForViewer)
        #expect(!pr.awaits("me"))
    }

    @Test func aCommentOnlyPassStillCountsAsHavingReadTheCode() {
        #expect(makePR(decision: .reviewRequired,
                       viewerReview: ViewerReview(state: .commented, coversHead: true))
            .isSettledForViewer)
        #expect(makePR(decision: .reviewRequired,
                       viewerReview: ViewerReview(state: .changesRequested, coversHead: true))
            .isSettledForViewer)
    }

    @Test func anUnsubmittedOrDismissedReviewSettlesNothing() {
        #expect(!makePR(decision: .reviewRequired,
                        viewerReview: ViewerReview(state: .pending, coversHead: true))
            .isSettledForViewer)
        #expect(!makePR(decision: .reviewRequired,
                        viewerReview: ViewerReview(state: .dismissed, coversHead: true))
            .isSettledForViewer)
    }

    /// New commits since your review mean there is code here you haven't read,
    /// so the row goes back to asking.
    @Test func aPushSinceYourReviewReopensTheObligation() {
        let pr = makePR(
            decision: .reviewRequired,
            reviewers: ["me"],
            viewerReview: ViewerReview(state: .approved, coversHead: false)
        )
        #expect(!pr.isSettledForViewer)
        #expect(pr.awaits("me"))
    }

    @Test func ageDescriptionPicksAUnit() {
        #expect(makePR(decision: nil, daysOld: 3).ageDescription == "3d")
        #expect(makePR(decision: nil, daysOld: 0.25).ageDescription == "6h")
        #expect(makePR(decision: nil, daysOld: 400).ageDescription == "1y")
    }

    @Test func churnStaysCompact() {
        #expect(makePR(decision: nil, additions: 12, deletions: 16).churn == "±28")
        #expect(makePR(decision: nil, additions: 1240, deletions: 880).churn == "±2.1k")
    }
}

@Suite struct NextUpTests {
    private func pr(
        _ id: String, daysOld: Double, changes: Int,
        reviewers: [String] = [], author: String = "someone",
        viewerReview: ViewerReview? = nil
    ) -> PullRequest {
        let date = Date().addingTimeInterval(-daysOld * 86_400)
        return PullRequest(
            id: id, number: 1, title: id,
            url: URL(string: "https://github.com/a/b/pull/1")!,
            author: author, repo: "a/b", createdAt: date, readyAt: date,
            approvals: 0, requestedReviewers: reviewers, decision: .reviewRequired,
            authorAvatar: nil, additions: changes, deletions: 0,
            viewerReview: viewerReview
        )
    }

    @Test func prefersWhatIsActuallyYours() {
        let queue = [
            pr("ancient-but-not-yours", daysOld: 60, changes: 50),
            pr("yours", daysOld: 2, changes: 50, reviewers: ["me"]),
        ]
        #expect(PullRequest.nextUp(from: queue, threshold: 7, viewer: "me")?.id == "yours")
    }

    @Test func fallsBackToUnclaimedWhenNothingIsYours() {
        let queue = [
            pr("claimed", daysOld: 30, changes: 50, reviewers: ["someone-else"]),
            pr("unclaimed", daysOld: 4, changes: 50),
        ]
        #expect(PullRequest.nextUp(from: queue, threshold: 7, viewer: "me")?.id == "unclaimed")
    }

    @Test func neverRecommendsYourOwnPullRequestAsUnclaimedWork() {
        let queue = [
            pr("mine", daysOld: 30, changes: 10, author: "me"),
            pr("theirs", daysOld: 3, changes: 10),
        ]
        #expect(PullRequest.nextUp(from: queue, threshold: 7, viewer: "me")?.id == "theirs")
    }

    @Test func neverRecommendsSomethingYouHaveAlreadyReviewed() {
        let queue = [
            pr("done", daysOld: 60, changes: 10, reviewers: ["me"],
               viewerReview: ViewerReview(state: .approved, coversHead: true)),
            pr("undone", daysOld: 3, changes: 10),
        ]
        #expect(PullRequest.nextUp(from: queue, threshold: 7, viewer: "me")?.id == "undone")
    }

    @Test func offersNothingWhenYouHaveReviewedEverything() {
        let queue = [
            pr("done", daysOld: 60, changes: 10,
               viewerReview: ViewerReview(state: .approved, coversHead: true)),
        ]
        #expect(PullRequest.nextUp(from: queue, threshold: 7, viewer: "me") == nil)
    }

    @Test func breaksTiesBySizeSoAQuickWinComesFirst() {
        let queue = [
            pr("huge", daysOld: 10, changes: 4000, reviewers: ["me"]),
            pr("small", daysOld: 10, changes: 20, reviewers: ["me"]),
        ]
        #expect(PullRequest.nextUp(from: queue, threshold: 7, viewer: "me")?.id == "small")
    }

    @Test func ageStillOutweighsSize() {
        let queue = [
            pr("stale-and-big", daysOld: 14, changes: 900, reviewers: ["me"]),
            pr("fresh-and-tiny", daysOld: 0.1, changes: 5, reviewers: ["me"]),
        ]
        #expect(PullRequest.nextUp(from: queue, threshold: 7, viewer: "me")?.id == "stale-and-big")
    }

    @Test func choiceIsStableAcrossRepeatedCalls() {
        let queue = [
            pr("a", daysOld: 10, changes: 100, reviewers: ["me"]),
            pr("b", daysOld: 10, changes: 100, reviewers: ["me"]),
        ]
        let first = PullRequest.nextUp(from: queue, threshold: 7, viewer: "me")?.id
        for _ in 0..<20 {
            #expect(PullRequest.nextUp(from: queue, threshold: 7, viewer: "me")?.id == first)
        }
    }

    @Test func emptyQueueRecommendsNothing() {
        #expect(PullRequest.nextUp(from: [], threshold: 7, viewer: "me") == nil)
    }

    @Test func estimateStaysWithinUsefulBounds() {
        #expect(pr("tiny", daysOld: 1, changes: 0).estimatedMinutes == 3)
        #expect(pr("small", daysOld: 1, changes: 40).estimatedMinutes == 5)
        #expect(pr("enormous", daysOld: 1, changes: 100_000).estimatedMinutes == 90)
    }

    @Test func sizeReadsInLines() {
        #expect(pr("a", daysOld: 1, changes: 252).sizeDescription == "252 lines")
        #expect(pr("b", daysOld: 1, changes: 2120).sizeDescription == "2.1k lines")
    }
}

@Suite struct ThemeTests {
    @Test func fractionIsClampedToTheThreshold() {
        #expect(Theme.fraction(forAge: 0, threshold: 7) == 0)
        #expect(abs(Theme.fraction(forAge: 7 * 86_400, threshold: 7) - 1) < 0.001)
        #expect(abs(Theme.fraction(forAge: 700 * 86_400, threshold: 7) - 1) < 0.001)
    }

    @Test func fractionRisesWithAge() {
        var previous = -1.0
        for day in stride(from: 0.0, through: 7.0, by: 0.5) {
            let value = Theme.fraction(forAge: day * 86_400, threshold: 7)
            #expect(value > previous)
            previous = value
        }
    }

    @Test func zeroThresholdDoesNotDivideByZero() {
        #expect(abs(Theme.fraction(forAge: 86_400, threshold: 0) - 1) < 0.001)
    }
}
