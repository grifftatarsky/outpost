import SwiftUI

public struct DataProblemView: View {
    private let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public var body: some View {
        // COPY BEGIN 9c1a5749 [NEEDS HUMAN REVIEW]
        ContentUnavailableView(
            String(localized: "Something is wrong with this device's data", bundle: .module),
            systemImage: "exclamationmark.triangle",
            description: Text(verbatim: reason)
        )
        // COPY END 9c1a5749
    }
}
