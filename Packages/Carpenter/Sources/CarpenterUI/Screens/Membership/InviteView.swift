import CarpenterKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

public struct InviteView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @Environment(\.verificationPhrase) private var phraseLookup

    private let roomName: String
    private let invite: String
    private let link: URL?
    private let phrase: String?
    private let expiresAt: Date
    private let notAskedYet: Bool

    public init(
        roomName: String, invite: String, link: URL? = nil, phrase: String?, expiresAt: Date,
        notAskedYet: Bool = false
    ) {
        self.roomName = roomName
        self.invite = invite
        self.link = link
        self.phrase = phrase
        self.expiresAt = expiresAt
        self.notAskedYet = notAskedYet
    }

    public init?(
        roomName: String, invite: Invite, phrase: String?, notAskedYet: Bool = false
    ) {
        guard let encoded = try? invite.encoded() else { return nil }
        self.init(
            roomName: roomName,
            invite: encoded,
            link: try? InviteLink.url(inviting: invite, scheme: Branding.urlScheme),
            phrase: phrase,
            expiresAt: invite.attestation.expiresAt,
            notAskedYet: notAskedYet
        )
    }

    private var shareable: String { link?.absoluteString ?? invite }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if notAskedYet { unasked }

                    code

                    if let phrase {
                        VerificationPhrase(phrase)

                        Text(
                            "They should see exactly the same characters. If they do not, stop — do not carry on and do not send another to the same code. Start again in person.",
                            bundle: .module
                        )
                        .font(CarpenterFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.center)
                    } else {
                        VerificationPhrasePending()
                    }

                    ShareLink(item: shareable) {
                        Text("Send the invite", bundle: .module)
                            .font(CarpenterFont.button)
                            .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
                            .background(
                                palette.elevatedSurface,
                                in: .rect(
                                    cornerRadius: CarpenterMetrics.buttonRadius, style: .continuous))
                    }
                    .foregroundStyle(palette.primaryText)

                    if expiresAt >= .distantFuture {
                        Text(
                            "This invite does not expire. It stays good until you take it back.",
                            bundle: .module
                        )
                        .font(CarpenterFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                    } else {
                        Text(
                            "This invite expires \(expiresAt.formatted(date: .abbreviated, time: .shortened)).",
                            bundle: .module
                        )
                        .font(CarpenterFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                    }
                }
                .padding(.horizontal, CarpenterMetrics.screenMargin)
                .padding(.vertical, 24)
            }
            .background(palette.background)
            .navigationTitle(roomName)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
        }
    }

    private var unasked: some View {
        Text(
            "\(roomName) has not been sent this yet. Nothing reaches them until you do.",
            bundle: .module
        )
        .font(CarpenterFont.rowDetail)
        .foregroundStyle(palette.primaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var code: some View {
        if let image = Self.qrCode(for: shareable) {
            Image(image, scale: 1, label: Text("Invite QR code", bundle: .module))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260)
                .padding(16)
                .background(.white, in: .rect(cornerRadius: CarpenterMetrics.cardRadius))

            Text("Point their camera at this, or send it.", bundle: .module)
                .font(CarpenterFont.caption)
                .foregroundStyle(palette.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            Text(invite)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    palette.elevatedSurface,
                    in: .rect(cornerRadius: CarpenterMetrics.cardRadius))
        }
    }

    static func qrCode(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}

struct OutstandingInviteSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.verificationPhrase) private var phraseLookup
    @Environment(\.dismiss) private var dismiss

    let roomName: String
    let load: () async -> Invite?

    @State private var invite: Invite?
    @State private var looked = false

    var body: some View {
        Group {
            if let invite {
                InviteView(
                    roomName: roomName, invite: invite, phrase: phraseLookup(invite),
                    notAskedYet: true)
            } else {
                NavigationStack {
                    VStack(spacing: 16) {
                        if looked {
                            Text(
                                "There is no invitation standing here any more.", bundle: .module
                            )
                            .font(CarpenterFont.rowDetail)
                            .foregroundStyle(palette.primaryText)
                            .multilineTextAlignment(.center)
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.background)
                    .navigationTitle(roomName)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button { dismiss() } label: { Text("Done", bundle: .module) }
                        }
                    }
                }
            }
        }
        .task {
            invite = await load()
            looked = true
        }
    }
}

