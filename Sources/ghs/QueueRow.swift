import AppKit
import SwiftUI

struct QueueRow: View {
    let pr: PullRequest
    let isNew: Bool
    let awaitsViewer: Bool
    let isSelected: Bool
    let threshold: Double
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var didCopy = false

    private var oxide: Color {
        Theme.oxidation(forAge: pr.age, threshold: threshold, scheme: scheme)
    }

    /// You have already reviewed this one. It stays in the queue — it is still
    /// blocked on somebody — but it stops claiming any of your attention.
    private var isSettled: Bool { pr.isSettledForViewer }

    var body: some View {
        HStack(spacing: 0) {
            // The signature element. Every row's rail is full-bleed and the
            // rows are flush, so the rails join into one continuous column that
            // oxidises from rust down to patina as the queue gets younger.
            // A settled row keeps its place in the decay column but sits back
            // from it: the rail drops to a fraction of its oxide, so the eye
            // running down the gradient reads a gap where you have done yours.
            Rectangle()
                .fill(oxide.opacity(isSettled ? Theme.settledRail : 1))
                .frame(width: Theme.railWidth)

            HStack(alignment: .center, spacing: 10) {
                Avatar(url: pr.authorAvatar, login: pr.author)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if isSettled {
                            // The counterpart to the dot: not an obligation,
                            // a receipt.
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .help("You have already reviewed this")
                        } else if awaitsViewer {
                            // A filled dot in the oxide colour: this one is
                            // personally yours, and it is this old.
                            Circle().fill(oxide).frame(width: 5, height: 5)
                                .help("Your review is requested")
                        }
                        Text(pr.title)
                            .font(Theme.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if isNew {
                            Text("new")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                        }
                    }

                    HStack(spacing: 5) {
                        Text(pr.repo)
                            .font(Theme.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        // String(), not interpolation: Text applies locale digit
                        // grouping to an Int, which turns PR #10423 into #10,423.
                        Text("#" + String(pr.number))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(reviewState)
                            .font(Theme.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(pr.ageDescription)
                        .font(Theme.numeric)
                        // The age still shows — the PR is still ageing — but it
                        // stops being coloured at you.
                        .foregroundStyle(isSettled ? Color.secondary : oxide)
                    if pr.approvals > 0 {
                        // Partial approval is the more useful second fact when
                        // there is one: it says how close this is to unblocking.
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                            Text(String(pr.approvals)).font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Text(pr.churn)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Copy stays out of the way until the row is under the cursor,
                // so the resting state has exactly one affordance: open it.
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
                    didCopy = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "link")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 18, height: 18)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(isSelected ? 1 : 0)
                .help("Copy link")
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .opacity(isSettled ? Theme.settledContent : 1)
        }
        .background(isSelected ? Color.primary.opacity(0.055) : .clear)
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .help("\(pr.repo) #\(pr.number) — \(pr.ageSpelled)\(isSettled ? ", already reviewed by you" : ""). Click to open on GitHub.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(pr.title), \(pr.repo) number \(pr.number), \(pr.ageSpelled)"
                + (isSettled ? ", already reviewed by you" : "")
        )
    }

    /// Everything in this list is blocked by definition, so the row never says
    /// so — it says who it is blocked on.
    private var reviewState: String {
        if isSettled {
            // Your review dropped you from the request list, so whoever is
            // still named here is who the PR is actually waiting on now.
            if pr.requestedReviewers.isEmpty { return "you reviewed" }
            if pr.requestedReviewers.count == 1 {
                return "you reviewed · waiting on " + pr.requestedReviewers[0]
            }
            return "you reviewed · waiting on \(pr.requestedReviewers.count) reviewers"
        }
        if pr.requestedReviewers.isEmpty { return "no reviewer yet" }
        if pr.requestedReviewers.count == 1 { return "waiting on " + pr.requestedReviewers[0] }
        return "waiting on \(pr.requestedReviewers.count) reviewers"
    }
}
