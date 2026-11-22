import CarpenterKit
import SwiftUI

extension View {
    public func approvingDevices(
        _ request: DeviceRequest?, onApprove: @escaping (DeviceRequest) -> Void,
        onDecline: @escaping (DeviceRequest) -> Void
    ) -> some View {
        // COPY BEGIN b6ce14dd [NEEDS HUMAN REVIEW]
        alert(
            Text("Approve a new device?", bundle: .module),
            isPresented: Binding(get: { request != nil }, set: { _ in }),
            presenting: request
        ) { request in
            Button { onApprove(request) } label: { Text("Approve", bundle: .module) }
            Button(role: .cancel) { onDecline(request) } label: { Text("Don't approve", bundle: .module) }
        } message: { request in
            Text(
                "Only approve it if it shows \(request.code). It will be able to read everything you can and send messages as you.",
                bundle: .module)
        }
        // COPY END b6ce14dd
    }
}
