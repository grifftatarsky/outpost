import SwiftUI

extension View {
    func returnIsDone(
        _ text: Binding<String>, focus: FocusState<Bool>.Binding? = nil, onDone: @escaping () -> Void = {}
    ) -> some View {
        modifier(ReturnIsDone(text: text, external: focus, onDone: onDone))
    }

    func doneAboveKeyboard(_ focus: FocusState<Bool>.Binding? = nil) -> some View {
        modifier(DoneAboveKeyboard(external: focus))
    }
}

enum TypedReturn {
    static func removed(from typed: String, after previous: String) -> String? {
        guard typed.count == previous.count + 1 else { return nil }
        for (offset, character) in typed.enumerated() where character.isNewline {
            var without = typed
            without.remove(at: typed.index(typed.startIndex, offsetBy: offset))
            if without == previous { return without }
        }
        return nil
    }
}

private struct ReturnIsDone: ViewModifier {
    @Binding var text: String
    let external: FocusState<Bool>.Binding?
    let onDone: () -> Void
    @FocusState private var own: Bool

    private var focus: FocusState<Bool>.Binding { external ?? $own }

    func body(content: Content) -> some View {
        focusedUnlessTheCallerDoes(content)
            .submitLabel(.done)
            .onSubmit(finish)
            .onChange(of: text) { previous, typed in
                guard let kept = TypedReturn.removed(from: typed, after: previous) else { return }
                text = kept
                finish()
            }
    }

    @ViewBuilder
    private func focusedUnlessTheCallerDoes(_ content: Content) -> some View {
        if external == nil {
            content.focused($own)
        } else {
            content
        }
    }

    private func finish() {
        focus.wrappedValue = false
        onDone()
    }
}

private struct DoneAboveKeyboard: ViewModifier {
    let external: FocusState<Bool>.Binding?
    @FocusState private var own: Bool

    private var focus: FocusState<Bool>.Binding { external ?? $own }

    func body(content: Content) -> some View {
        #if os(iOS)
            focusedUnlessTheCallerDoes(content)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        if focus.wrappedValue {
                            Spacer()
                            Button { focus.wrappedValue = false } label: {
                                Text("Done", bundle: .module)
                            }
                        }
                    }
                }
        #else
            content
        #endif
    }

    @ViewBuilder
    private func focusedUnlessTheCallerDoes(_ content: Content) -> some View {
        if external == nil {
            content.focused($own)
        } else {
            content
        }
    }
}
