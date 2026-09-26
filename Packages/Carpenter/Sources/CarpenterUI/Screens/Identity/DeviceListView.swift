import CarpenterKit
import SwiftUI

public struct DeviceListView: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let devices: [DeviceSummary]
    private let onRevoke: ([DeviceSummary]) async -> Void
    private let onPair: (() -> Void)?
    private let onRename: ((DeviceSummary, String) async -> Void)?

    @State private var confirming: [DeviceSummary] = []
    @State private var renaming: DeviceSummary?
    @State private var draft = ""
    @State private var chosen: Set<DeviceID> = []
    @State private var picking = false

    private var removable: [DeviceSummary] { devices.filter { $0.isActive && !$0.isCurrent } }

    private var picked: [DeviceSummary] { removable.filter { chosen.contains($0.id) } }

    public init(
        devices: [DeviceSummary],
        onRevoke: @escaping ([DeviceSummary]) async -> Void = { _ in },
        onPair: (() -> Void)? = nil,
        onRename: ((DeviceSummary, String) async -> Void)? = nil
    ) {
        self.devices = devices
        self.onRevoke = onRevoke
        self.onPair = onPair
        self.onRename = onRename
    }

    public var body: some View {
        List(selection: $chosen) {
            Section {
                ForEach(devices) { device in
                    row(device)
                        .tag(device.id)
                        .selectionDisabled(!device.isActive || device.isCurrent)
                        .swipeActions(edge: .leading) {
                            // COPY BEGIN 0bce4c15 [NEEDS HUMAN REVIEW]
                            if onRename != nil {
                                Button {
                                    draft = device.name ?? ""
                                    renaming = device
                                } label: {
                                    Label {
                                        Text("Rename", bundle: .module)
                                    } icon: {
                                        Image(systemName: "pencil")
                                    }
                                }
                                .tint(palette.accentColor)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if device.isActive && !device.isCurrent {
                                Button(role: .destructive) {
                                    confirming = [device]
                                } label: {
                                    Label {
                                        Text("Remove", bundle: .module)
                                    } icon: {
                                        Image(systemName: "trash")
                                    }
                                }
                                .tint(palette.destructive)
                            }
                        }
                }
            } footer: {
                Text(
                    "Anything on this list can send messages as you. Removing one stops it from reading what is said afterwards — but not from having sent what it already sent, because it really was you. Other people stop accepting it as you as their devices collect the removal, which is the next time each of them syncs.",
                    bundle: .module
                )
                .fixedSize(horizontal: false, vertical: true)
                            // COPY END 0bce4c15
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN 53f4599c [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Devices", bundle: .module))
        // COPY END 53f4599c
        #if os(iOS)
            .environment(
                \.editMode,
                .constant(picking ? EditMode.active : EditMode.inactive))
        #endif
        .toolbar {
            // COPY BEGIN b6eeeacd [NEEDS HUMAN REVIEW]
            if let onPair, !picking {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onPair) {
                        Label {
                            Text("Add a device", bundle: .module)
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            if !removable.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(reduceMotion ? nil : .default) { picking.toggle() }
                        chosen = []
                    } label: {
                        if picking {
                            Text("Done", bundle: .module)
                        } else {
                            Text("Select", bundle: .module)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if picking {
                Button(role: .destructive) { confirming = picked } label: {
                    Text("^[Remove \(picked.count) device](inflect: true)", bundle: .module)
                        .primaryAction()
                }
                .destructiveActionButton()
                .disabled(picked.isEmpty)
                .padding(.horizontal, CarpenterMetrics.screenMargin)
                .padding(.bottom, 8)
                .transition(.opacity)  // cross-fade only
            }
        }
            // COPY END b6eeeacd
        .sheet(isPresented: .init(get: { !confirming.isEmpty }, set: { if !$0 { confirming = [] } })) {
            removalSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        // COPY BEGIN b1dd4c2f [NEEDS HUMAN REVIEW]
        .alert(
            Text("Name this device", bundle: .module),
            isPresented: .init(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField(text: $draft) { Text("Name", bundle: .module) }
            Button {
                if let device = renaming, let onRename {
                    let wanted = draft
                    renaming = nil
                    Task { await onRename(device, wanted) }
                }
            } label: {
                Text("Save", bundle: .module)
            }
            Button(role: .cancel) { renaming = nil } label: {
                Text("Cancel", bundle: .module)
            }
        } message: {
            Text(
                "Only you see this. It travels to your own devices and reaches nobody else.",
                bundle: .module)
        // COPY END b1dd4c2f
        }
    }

    private var removalSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // COPY BEGIN 5235a290 [NEEDS HUMAN REVIEW]
                    Group {
                        if confirming.count == 1 {
                            Text("Remove this device?", bundle: .module)
                        } else {
                            Text("Remove these \(confirming.count) devices?", bundle: .module)
                        }
                    }
                    .font(CarpenterFont.navigationTitle)
                    .foregroundStyle(palette.primaryText)
                    // COPY END 5235a290

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(confirming) { device in
                            HStack(spacing: 10) {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(palette.tertiaryText)
                                    .accessibilityHidden(true)
                                Text(verbatim: name(of: device))
                                    .font(CarpenterFont.rowTitle)
                                    .foregroundStyle(palette.primaryText)
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    // COPY BEGIN 99b2a7ba [NEEDS HUMAN REVIEW]
                    Group {
                        if confirming.count == 1 {
                            Text(
                                "It will not be able to read anything sent from now on. What it already sent stays.",
                                bundle: .module)
                        } else {
                            Text(
                                "They will not be able to read anything sent from now on. What they already sent stays. Every room turns its key once, however many you remove.",
                                bundle: .module)
                        }
                    }
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    // COPY END 99b2a7ba
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CarpenterMetrics.screenMargin)
                .padding(.top, 28)
            }

            VStack(spacing: 10) {
                // COPY BEGIN 5f3e3b71 [NEEDS HUMAN REVIEW]
                Button(role: .destructive) {
                    let going = confirming
                    confirming = []
                    chosen = []
                    picking = false
                    Task { await onRevoke(going) }
                } label: {
                    Text("^[Remove \(confirming.count) device](inflect: true)", bundle: .module)
                        .primaryAction()
                }
                .destructiveActionButton()
                // COPY END 5f3e3b71

                // COPY BEGIN b8ef82a2 [NEEDS HUMAN REVIEW]
                Button { confirming = [] } label: {
                    Text("Cancel", bundle: .module)
                        .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.hitTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accentColor)
                // COPY END b8ef82a2
            }
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.bottom, 16)
        }
        .background(palette.background)
    }

    private func name(of device: DeviceSummary) -> String {
        device.name.flatMap { $0.isEmpty ? nil : $0 } ?? device.shortCode
    }

    private func row(_ device: DeviceSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: device.isCurrent ? "iphone" : "desktopcomputer")
                .font(.title3)
                .foregroundStyle(device.isActive ? palette.accentColor : palette.quaternaryText)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let name = device.name, !name.isEmpty {
                        Text(name)
                            .font(CarpenterFont.rowTitle)
                            .foregroundStyle(
                                device.isActive ? palette.primaryText : palette.tertiaryText)
                    } else {
                        Text(verbatim: device.shortCode)
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                            .foregroundStyle(
                                device.isActive ? palette.primaryText : palette.tertiaryText)
                    }

                    // COPY BEGIN c7e99e92 [NEEDS HUMAN REVIEW]
                    if device.isCurrent {
                        Text("This device", bundle: .module)
                            .font(CarpenterFont.badge)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(palette.badgeFill, in: .capsule)
                            .foregroundStyle(palette.primaryText)
                    }
                    // COPY END c7e99e92
                }

                if device.isNamed {
                    Text(verbatim: device.shortCode)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(palette.tertiaryText)
                }

                if let revokedAt = device.revokedAt {
                    // COPY BEGIN 247d1fdf [NEEDS HUMAN REVIEW]
                    Text(
                        "Removed \(revokedAt.formatted(date: .abbreviated, time: .shortened))",
                        bundle: .module
                    )
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.tertiaryText)
                } else if let addedAt = device.addedAt {
                    if device.hasSpoken {
                        Text(
                            "Added \(addedAt.formatted(date: .abbreviated, time: .shortened))",
                            bundle: .module
                        )
                        .font(CarpenterFont.caption)
                        .foregroundStyle(palette.secondaryText)
                    } else {
                        Text(
                            "Added \(addedAt.formatted(date: .abbreviated, time: .shortened)). Nothing it sent has reached this device.",
                            bundle: .module
                        )
                        .font(CarpenterFont.caption)
                        .foregroundStyle(palette.accentColor)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Here since you made this identity", bundle: .module)
                        .font(CarpenterFont.caption)
                        .foregroundStyle(palette.secondaryText)
                    // COPY END 247d1fdf
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .opacity(device.isActive ? 1 : 0.6)
    }
}

#Preview("Devices") {
    NavigationStack {
        DeviceListView(
            devices: [
                DeviceSummary(
                    id: DeviceID(rawValue: Data([0x8A, 0x2D, 0x01])), isCurrent: true,
                    addedAt: nil),
                DeviceSummary(
                    id: DeviceID(rawValue: Data([0x14, 0xBC, 0x77])), isCurrent: false,
                    addedAt: .now.addingTimeInterval(-86_400 * 5)),
                DeviceSummary(
                    id: DeviceID(rawValue: Data([0x99, 0x0E, 0x31])), isCurrent: false,
                    addedAt: .now.addingTimeInterval(-86_400 * 90),
                    revokedAt: .now.addingTimeInterval(-86_400)),
            ],
            onPair: {}
        )
    }
    .themed(.default)
}

#Preview("One device") {
    NavigationStack {
        DeviceListView(
            devices: [
                DeviceSummary(
                    id: DeviceID(rawValue: Data([0x8A, 0x2D, 0x01])), isCurrent: true,
                    addedAt: nil)
            ],
            onPair: {}
        )
    }
    .themed(.default)
}
