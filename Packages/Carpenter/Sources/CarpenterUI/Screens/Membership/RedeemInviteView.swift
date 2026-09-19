import CarpenterKit
import SwiftUI

public struct InviteOffer: Hashable, Sendable {
    public let roomName: String?
    public let inviterName: String?
    public let phrase: String
    public let expiresAt: Date

    public init(roomName: String?, inviterName: String?, phrase: String, expiresAt: Date) {
        self.roomName = roomName
        self.inviterName = inviterName
        self.phrase = phrase
        self.expiresAt = expiresAt
    }
}

struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: spacing) { content }
        } else {
            HStack(spacing: spacing) { content }
        }
    }
}

public struct RedeemInviteFlow: Hashable, Sendable {
    public enum Step: Hashable, Sendable {
        case pasting
        case checking(InviteOffer)
        case refused(InviteOffer)
    }

    public private(set) var step: Step = .pasting
    public private(set) var code: String = ""
    public private(set) var problem: String?

    public init() {}

    private var isSettled: Bool {
        if case .refused = step { return true }
        return false
    }

    public mutating func paste(_ code: String) {
        guard !isSettled else { return }
        self.code = code
    }

    @discardableResult
    public mutating func read(using parse: (String) -> InviteOffer?) -> Bool {
        guard !isSettled, let offer = parse(code) else { return false }
        problem = nil
        step = .checking(offer)
        return true
    }

    public mutating func failed(_ reason: String) {
        guard !isSettled else { return }
        problem = reason
    }

    public mutating func refuse() {
        guard case .checking(let offer) = step else { return }
        step = .refused(offer)
        code = ""
        problem = nil
    }

    public mutating func settled(_ reason: String?) {
        guard !isSettled else { return }
        problem = reason
    }
}

