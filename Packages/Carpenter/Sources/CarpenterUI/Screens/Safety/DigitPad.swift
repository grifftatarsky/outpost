import CarpenterKit
import SwiftUI

struct DigitPad: View {
    @Environment(\.palette) private var palette

    let length: Int?
    let busy: Bool
    let biometricName: String?
    let onBiometrics: () -> Void
    let onSubmit: (String) -> Void

    @State private var entered = ""

    private var slots: Int { length ?? max(entered.count, 4) }
    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        VStack(spacing: 28) {
            dots
            GlassEffectContainer(spacing: 18) {
                Grid(horizontalSpacing: 26, verticalSpacing: 16) {
                    ForEach(rows, id: \.self) { row in
                        GridRow {
                            ForEach(row, id: \.self) { digit in key(digit) }
                        }
                    }
                    GridRow {
                        biometricKey
                        key("0")
                        deleteKey
                    }
                }
            }
            if length == nil {
                Button { submit() } label: {
                    // COPY BEGIN ff8d357a [NEEDS HUMAN REVIEW]
                    Text("Unlock", bundle: .module).primaryAction()
                    // COPY END ff8d357a
                }
                .prominentActionButton()
                .disabled(entered.isEmpty || busy)
                .frame(maxWidth: 320)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 14) {
            ForEach(0..<slots, id: \.self) { index in
                Circle()
                    .strokeBorder(palette.primaryText, lineWidth: 1.5)
                    .background(Circle().fill(index < entered.count ? palette.primaryText : .clear))
                    .frame(width: 13, height: 13)
            }
        }
        .accessibilityElement(children: .ignore)
        // COPY BEGIN bc60cfe2 [NEEDS HUMAN REVIEW]
        .accessibilityLabel(Text("\(entered.count) digits entered", bundle: .module))
        // COPY END bc60cfe2
    }

    private func key(_ digit: String) -> some View {
        Button { type(digit) } label: {
            Text(verbatim: digit)
                .font(.system(size: 34, weight: .regular))
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .foregroundStyle(palette.primaryText)
        .disabled(busy)
        .accessibilityLabel(Text(verbatim: digit))
    }

    @ViewBuilder private var biometricKey: some View {
        if let biometricName {
            Button(action: onBiometrics) {
                Image(systemName: Self.symbol(for: biometricName))
                    .font(.system(size: 30))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .foregroundStyle(palette.accentColor)
            .disabled(busy)
            // COPY BEGIN f1fb9c55 [NEEDS HUMAN REVIEW]
            .accessibilityLabel(Text("Use \(biometricName)", bundle: .module))
            // COPY END f1fb9c55
        } else {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
        }
    }

    private var deleteKey: some View {
        Button { if !entered.isEmpty { entered.removeLast() } } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 26))
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .foregroundStyle(palette.primaryText)
        .disabled(entered.isEmpty || busy)
        // COPY BEGIN d911fd09 [NEEDS HUMAN REVIEW]
        .accessibilityLabel(Text("Delete", bundle: .module))
        // COPY END d911fd09
    }

    private func type(_ digit: String) {
        guard entered.count < (length ?? 6) else { return }
        entered.append(digit)
        if let length, entered.count == length { submit() }
    }

    private func submit() {
        guard !entered.isEmpty else { return }
        let code = entered
        entered = ""
        onSubmit(code)
    }

    static func symbol(for biometricName: String) -> String {
        if biometricName.localizedCaseInsensitiveContains("face") { return "faceid" }
        if biometricName.localizedCaseInsensitiveContains("optic") { return "opticid" }
        return "touchid"
    }
}
