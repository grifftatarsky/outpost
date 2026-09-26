import CarpenterKit
import SwiftUI

struct ReciprocalAccessCard: View {
    @Environment(\.palette) private var palette

    let access: ReciprocalAccess
    let onChange: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider().overlay(palette.separator)
            // COPY BEGIN 098dd2a9 [NEEDS HUMAN REVIEW]
            VStack(alignment: .leading, spacing: 18) {
                direction(
                    title: Text("You can read", bundle: .module), windows: access.youCanRead
                ) {
                    theirDecision
                }
                direction(
                    title: Text("They can read", bundle: .module), windows: access.theyCanRead
                ) {
                    yourControl
                }
            }
            // COPY END 098dd2a9
        }
        .padding(16)
        .background(palette.fieldFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 12) {
            AvatarView(
                initials: access.person.initials, diameter: CarpenterMetrics.messageAvatar,
                image: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: access.person.displayName)
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                if !access.sharedRooms.isEmpty {
                    Text(verbatim: access.sharedRooms.joined(separator: " · "))
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.tertiaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func direction<Control: View>(
        title: Text, windows: [AccessWindow], @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .sectionHeading()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // COPY BEGIN aa656dde [NEEDS HUMAN REVIEW]
                VStack(alignment: .leading, spacing: 2) {
                    if windows.isEmpty {
                        Text("Nothing", bundle: .module)
                    } else {
                        ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                            Text(verbatim: AccessWindowsCopy.line(for: window))
                        }
                    }
                }
                .font(CarpenterFont.rowDetail)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                // COPY END aa656dde
                Spacer(minLength: 0)
                control()
            }
        }
    }

    // COPY BEGIN 7c7fa483 [NEEDS HUMAN REVIEW]
    private var theirDecision: some View {
        Text("Their decision", bundle: .module)
            .font(CarpenterFont.rowDetail)
            .foregroundStyle(palette.tertiaryText)
            .accessibilityLabel(
                Text(
                    "Their decision. Only they can change what you can read.",
                    bundle: .module))
    }
    // COPY END 7c7fa483

    // COPY BEGIN 0270d618 [NEEDS HUMAN REVIEW]
    @ViewBuilder private var yourControl: some View {
        if let onChange {
            Button(action: onChange) { Text("Change", bundle: .module) }
                .buttonStyle(.borderless)
                .tint(palette.secondaryActionLabel)
                .font(CarpenterFont.rowDetail)
        }
    }
    // COPY END 0270d618
}

#if DEBUG
    #Preview("63 Reciprocal access") {
        VStack {
            ReciprocalAccessCard(
                access: ReciprocalAccess(
                    person: Fixtures.camilla,
                    sharedRooms: ["The Gazette", "Zeppelin Enthusiasts"],
                    theyGave: OutpostAccess.Grant(),
                    youGave: OutpostAccess.Grant(windows: [
                        AccessWindow(
                            from: Date(timeIntervalSince1970: 1_757_000_000),
                            until: Date(timeIntervalSince1970: 1_775_260_800)),
                        AccessWindow(from: Date(timeIntervalSince1970: 1_779_000_000)),
                    ])),
                onChange: {})
            Spacer()
        }
        .padding()
        .themed(.default)
    }
#endif
