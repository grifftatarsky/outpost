import CarpenterKit
import LocalAuthentication
import SwiftUI

public struct DeviceSecuritySetting: Sendable {
    public let isOn: Bool
    public let change: @MainActor @Sendable (Bool) async -> String?

    public init(isOn: Bool, change: @escaping @MainActor @Sendable (Bool) async -> String?) {
        self.isOn = isOn
        self.change = change
    }
}

extension EnvironmentValues {
    @Entry public var deviceSecurity: DeviceSecuritySetting?
}

struct DeviceSecuritySettingsView: View {
    @Environment(\.palette) private var palette

    let setting: DeviceSecuritySetting
    @State private var changing = false
    @State private var problem: String?
    @State private var passcodeIsSet = true

    var body: some View {
        List {
            // COPY BEGIN 9057a976 [NEEDS HUMAN REVIEW]
            SettingsHeaderCard(
                icon: "lock.shield.fill", tone: .device,
                title: Text("Advanced On Device Security", bundle: .module),
                paragraph: Text(
                    "When it's on, the messages, photos, names and keys this iPhone keeps for the app are sealed whenever the iPhone is locked. Someone who copies what is stored on it while it is locked can't read them without the iPhone's passcode.",
                    bundle: .module))
            // COPY END 9057a976

            Section {
                // COPY BEGIN ea4d1bb4 [NEEDS HUMAN REVIEW]
                SettingsToggle(
                    icon: "lock.fill", tone: .device,
                    title: Text("Seal while iPhone is locked", bundle: .module),
                    isOn: Binding(get: { setting.isOn }, set: { on in Task { await change(on) } }))
                    .disabled(changing || (!passcodeIsSet && !setting.isOn))
                // COPY END ea4d1bb4
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    // COPY BEGIN d561602f [NEEDS HUMAN REVIEW]
                    Text(
                        "While your iPhone is locked, new messages wait, sealed, in the sender's iCloud and arrive when you unlock it, and notifications only say that something arrived.",
                        bundle: .module)
                    if !passcodeIsSet {
                        Text(
                            "This iPhone has no passcode, so nothing it keeps can be sealed. Set a passcode in the Settings app first.",
                            bundle: .module)
                    }
                    // COPY END d561602f
                    if let problem {
                        Text(verbatim: problem).foregroundStyle(palette.destructive)
                    }
                }
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN 8bf17541 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Advanced On Device Security", bundle: .module))
        // COPY END 8bf17541
        .toolbarTitleDisplayMode(.inline)
        .onAppear { passcodeIsSet = Self.phoneHasPasscode() }
    }

    private func change(_ on: Bool) async {
        changing = true
        problem = await setting.change(on)
        changing = false
    }

    private static func phoneHasPasscode() -> Bool {
        var error: NSError?
        let usable = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        return usable || error?.code != LAError.Code.passcodeNotSet.rawValue
    }
}
