import CarpenterKit
import SwiftUI

public struct NotGoneHelp: Sendable {
    public var reason: String?
    public var onChangeWait: (@MainActor @Sendable () -> Void)?
    public var onShowWaiting: (@MainActor @Sendable () -> Void)?

    public init(
        reason: String? = nil, onChangeWait: (@MainActor @Sendable () -> Void)? = nil,
        onShowWaiting: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.reason = reason
        self.onChangeWait = onChangeWait
        self.onShowWaiting = onShowWaiting
    }
}

extension EnvironmentValues {
    @Entry public var notGoneHelp = NotGoneHelp()
}

public struct RoomNotGoneChoice: Sendable {
    public let wait: NotGoneWait
    public let onChange: @Sendable (NotGoneWait) async -> Void

    public init(wait: NotGoneWait, onChange: @escaping @Sendable (NotGoneWait) async -> Void) {
        self.wait = wait
        self.onChange = onChange
    }
}

struct NotGoneMark: View {
    @Environment(\.palette) private var palette
    @Environment(\.notGoneHelp) private var help

    let notGone: NotGone
    let sentAt: Date

    @ScaledMetric(relativeTo: .caption2) private var box = CarpenterMetrics.deliveryMarkBox
    @State private var explaining = false
    @State private var next: Next?

    private enum Next { case setting, waiting }

    var body: some View {
        Button { explaining = true } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: box + 2, weight: .semibold))
                .foregroundStyle(palette.notGone)
        }
        .buttonStyle(.plain)
        .tappable()
        .padding(-max(0, CarpenterMetrics.hitTarget - box - 2) / 2)
        .accessibilityLabel(Text("Not sent yet", bundle: .module))
        .accessibilityHint(Text("Says why.", bundle: .module))
        .sheet(
            isPresented: $explaining,
            onDismiss: {
                let chosen = next
                next = nil
                switch chosen {
                case .setting: help.onChangeWait?()
                case .waiting: help.onShowWaiting?()
                case nil: break
                }
            }
        ) {
            NotGoneExplanation(
                notGone: notGone, sentAt: sentAt, reason: help.reason,
                onChangeWait: help.onChangeWait == nil
                    ? nil
                    : {
                        next = .setting
                        explaining = false
                    },
                onShowWaiting: help.onShowWaiting == nil
                    ? nil
                    : {
                        next = .waiting
                        explaining = false
                    })
        }
    }
}

struct NotGoneExplanation: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let notGone: NotGone
    let sentAt: Date
    let reason: String?
    let onChangeWait: (() -> Void)?
    let onShowWaiting: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let reason {
                        Text(verbatim: reason)
                            .font(CarpenterFont.bubble)
                            .foregroundStyle(palette.primaryText)
                    }

                    whatHappened
                        .font(CarpenterFont.bubble)
                        .foregroundStyle(palette.primaryText)

                    Text("Sent \(sentAt, format: .dateTime.weekday(.wide).day().month().hour().minute()).", bundle: .module)
                        .font(CarpenterFont.footnote)
                        .foregroundStyle(palette.secondaryText)

                    Text(
                        "It keeps trying on its own, every time this app syncs. Nothing you wrote is lost.",
                        bundle: .module
                    )
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.secondaryText)

                    if let onShowWaiting {
                        Button(action: onShowWaiting) {
                            Text("See who this room is waiting on", bundle: .module)
                                .font(CarpenterFont.footnote.weight(.semibold))
                        }
                        .tint(palette.accentColor)
                        .tappable()
                    }

                    if let onChangeWait {
                        Button(action: onChangeWait) {
                            Text("Change when this is shown", bundle: .module)
                                .font(CarpenterFont.footnote.weight(.semibold))
                        }
                        .tint(palette.accentColor)
                        .tappable()
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CarpenterMetrics.screenMargin)
                .padding(.vertical, 16)
            }
            .background(palette.background)
            .navigationTitle(Text("Not sent yet", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var whatHappened: Text {
        switch (notGone.signal, notGone.hasLeftThisDevice) {
        case (.newerMessagesCollected(let count), true):
            Text(
                "It is waiting in your iCloud. ^[\(count) newer message](inflect: true) you sent here have been collected since, and this one has not — which is more than somebody being away.",
                bundle: .module)
        case (.newerMessagesCollected(let count), false):
            Text(
                "It has not left this phone. ^[\(count) newer message](inflect: true) you sent here have been collected since, and this one has not — which is more than somebody being away.",
                bundle: .module)
        case (.waited(let days), true):
            Text(
                "It is waiting in your iCloud, and in more than ^[\(days) day](inflect: true) nobody in this room has collected it. People collect messages when they open the app.",
                bundle: .module)
        case (.waited(let days), false):
            Text(
                "It has not left this phone, and it has been trying for more than ^[\(days) day](inflect: true).",
                bundle: .module)
        }
    }
}

struct NotGoneWaitView: View {
    @Environment(\.palette) private var palette

    let choice: RoomNotGoneChoice

    @State private var chosen: NotGoneWait?

    private var current: NotGoneWait { chosen ?? choice.wait }

    var body: some View {
        List {
            Section {
                ChoiceRow(
                    title: Text("Only when newer ones arrive first", bundle: .module),
                    isSelected: current == .off,
                    action: { choose(.off) })
                ForEach(Array(NotGoneWait.range), id: \.self) { days in
                    ChoiceRow(
                        title: Text("After ^[\(days) day](inflect: true)", bundle: .module),
                        isSelected: current.days == days,
                        action: { choose(NotGoneWait(days: days)) })
                }
            } footer: {
                Text(
                    "A message waiting for somebody to open the app is ordinary, so nothing is said at first. It is marked with an orange circle when more than one newer message you sent here has been collected and it has not, or when it has waited this long. Choosing the first option leaves only the newer-messages sign, so somebody who has stopped opening the app is never pointed out.",
                    bundle: .module)
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(Text("Not sent yet", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
    }

    private func choose(_ wait: NotGoneWait) {
        chosen = wait
        Task { await choice.onChange(wait) }
    }
}