public struct RedeemInviteView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var flow = RedeemInviteFlow()
    @State private var settled: Int?
    @State private var rejected = 0
    @State private var accepting = false
    @State private var wantsToScan = false

    private let read: (String) -> InviteOffer?
    private let accept: (String) async -> String?
    private let arriving: String?

    public init(
        arriving: String? = nil,
        read: @escaping (String) -> InviteOffer?,
        accept: @escaping (String) async -> String?
    ) {
        self.arriving = arriving
        self.read = read
        self.accept = accept
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch flow.step {
                    case .refused(let offer): warning(offer)
                    case .checking(let offer): review(offer)
                    case .pasting: entry
                    }
                }
                .padding(.horizontal, CarpenterMetrics.screenMargin)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(palette.background)
            .navigationTitle(isRefused ? Text("Stop", bundle: .module) : Text("Join a room", bundle: .module))
            .toolbar {
                if !isRefused {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
        }
        .task {
            guard let arriving, flow.code.isEmpty else { return }
            flow.paste(arriving)
            if !flow.read(using: read) {
                flow.failed(
                    String(localized: "That invite is not usable. It may have expired.", bundle: .module))
                rejected += 1
            }
        }
        .haptic(.refusal, trigger: rejected)
        .haptic(trigger: settled) { _, new in
            guard new != nil else { return nil }
            return flow.problem == nil ? .commit : .refusal
        }
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                "Paste the invite someone sent you. Nothing is accepted until you have checked it.",
                bundle: .module
            )
            .font(CarpenterFont.footnote)
            .foregroundStyle(palette.secondaryText)

            TextField(
                text: Binding(get: { flow.code }, set: { flow.paste($0) }), axis: .vertical
            ) {
                Text("Paste the invite", bundle: .module)
            }
            .font(.system(.body, design: .monospaced))
            .codeEntry()
            .lineLimit(4...8)
            .returnIsDone(Binding(get: { flow.code }, set: { flow.paste($0) }))
            .padding(12)
            .background(
                palette.elevatedSurface,
                in: .rect(cornerRadius: CarpenterMetrics.cardRadius, style: .continuous))

            #if os(iOS)
                InviteCodeButtons(
                    wantsToScan: $wantsToScan,
                    accepts: { read($0) != nil },
                    onPaste: { flow.paste($0) },
                    onScan: { code in
                        flow.paste(code)
                        flow.read(using: read)
                    })
            #else
                PasteCodeButton { flow.paste($0) }
            #endif

            if let problem = flow.problem {
                Text(problem)
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.destructive)
            }

            Button {
                if !flow.read(using: read) {
                    flow.failed(
                        String(
                            localized: "That is not a usable invite. It may have expired.",
                            bundle: .module))
                    rejected += 1
                }
            } label: {
                Text("Read the invite", bundle: .module).primaryAction()
            }
            .prominentActionButton()
            .disabled(flow.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            #if os(iOS)
                InviteScanningQuestion(wantsToScan: $wantsToScan)
                    .padding(.top, 8)
            #endif
        }
    }

    private func warning(_ offer: InviteOffer) -> some View {
        RefusedCheck(
            placement: .screen,
            readings: Text(
                "Usually that means a link was garbled or an old one was resent. It can also mean somebody put this in front of you in somebody else's name.",
                bundle: .module),
            protection: Text(
                "Nothing was joined and nothing was shared. You were never shown the room, and this device sent nothing back — including to whoever sent this, who does not learn that you looked.",
                bundle: .module),
            nextStep: Text(
                "Ring the person you meant to talk to and read these to each other.",
                bundle: .module),
            phrase: offer.phrase
        ) {
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module).primaryAction()
            }
            .prominentActionButton()
        }
    }

    private var isRefused: Bool {
        if case .refused = flow.step { return true }
        return false
    }

    private func review(_ offer: InviteOffer) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                if let inviterName = offer.inviterName {
                    Text("\(inviterName) invited you", bundle: .module)
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)
                } else {
                    Text("Someone invited you", bundle: .module)
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)
                }

                if let roomName = offer.roomName {
                    Text(roomName)
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.secondaryText)
                }
            }

            VerificationPhrase(offer.phrase)
                .frame(maxWidth: .infinity)

            Text(
                "You have never met this room before, so there is nothing on this device to check the invite against. If the characters do not match what they read out, someone else sent this.",
                bundle: .module
            )
            .font(CarpenterFont.footnote)
            .foregroundStyle(palette.secondaryText)

            if let problem = flow.problem {
                Text(problem)
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.destructive)
            }

            AdaptiveStack(spacing: 10) {
                Button {
                    flow.refuse()
                    rejected += 1
                } label: {
                    Text("They do not match", bundle: .module)
                        .font(CarpenterFont.button)
                        .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
                        .background(
                            palette.elevatedSurface,
                            in: .rect(
                                cornerRadius: CarpenterMetrics.buttonRadius, style: .continuous))
                }
                .foregroundStyle(palette.primaryText)
                .disabled(accepting)

                Button {
                    accepting = true
                    Task {
                        let reason = await accept(flow.code)
                        accepting = false
                        guard case .checking = flow.step else { return }
                        flow.settled(reason)
                        settled = (settled ?? 0) + 1
                        if flow.problem == nil { dismiss() }
                    }
                } label: {
                    Text("They match", bundle: .module).primaryAction()
                }
                .prominentActionButton()
                .disabled(accepting)
            }

            Text(
                "Confirming tells them the characters matched and opens the way to their outbox. The room appears once whoever is in it has let you in.",
                bundle: .module
            )
            .font(CarpenterFont.caption)
            .foregroundStyle(palette.quaternaryText)
        }
    }
}

#Preview("The characters did not match") {
    RedeemInviteView(
        arriving: "outpost://invite?c=whatever",
        read: { _ in
            InviteOffer(
                roomName: nil, inviterName: nil, phrase: "K7M2QX",
                expiresAt: .now.addingTimeInterval(86_400))
        },
        accept: { _ in nil }
    )
    .themed(.default)
}

#Preview("Paste an invite") {
    RedeemInviteView(read: { _ in nil }, accept: { _ in nil })
        .themed(.default)
}

#Preview("Check the phrase") {
    RedeemInviteView(
        read: { _ in
            InviteOffer(
                roomName: nil, inviterName: nil, phrase: "K7M2QX",
                expiresAt: .now.addingTimeInterval(86_400))
        },
        accept: { _ in nil }
    )
    .themed(.default)
}
