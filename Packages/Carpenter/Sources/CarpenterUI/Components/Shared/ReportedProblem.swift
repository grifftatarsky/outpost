import SwiftUI

public struct ReportedProblem: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

extension EnvironmentValues {
    @Entry public var reportedProblem: Binding<ReportedProblem?> = .constant(nil)
}

extension View {
    public func presentingProblems(_ problem: Binding<ReportedProblem?>) -> some View {
        // COPY BEGIN 82c3ae22 [NEEDS HUMAN REVIEW]
        alert(
            Text(verbatim: problem.wrappedValue?.title ?? ""),
            isPresented: Binding(
                get: { problem.wrappedValue != nil },
                set: { showing in if !showing { problem.wrappedValue = nil } }),
            presenting: problem.wrappedValue
        ) { _ in
            Button { problem.wrappedValue = nil } label: { Text("OK", bundle: .module) }
        } message: { shown in
            Text(verbatim: shown.detail)
        }
        // COPY END 82c3ae22
    }

    public func presentingReportedProblems() -> some View {
        modifier(PresentingReportedProblems())
    }
}

private struct PresentingReportedProblems: ViewModifier {
    @Environment(\.reportedProblem) private var problem

    func body(content: Content) -> some View {
        content.presentingProblems(problem)
    }
}
