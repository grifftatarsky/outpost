import CarpenterKit
import SwiftUI

struct HistoryRepairBanner: View {
    @Environment(\.palette) private var palette

    let status: HistoryRepairStatus
    let onDismiss: () async -> Void

    private var isWhole: Bool { status.stillMissing == 0 && status.unverifiable == 0 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if status.isComplete {
                Image(systemName: isWhole ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(isWhole ? palette.accentColor : palette.secondaryText)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            RepairCopy.line(for: status)
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 0)
            Button {
                Task { await onDismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.tertiaryText)
            }
            .accessibilityLabel(
                status.isComplete
                    ? Text("Dismiss", bundle: .module) : Text("Stop waiting", bundle: .module))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.fieldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

enum RepairCopy {
    static func line(for status: HistoryRepairStatus) -> Text {
        let asked = names(status.asked)
        if !status.isComplete {
            if status.answered.isEmpty {
                return Text("Asking \(asked) for anything this device is missing…", bundle: .module)
            }
            return Text(
                "\(names(status.answered)) answered. Waiting for \(names(status.waiting)).",
                bundle: .module)
        }

        let checked = Text("Checked with \(asked).", bundle: .module)
        let refused = status.unverifiable > 0
            ? Text(
                "^[\(status.unverifiable) entry](inflect: true) will not verify: a device that signed them had stopped being allowed to speak for its member.",
                bundle: .module)
            : nil

        if status.stillMissing == 0 {
            if status.recovered > 0 {
                let arrived = sentences(
                    checked,
                    Text("^[\(status.recovered) missing entry](inflect: true) arrived.", bundle: .module))
                return sentences(arrived, refused ?? Text("Nothing is missing now.", bundle: .module))
            }
            return sentences(checked, refused ?? Text("Nothing is missing.", bundle: .module))
        }

        let missing: Text
        if status.heldByNobodyAsked == status.stillMissing {
            missing = Text(
                "^[\(status.stillMissing) entry](inflect: true) still missing, and nobody asked has them.",
                bundle: .module)
        } else if status.sentButNotArrived == status.stillMissing {
            missing = Text(
                "^[\(status.stillMissing) entry](inflect: true) still missing; \(asked) sent them and they did not arrive. Check again.",
                bundle: .module)
        } else {
            missing = Text(
                "^[\(status.stillMissing) entry](inflect: true) still missing: \(status.heldByNobodyAsked) nobody asked has, \(status.sentButNotArrived) sent and not arrived. Check again.",
                bundle: .module)
        }
        let told = sentences(checked, missing)
        return refused.map { sentences(told, $0) } ?? told
    }

    private static func sentences(_ first: Text, _ next: Text) -> Text {
        Text("\(first) \(next)", bundle: .module)
    }

    static func names(_ people: [Member]) -> String {
        people.map(\.displayName).formatted(.list(type: .and))
    }
}