public struct StartInviteView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var failed = false
    @FocusState private var pasting: Bool
    @State private var lifetime: InvitationLifetime = .aDay
    @State private var pickedDay = Date().addingTimeInterval(7 * 24 * 60 * 60)

    private let roomName: String
    private let onIssue: (String, InvitationLifetime) async -> Bool

    public init(roomName: String, onIssue: @escaping (String, InvitationLifetime) async -> Bool) {
        self.roomName = roomName
        self.onIssue = onIssue
    }

    private static var pickableDays: ClosedRange<Date> {
        let today = Date()
        return today...today.addingTimeInterval(365 * 24 * 60 * 60)
    }

    static func name(of lifetime: InvitationLifetime) -> Text {
        switch lifetime {
        case .aDay: return Text("A day", bundle: .module)
        case .aWeek: return Text("A week", bundle: .module)
        case .thirtyDays: return Text("Thirty days", bundle: .module)
        case .indefinite: return Text("Until you take it back", bundle: .module)
        case .until(let date):
            return Text(
                "Until \(date.formatted(date: .abbreviated, time: .shortened))", bundle: .module)
        }
    }

    private func lifetimeRow(_ option: InvitationLifetime) -> some View {
        let detail: Text? =
            option == .indefinite
            ? Text("Never runs out. Only taking it back closes it.", bundle: .module)
            : nil
        return ChoiceRow(
            title: Self.name(of: option), detail: detail, isSelected: lifetime == option
        ) {
            lifetime = option
        }
    }

    private var pickedDateRow: some View {
        ChoiceRow(
            title: Text("A date you pick", bundle: .module),
            detail: Text(
                "Good until the end of that day, wherever you are when you choose it.",
                bundle: .module),
            isSelected: lifetime.isPickedDate
        ) {
            lifetime = InvitationLifetime.endOfDay(pickedDay)
            pasting = false
        }
    }

    @ViewBuilder
    private var lifetimeSection: some View {
        Section {
            ForEach(InvitationLifetime.allCases, id: \.self) { lifetimeRow($0) }
            pickedDateRow
        } header: {
            Text("How long it stays good", bundle: .module).sectionHeading()
        }
        .groupedRowSurface()
    }

    @ViewBuilder
    private var pickedDaySection: some View {
        if lifetime.isPickedDate {
            Section {
                DatePicker(
                    selection: $pickedDay,
                    in: Self.pickableDays,
                    displayedComponents: .date
                ) {
                    Text("Runs out at the end of", bundle: .module)
                        .foregroundStyle(palette.primaryText)
                }
                .onChange(of: pickedDay) { _, day in
                    lifetime = InvitationLifetime.endOfDay(day)
                }
            }
            .groupedRowSurface()
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(text: $code, axis: .vertical) {
                        Text("Paste their code", bundle: .module)
                    }
                    .font(.system(.body, design: .monospaced))
                    .codeEntry()
                    .lineLimit(4...8)
                    .focused($pasting)

                    PasteCodeButton { code = $0 }
                } header: {
                    Text("Their code", bundle: .module).sectionHeading()
                } footer: {
                    if failed {
                        Text(
                            "That does not look like a code from \(Branding.displayName).",
                            bundle: .module)
                            .foregroundStyle(palette.destructive)
                    } else {
                        Text(
                            "Ask them to open \(Branding.displayName), go to You, and send you their code.",
                            bundle: .module)
                    }
                }
                .groupedRowSurface()

                lifetimeSection

                pickedDaySection

                Section {
                    Button {
                        Task {
                            failed = !(await onIssue(code, lifetime))
                            if !failed { dismiss() }
                        }
                    } label: {
                        Text("Create the invite", bundle: .module).primaryAction()
                    }
                    .prominentActionButton()
                    .disabled(!InviteLink.namesSomebody(code))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button { pasting = false } label: { Text("Done", bundle: .module) }
                    }
                }
            }
            .background(palette.background)
            .navigationTitle(roomName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
            }
        }
    }
}

#Preview("Start an invite") {
    StartInviteView(roomName: "Hangar 7", onIssue: { _, _ in false })
        .themed(.default)
}

#Preview("Invite") {
    InviteView(
        roomName: "Hangar 7",
        invite: "eyJyb29tIjoiSGFuZ2FyIDciLCJqb2luZXIiOiJib2IifQ",
        phrase: "K7M2QX",
        expiresAt: .now.addingTimeInterval(86_400)
    )
    .themed(.default)
}
