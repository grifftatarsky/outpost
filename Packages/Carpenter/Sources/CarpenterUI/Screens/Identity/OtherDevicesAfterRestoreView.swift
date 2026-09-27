import CarpenterKit
import SwiftUI

public struct OtherDevicesAfterRestoreView: View {
    @Environment(\.palette) private var palette
    @State private var confirmingAll = false
    @State private var working = false

    private let devices: [DeviceSummary]
    private let onRevoke: ([DeviceSummary]) async -> Void
    private let onDone: () -> Void

    public init(
        devices: [DeviceSummary], onRevoke: @escaping ([DeviceSummary]) async -> Void,
        onDone: @escaping () -> Void
    ) {
        self.devices = devices
        self.onRevoke = onRevoke
        self.onDone = onDone
    }

    private var others: [DeviceSummary] { devices.filter { $0.isActive && !$0.isCurrent } }

    public var body: some View {
        NavigationStack {
            List {
                // COPY BEGIN 07998163 [NEEDS HUMAN REVIEW]
                SettingsHeaderCard(
                    icon: "ipad.and.iphone",
                    title: Text("Your other devices", bundle: .module),
                    paragraph: Text(
                        "These devices are still signed in as you. Remove any you no longer have. A removed device can't read anything sent from now on, and erases what it holds the next time it opens.",
                        bundle: .module))
                // COPY END 07998163

                Section {
                    // COPY BEGIN 5de9a207 [NEEDS HUMAN REVIEW]
                    Button(role: .destructive) {
                        confirmingAll = true
                    } label: {
                        Label {
                            Text("Remove all other devices", bundle: .module)
                        } icon: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(palette.destructive)
                        }
                    }
                    .tint(palette.destructive)
                    .disabled(others.isEmpty || working)

                    NavigationLink {
                        DeviceListView(devices: devices, onRevoke: onRevoke)
                    } label: {
                        Text("Choose which to remove", bundle: .module)
                    }

                    Button(action: onDone) {
                        Text("Keep them", bundle: .module)
                    }
                    // COPY END 5de9a207
                }
                .groupedRowSurface()
            }
            .confirmationDialog(
                Text("Remove all other devices?", bundle: .module), isPresented: $confirmingAll,
                titleVisibility: .visible
            ) {
                // COPY BEGIN 8bb89ce2 [NEEDS HUMAN REVIEW]
                Button(role: .destructive) {
                    working = true
                    Task {
                        await onRevoke(others)
                        working = false
                        onDone()
                    }
                } label: {
                    Text("Remove \(others.count) devices", bundle: .module)
                }
            } message: {
                Text(
                    "Every conversation's key is rotated once. The removed devices can't read anything sent from now on.",
                    bundle: .module)
                // COPY END 8bb89ce2
            }
        }
    }
}

#if DEBUG
    #Preview("Your other devices, after a restore") {
        OtherDevicesAfterRestoreView(devices: Fixtures.devices, onRevoke: { _ in }, onDone: {})
            .themed(.default)
    }
#endif
