import SwiftUI

private struct TutorialModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    public var showsHelp: Bool {
        get { self[TutorialModeKey.self] }
        set { self[TutorialModeKey.self] = newValue }
    }
}

extension View {
    public func helpButton() -> some View {
        modifier(HelpButton())
    }
}

private struct HelpButton: ViewModifier {
    @Environment(\.showsHelp) private var showsHelp
    @Environment(\.palette) private var palette

    @State private var reading = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if showsHelp {
                    ToolbarItem(placement: .primaryAction) {
                        Button { reading = true } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(palette.primaryText)
                        }
                        .accessibilityLabel(Text("How this works", bundle: .module))
                        .barIconLargeContent(
                            Text("How this works", bundle: .module), systemImage: "questionmark.circle")
                    }
                }
            }
            .sizedSheet(isPresented: $reading) { HowItWorksView() }
    }
}
