import SwiftUI

enum LineBreak {
    static func inserted(into text: String, at selection: TextSelection?) -> (text: String, selection: TextSelection) {
        var range = text.endIndex..<text.endIndex
        switch selection?.indices {
        case .selection(let chosen)?:
            range = chosen
        case .multiSelection(let chosen)?:
            range = chosen.ranges.first ?? range
        default:
            break
        }
        let lower = position(range.lowerBound, in: text)
        let upper = max(position(range.upperBound, in: text), lower)
        let offset = text.distance(from: text.startIndex, to: lower)
        var result = text
        result.replaceSubrange(lower..<upper, with: "\n")
        return (result, TextSelection(insertionPoint: result.index(result.startIndex, offsetBy: offset + 1)))
    }

    private static func position(_ index: String.Index, in text: String) -> String.Index {
        guard index < text.endIndex else { return text.endIndex }
        return String.Index(index, within: text) ?? text.endIndex
    }
}

extension View {
    @ViewBuilder
    func shiftReturnBreaksLine(_ text: Binding<String>, selection: Binding<TextSelection?>) -> some View {
        #if os(macOS)
            onKeyPress(.return, phases: .down) { press in
                guard press.modifiers.contains(.shift) else { return .ignored }
                (text.wrappedValue, selection.wrappedValue) = LineBreak.inserted(
                    into: text.wrappedValue, at: selection.wrappedValue)
                return .handled
            }
        #else
            self
        #endif
    }
}
