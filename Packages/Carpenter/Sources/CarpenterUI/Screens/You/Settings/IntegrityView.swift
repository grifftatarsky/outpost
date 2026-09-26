import CarpenterKit
import SwiftUI

public struct IntegrityView: View {
    @Environment(\.palette) private var palette

    private let report: IntegrityReport
    private let name: (FeedKey) -> String

    public init(report: IntegrityReport, name: @escaping (FeedKey) -> String = { _ in "" }) {
        self.report = report
        self.name = name
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if report.isClean {
                    clean
                } else {
                    if report.hasDiverged { divergence }
                    if report.lastLoad != .complete || report.discardedBytes > 0 { storage }
                    if report.unverifiableOnDisk > 0 { unverifiable }
                    if report.rejectedFromPeers > 0 { rejected }
                    if report.writesFailed > 0 { unwritten }
                    if report.feedsFromOtherMembers > 0 { foreignFeeds }
                }

                if report.sealedForOthers > 0 { carried }

                // COPY BEGIN 33f91dec [NEEDS HUMAN REVIEW]
                Text(
                    "Nothing here is repaired automatically. Two versions of the same message are both kept, because there is no honest way to choose between them.",
                    bundle: .module
                )
                .font(CarpenterFont.caption)
                .foregroundStyle(palette.quaternaryText)
                // COPY END 33f91dec
            }
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.vertical, 16)
        }
        .background(palette.background)
        // COPY BEGIN 38b39113 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("History check", bundle: .module))
        // COPY END 38b39113
    }

    private var clean: some View {
        card {
            // COPY BEGIN cdbe7535 [NEEDS HUMAN REVIEW]
            Label {
                Text("Nothing looks wrong", bundle: .module)
                    .font(CarpenterFont.rowTitle)
            } icon: {
                Image(systemName: "checkmark.seal")
            }
            .foregroundStyle(palette.primaryText)
            // COPY END cdbe7535

            // COPY BEGIN d9ac6664 [NEEDS HUMAN REVIEW]
            Text(
                "Every message on this device is signed by the person who sent it and links to the one before it. That has been checked.",
                bundle: .module
            )
            .font(CarpenterFont.footnote)
            .foregroundStyle(palette.secondaryText)
            // COPY END d9ac6664
        }
    }

    private var divergence: some View {
        card(alarming: true) {
            // COPY BEGIN 4d19badc [NEEDS HUMAN REVIEW]
            Label {
                Text("Two versions of the same history", bundle: .module)
                    .font(CarpenterFont.rowTitle)
            } icon: {
                Image(systemName: "arrow.triangle.branch")
            }
            .foregroundStyle(palette.primaryText)
            // COPY END 4d19badc

            // COPY BEGIN 5fe04702 [NEEDS HUMAN REVIEW]
            Text(
                "A device sent two different messages claiming the same place in its own history. Both are kept. This usually means that device was restored from a backup.",
                bundle: .module
            )
            .font(CarpenterFont.footnote)
            .foregroundStyle(palette.secondaryText)
            // COPY END 5fe04702

            // COPY BEGIN a9304ca1 [NEEDS HUMAN REVIEW]
            ForEach(Array(report.forks.enumerated()), id: \.offset) { _, fork in
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(fork.feed))
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.primaryText)
                    Text(
                        "\(fork.hashes.count) versions at position \(fork.seq)",
                        bundle: .module
                    )
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.secondaryText)
                }
                .padding(.top, 4)
            }
            // COPY END a9304ca1
        }
    }

    private var storage: some View {
        card {
            // COPY BEGIN bf1e96ea [NEEDS HUMAN REVIEW]
            Label {
                Text("The end of the log was unreadable", bundle: .module)
                    .font(CarpenterFont.rowTitle)
            } icon: {
                Image(systemName: "externaldrive.badge.exclamationmark")
            }
            .foregroundStyle(palette.primaryText)
            // COPY END bf1e96ea

            Text(explanation(for: report.lastLoad))
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)

            // COPY BEGIN f8dfbf6e [NEEDS HUMAN REVIEW]
            if report.discardedBytes > 0 {
                Text("\(report.discardedBytes) bytes could not be used.", bundle: .module)
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            // COPY END f8dfbf6e
        }
    }

    private var unverifiable: some View {
        card(alarming: true) {
            // COPY BEGIN 37ffb7a2 [NEEDS HUMAN REVIEW]
            Label {
                Text("Some messages no longer verify", bundle: .module)
                    .font(CarpenterFont.rowTitle)
            } icon: {
                Image(systemName: "xmark.seal")
            }
            .foregroundStyle(palette.primaryText)
            // COPY END 37ffb7a2

            // COPY BEGIN a3c95c74 [NEEDS HUMAN REVIEW]
            Text(
                "\(report.unverifiableOnDisk) messages already on this device failed their signature check and were not shown. Something has altered them.",
                bundle: .module
            )
            .font(CarpenterFont.footnote)
            .foregroundStyle(palette.secondaryText)
            // COPY END a3c95c74
        }
    }

    private var rejected: some View {
        card {
            // COPY BEGIN 35f6c54f [NEEDS HUMAN REVIEW]
            Label {
                Text("Some incoming messages were refused", bundle: .module)
                    .font(CarpenterFont.rowTitle)
            } icon: {
                Image(systemName: "hand.raised")
            }
            .foregroundStyle(palette.primaryText)
            // COPY END 35f6c54f

            // COPY BEGIN 3f4510af [NEEDS HUMAN REVIEW]
            Text(
                "\(report.rejectedFromPeers) messages arrived that did not verify and were discarded. Nothing you can see is affected.",
                bundle: .module
            )
            .font(CarpenterFont.footnote)
            .foregroundStyle(palette.secondaryText)
            // COPY END 3f4510af
        }
    }

    private var unwritten: some View {
        VStack(alignment: .leading, spacing: 6) {
            // COPY BEGIN 34bf02e9 [NEEDS HUMAN REVIEW]
            Label {
                Text("Some history could not be saved", bundle: .module)
                    .font(CarpenterFont.rowTitle)
            } icon: {
                Image(systemName: "externaldrive.badge.exclamationmark")
            }
            .foregroundStyle(palette.primaryText)
            // COPY END 34bf02e9

            // COPY BEGIN 3c2dd86b [NEEDS HUMAN REVIEW]
            Text(
                "^[\(report.writesFailed) piece](inflect: true) of history reached this device and could not be written to it. It is here now and will be gone when the app next starts. Check whether the device is out of space.",
                bundle: .module
            )
            .font(CarpenterFont.footnote)
            .foregroundStyle(palette.secondaryText)
            // COPY END 3c2dd86b
        }
    }

    private var carried: some View {
        VStack(alignment: .leading, spacing: 6) {
            // COPY BEGIN afc8f601 [NEEDS HUMAN REVIEW]
            Label {
                Text("Carried for other people", bundle: .module)
                    .font(CarpenterFont.rowTitle)
            } icon: {
                Image(systemName: "shippingbox")
            }
            .foregroundStyle(palette.primaryText)
            // COPY END afc8f601

            // COPY BEGIN 9092655d [NEEDS HUMAN REVIEW]
            Text(
                "^[\(report.sealedForOthers) message](inflect: true) this device is passing along and cannot read, written by ^[\(report.unmetAuthorsHeld) person](inflect: true) you have not met. This is how a message gets from one phone to another with nothing in between, and none of it is readable here.",
                bundle: .module
            )
            .font(CarpenterFont.footnote)
            .foregroundStyle(palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            // COPY END 9092655d
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .groupedRowSurface()
    }

    private var foreignFeeds: some View {
        VStack(alignment: .leading, spacing: 6) {
            // COPY BEGIN 9dace810 [NEEDS HUMAN REVIEW]
            Label {
                Text("Another member's history is on this account", bundle: .module)
                    .font(CarpenterFont.rowTitle)
            } icon: {
                Image(systemName: "person.2.slash")
            }
            .foregroundStyle(palette.primaryText)
            // COPY END 9dace810

            // COPY BEGIN 81cb9ee5 [NEEDS HUMAN REVIEW]
            Text(
                "^[\(report.feedsFromOtherMembers) feed](inflect: true) written by a different member arrived in this Apple Account's storage and was ignored. Nothing of yours is affected, and nothing of theirs was read.",
                bundle: .module
            )
            .font(CarpenterFont.footnote)
            .foregroundStyle(palette.secondaryText)
            // COPY END 81cb9ee5
        }
    }

    // COPY BEGIN 7e67d2e5 [NEEDS HUMAN REVIEW]
    private func explanation(for termination: LogTermination) -> LocalizedStringKey {
        switch termination {
        case .complete:
            "The log was read to the end."
        case .tornTail:
            "The app stopped part-way through saving, so the last thing written was incomplete. Only that one entry was lost."
        case .recordTooLarge:
            "An entry claimed a size past what this app will read. It was refused rather than opened."
        case .undecodableRecord:
            "A complete entry could not be read. Either it is damaged, or it was written by a newer version."
        }
    }
    // COPY END 7e67d2e5

    private func card(
        alarming: Bool = false, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            palette.elevatedSurface,
            in: .rect(cornerRadius: CarpenterMetrics.cardRadius, style: .continuous)
        )
        .overlay {
            if alarming {
                RoundedRectangle(
                    cornerRadius: CarpenterMetrics.cardRadius, style: .continuous
                )
                .strokeBorder(palette.accentColor, lineWidth: CarpenterMetrics.hairline * 2)
            }
        }
    }
}

#Preview("Nothing wrong") {
    NavigationStack { IntegrityView(report: IntegrityReport()) }
        .themed(.default)
}

private func divergedFixture() -> IntegrityReport {
    var report = IntegrityReport()
    report.forks = [
        Fork(
            feed: FeedKey(
                author: ParticipantID(rawValue: Data([1])), device: DeviceID(rawValue: Data([2]))),
            seq: 42,
            hashes: [EntryHash(rawValue: Data([1])), EntryHash(rawValue: Data([2]))])
    ]
    report.lastLoad = .tornTail
    report.discardedBytes = 118
    report.unverifiableOnDisk = 2
    report.rejectedFromPeers = 1
    return report
}

#Preview("Diverged") {
    NavigationStack {
        IntegrityView(report: divergedFixture(), name: { _ in "Nora’s iPhone" })
    }
    .themed(.default)
}
