import SwiftUI

public struct DataProblemView: View {
    private let reason: String
    private let onTryAgain: () async -> Void

    @State private var trying = false

    public init(reason: String, onTryAgain: @escaping () async -> Void) {
        self.reason = reason
        self.onTryAgain = onTryAgain
    }

    public var body: some View {
        // COPY BEGIN 9c1a5749 [NEEDS HUMAN REVIEW]
        ContentUnavailableView {
            Label {
                Text("Something is wrong with this device's data", bundle: .module)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } description: {
            Text(verbatim: reason)
        } actions: {
            Button {
                Task {
                    trying = true
                    await onTryAgain()
                    trying = false
                }
            } label: {
                Text("Try again", bundle: .module)
            }
            .disabled(trying)
        }
        // COPY END 9c1a5749
    }
}
