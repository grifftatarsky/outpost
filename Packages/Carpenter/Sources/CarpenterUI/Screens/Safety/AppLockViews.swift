import CarpenterKit
import SwiftUI

public struct AppLockScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let controller: AppLockController
    private let onForget: (() async -> Void)?
    @State private var code = ""
    @State private var forgetting = false
    @State private var usingRecoveryKey = false
    @FocusState private var typing: Bool

    public init(controller: AppLockController, onForget: (() async -> Void)? = nil) {
        self.controller = controller
        self.onForget = onForget
    }

    private var isDigits: Bool { controller.lock?.code == .digits }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(palette.accentColor)
                .accessibilityHidden(true)
            // COPY BEGIN 5be5d303 [NEEDS HUMAN REVIEW]
            Text("\(Branding.displayName) is locked", bundle: .module)
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.primaryText)
            if controller.erasing {
                ProgressView()
                AppLockProblem.erasing.sentence
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.secondaryText)
            } else if controller.isLocked, controller.lock != nil {
                SecureField(
                    text: $code,
                    prompt: isDigits ? Text("Code", bundle: .module) : Text("Passphrase", bundle: .module)
                ) {
                    isDigits ? Text("Code", bundle: .module) : Text("Passphrase", bundle: .module)
                }
                #if !os(macOS)
                    .keyboardType(isDigits ? .numberPad : .default)
                #endif
                .textContentType(.password)
                .multilineTextAlignment(.center)
                .font(.title3.monospaced())
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(palette.elevatedSurface, in: .rect(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: 320)
                .focused($typing)
                .onSubmit(submit)

                if let problem = controller.problem {
                    problem.sentence
                        .font(CarpenterFont.footnote)
                        .foregroundStyle(palette.destructive)
                        .multilineTextAlignment(.center)
                } else if controller.biometricsChanged, let name = controller.biometricName {
                    Text("\(name) changed on this phone, so enter your code.", bundle: .module)
                        .font(CarpenterFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.center)
                }

                Button(action: submit) {
                    Text("Unlock", bundle: .module).primaryAction()
                }
                .prominentActionButton()
                .disabled(code.isEmpty || controller.checking)
                .frame(maxWidth: 320)

                if controller.offersBiometrics, let name = controller.biometricName {
                    Button {
                        Task { await controller.unlockWithBiometrics() }
                    } label: {
                        Text("Use \(name)", bundle: .module)
                    }
                    .quietActionButton()
                }
            }
            // COPY END 5be5d303
            forgotten
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) { recoveryKeyButton }
        .background(palette.background)
        .sheet(isPresented: $usingRecoveryKey) {
            NavigationStack {
                RecoveryKeyUnlockView(controller: controller)
            }
            .themed(.default)
        }
        .task {
            if controller.offersBiometrics {
                await controller.unlockWithBiometrics()
            }
            if controller.isLocked { typing = true }
        }
    }

    @ViewBuilder private var recoveryKeyButton: some View {
        // COPY BEGIN 69fb0425 [NEEDS HUMAN REVIEW]
        if controller.isLocked, controller.lock != nil, controller.recovery != nil, !controller.erasing {
            Button { usingRecoveryKey = true } label: {
                Image(systemName: "key.horizontal.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("Use your recovery key", bundle: .module))
            .padding(.leading, 24)
            .padding(.bottom, 12)
        }
        // COPY END 69fb0425
    }

    @ViewBuilder private var forgotten: some View {
        // COPY BEGIN 7e88ab4a [NEEDS HUMAN REVIEW]
        if controller.isLocked, controller.lock != nil, let onForget {
            Button { forgetting = true } label: {
                Text("Forgot the code?", bundle: .module)
            }
            .quietActionButton()
            .alert(Text("Erase this phone's copy?", bundle: .module), isPresented: $forgetting) {
                Button(role: .destructive) {
                    Task { await onForget() }
                } label: {
                    Text("Erase", bundle: .module)
                }
                Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }  // intentionally empty
            } message: {
                Text(
                    "If you have your recovery key, use the key button instead: it opens the app and erases nothing. Without the code or the key, the only way back in is to erase everything this phone keeps, then approve this phone from another of your devices.",
                    bundle: .module)
            }
        }
        // COPY END 7e88ab4a
    }

    private func submit() {
        guard !code.isEmpty else { return }
        let entered = code
        code = ""
        Task { await controller.unlock(with: entered) }
    }

}

extension AppLockProblem {
    // COPY BEGIN c45e581f [NEEDS HUMAN REVIEW]
    var sentence: Text {
        switch self {
        case .wrong(let left):
            Text("That's not it. \(left) more tries before a wait.", bundle: .module)
        case .waitUntil(let until):
            Text("Too many tries. Try again at \(until.formatted(date: .omitted, time: .shortened)).", bundle: .module)
        case .notSaved:
            Text("The lock couldn't be saved. Try again.", bundle: .module)
        case .needsCode:
            Text("Enter your current code first.", bundle: .module)
        case .wrongBeforeErasing(let left):
            left == 1
                ? Text("That's not it. One more wrong code erases everything.", bundle: .module)
                : Text("That's not it. \(left) more wrong codes erase everything.", bundle: .module)
        case .erasing:
            Text("Erasing everything…", bundle: .module)
        case .notTheRecoveryKey:
            Text("That isn't the recovery key for this identity.", bundle: .module)
        }
    }
    // COPY END c45e581f
}

struct RecoveryKeyUnlockView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let controller: AppLockController
    @State private var text = ""
    @State private var checking = false

    var body: some View {
        List {
            // COPY BEGIN bfd439df [NEEDS HUMAN REVIEW]
            Section {
                TextField(text: $text, axis: .vertical) {
                    Text("Paste your recovery key", bundle: .module)
                }
                .lineLimit(3...8)
                .font(.body.monospaced())
                #if !os(macOS)
                    .textInputAutocapitalization(.characters)
                #endif
                .autocorrectionDisabled()
            } footer: {
                if controller.problem == .notTheRecoveryKey {
                    AppLockProblem.notTheRecoveryKey.sentence
                        .foregroundStyle(palette.destructive)
                } else {
                    Text(
                        "Your recovery key opens the app and turns the lock off, so you can set a new code in Settings.",
                        bundle: .module)
                }
            }
            .groupedRowSurface()

            Section {
                Button {
                    checking = true
                    let entered = text
                    Task {
                        let opened = await controller.unlock(withRecoveryKey: entered)
                        checking = false
                        if opened { dismiss() }
                    }
                } label: {
                    Text("Unlock", bundle: .module).primaryAction()
                }
                .prominentActionButton()
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(palette.background)
        .navigationTitle(Text("Recovery Key", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Text("Cancel", bundle: .module) }
            }
        }
        // COPY END bfd439df
    }
}

public struct AppLockSetupView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let biometricName: String?
    private let revealsNotifications: (@MainActor () -> Bool)?
    private let onLock: (AppLock) async -> Bool
    private let onMakeNotificationsPrivate: (() async -> Void)?
    private let onDone: (() -> Void)?
    private let onNotNow: (() -> Void)?

    @State private var kind: AppLock.Code = .digits
    @State private var code = ""
    @State private var again = ""
    @State private var biometrics = true
    @State private var saving = false
    @State private var notSaved = false
    @State private var askingAboutNotifications = false
    @FocusState private var focus: Field?

    private enum Field { case code, again }

    public init(
        biometricName: String?, revealsNotifications: (@MainActor () -> Bool)? = nil,
        onLock: @escaping (AppLock) async -> Bool,
        onMakeNotificationsPrivate: (() async -> Void)? = nil, onDone: (() -> Void)? = nil,
        onNotNow: (() -> Void)? = nil
    ) {
        self.biometricName = biometricName
        self.revealsNotifications = revealsNotifications
        self.onLock = onLock
        self.onMakeNotificationsPrivate = onMakeNotificationsPrivate
        self.onDone = onDone
        self.onNotNow = onNotNow
    }

    private var mismatch: Bool { !again.isEmpty && again != code }
    private var acceptable: Bool { AppLock.isAcceptable(code, as: kind) }
    private var ready: Bool { acceptable && code == again && !saving }

    public var body: some View {
        List {
            // COPY BEGIN 66758400 [NEEDS HUMAN REVIEW]
            Section {
                SettingsHeaderCard(
                    icon: "lock.fill",
                    title: Text("Lock the app", bundle: .module),
                    paragraph: Text(
                        "Ask for a code of its own whenever the app opens. Your phone's passcode never opens it.",
                        bundle: .module))
            }
            .groupedRowSurface()

            Section {
                Picker(selection: $kind) {
                    Text("A 4 to 6 digit code", bundle: .module).tag(AppLock.Code.digits)
                    Text("A passphrase", bundle: .module).tag(AppLock.Code.passphrase)
                } label: {
                    Text("Use", bundle: .module)
                }
                .onChange(of: kind) { _, _ in
                    code = ""
                    again = ""
                }
                SecureField(text: $code) {
                    kind == .digits ? Text("Code", bundle: .module) : Text("Passphrase", bundle: .module)
                }
                #if !os(macOS)
                    .keyboardType(kind == .digits ? .numberPad : .default)
                #endif
                .textContentType(.newPassword)
                .focused($focus, equals: .code)
                SecureField(text: $again) {
                    Text("Again", bundle: .module)
                }
                #if !os(macOS)
                    .keyboardType(kind == .digits ? .numberPad : .default)
                #endif
                .textContentType(.newPassword)
                .focused($focus, equals: .again)
                if let biometricName {
                    Toggle(isOn: $biometrics) {
                        Text("Also unlock with \(biometricName)", bundle: .module)
                    }
                }
            } footer: {
                if notSaved {
                    AppLockProblem.notSaved.sentence
                        .foregroundStyle(palette.destructive)
                } else if mismatch {
                    Text("The two don't match.", bundle: .module)
                        .foregroundStyle(palette.destructive)
                } else if !code.isEmpty, !acceptable {
                    kind == .digits
                        ? Text("Use 4 to 6 digits.", bundle: .module)
                        : Text("Use at least 8 characters.", bundle: .module)
                } else {
                    Text(
                        "The lock guards the app's screens. If you forget the code, your recovery key opens the app from the lock screen.",
                        bundle: .module)
                }
            }
            .groupedRowSurface()
            // COPY END 66758400

            actions
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(palette.background)
        // COPY BEGIN 61f4704a [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("App Lock", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        // COPY END 61f4704a
        .onAppear { if onNotNow == nil { focus = .code } }
        .onChange(of: ready) { _, now in if now { focus = nil } }
        // COPY BEGIN 095e4033 [NEEDS HUMAN REVIEW]
        .alert(Text("Make notifications private too?", bundle: .module), isPresented: $askingAboutNotifications) {
            Button {
                Task {
                    await onMakeNotificationsPrivate?()
                    finish()
                }
            } label: {
                Text("Make them private", bundle: .module)
            }
            Button(role: .cancel) { finish() } label: { Text("Keep them as they are", bundle: .module) }
        } message: {
            Text(
                "The lock covers the app, not your notifications. As they arrive, anyone holding your phone can read the names, rooms and words they show. Private notifications say only that something arrived.",
                bundle: .module)
        }
        // COPY END 095e4033
    }

    private func finish() {
        if let onDone { onDone() } else { dismiss() }
    }

    private var actions: some View {
        Section {
            VStack(spacing: 10) {
                // COPY BEGIN 82c694ab [NEEDS HUMAN REVIEW]
                Button {
                    save()
                } label: {
                    Text("Lock the app", bundle: .module).primaryAction()
                }
                .prominentActionButton()
                .disabled(!ready)
                if let onNotNow {
                    Button { onNotNow() } label: {
                        Text("Not now", bundle: .module)
                    }
                    .quietActionButton()
                }
                // COPY END 82c694ab
            }
            .padding(.top, 8)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private func save() {
        guard ready else { return }
        saving = true
        let (entered, chosen, withBiometrics) = (code, kind, biometrics && biometricName != nil)
        Task {
            let made = await Task.detached(priority: .userInitiated) {
                try? AppLock.make(entered, as: chosen, usesBiometrics: withBiometrics)
            }.value
            let kept = if let made { await onLock(made) } else { false }
            saving = false
            notSaved = !kept
            guard kept else { return }
            if revealsNotifications?() == true, onMakeNotificationsPrivate != nil {
                askingAboutNotifications = true
            } else {
                finish()
            }
        }
    }
}

struct AppLockSettingsView: View {
    @Environment(\.palette) private var palette

    let controller: AppLockController
    @State private var settingUp = false
    @State private var confirming: Change?
    @State private var entered = ""
    @State private var savingKeyFirst: Int?
    @State private var riskingNoKey: Int?

    private enum Change: Identifiable, Hashable {
        case newCode
        case off
        case biometricsOn
        case delay(TimeInterval)
        case eraseAfter(Int?)

        var id: Self { self }
    }

    var body: some View {
        List {
            // COPY BEGIN 77e5e417 [NEEDS HUMAN REVIEW]
            Section {
                SettingsHeaderCard(
                    icon: "lock.fill",
                    title: Text("App lock", bundle: .module),
                    paragraph: Text(
                        "When it's on, the app asks for its own code, or Face ID, when it opens, and covers itself in the app switcher.",
                        bundle: .module))
            }
            .groupedRowSurface()

            Section {
                if let lock = controller.lock {
                    Picker(selection: Binding(
                        get: { lock.delay },
                        set: { delay in
                            if delay > lock.delay {
                                confirming = .delay(delay)
                            } else {
                                Task { await controller.setDelay(delay) }
                            }
                        })
                    ) {
                        Text("Right away", bundle: .module).tag(TimeInterval(0))
                        Text("After 1 minute", bundle: .module).tag(TimeInterval(60))
                        Text("After 5 minutes", bundle: .module).tag(TimeInterval(300))
                        Text("After 15 minutes", bundle: .module).tag(TimeInterval(900))
                    } label: {
                        Text("Lock", bundle: .module)
                    }
                    if let name = controller.biometricName {
                        Toggle(isOn: Binding(
                            get: { lock.usesBiometrics },
                            set: { on in
                                if on {
                                    confirming = .biometricsOn
                                } else {
                                    Task { await controller.setBiometrics(false) }
                                }
                            })
                        ) {
                            Text("Unlock with \(name)", bundle: .module)
                        }
                    }
                    Button { confirming = .newCode } label: {
                        Text("Change code", bundle: .module)
                    }
                    Button(role: .destructive) {
                        confirming = .off
                    } label: {
                        Text("Turn off the lock", bundle: .module)
                    }
                    .tint(palette.destructive)
                } else {
                    Button { settingUp = true } label: {
                        Text("Turn on the lock", bundle: .module)
                    }
                }
            }
            .groupedRowSurface()
            // COPY END 77e5e417
            if let lock = controller.lock {
                eraseSection(lock)
            }
            if let problem = controller.problem {
                Section {
                    problem.sentence
                        .font(CarpenterFont.footnote)
                        .foregroundStyle(palette.destructive)
                }
                .groupedRowSurface()
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN a60a94cd [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("App Lock", bundle: .module))
        // COPY END a60a94cd
        .sheet(isPresented: $settingUp) {
            NavigationStack {
                AppLockSetupView(
                    biometricName: controller.biometricName,
                    revealsNotifications: { controller.notificationPrivacy?.reveals() ?? false },
                    onLock: { lock in await controller.turnOn(lock) },
                    onMakeNotificationsPrivate: { await controller.notificationPrivacy?.makePrivate() })
            }
        }
        .sheet(item: Binding(get: { savingKeyFirst.map(EraseChoice.init) }, set: { savingKeyFirst = $0?.count })) {
            choice in saveKeySheet(then: choice.count)
        }
        // COPY BEGIN 5e791962 [NEEDS HUMAN REVIEW]
        .alert(
            Text("Enter your current code", bundle: .module),
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { change in
            SecureField(text: $entered) { Text("Code", bundle: .module) }
            Button {
                let code = entered
                entered = ""
                Task {
                    guard await controller.confirm(code) else { return }
                    switch change {
                    case .newCode: settingUp = true
                    case .off: await controller.turnOff()
                    case .biometricsOn: await controller.setBiometrics(true)
                    case .delay(let delay): await controller.setDelay(delay)
                    case .eraseAfter(let count): turnOnErasing(count)
                    }
                }
            } label: {
                Text("Continue", bundle: .module)
            }
            Button(role: .cancel) { entered = "" } label: { Text("Cancel", bundle: .module) }
        } message: { _ in
            Text("The lock only changes for somebody who knows it.", bundle: .module)
        }
        // COPY END 5e791962
        // COPY BEGIN 3fe7fb47 [NEEDS HUMAN REVIEW]
        .alert(
            Text("Turn it on without your recovery key?", bundle: .module),
            isPresented: Binding(get: { riskingNoKey != nil }, set: { if !$0 { riskingNoKey = nil } }),
            presenting: riskingNoKey
        ) { count in
            Button(role: .destructive) {
                Task { await controller.setEraseAfter(count) }
            } label: {
                Text("Turn it on", bundle: .module)
            }
            .tint(palette.destructive)
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }  // intentionally empty
        } message: { _ in
            Text(
                "If it erases everything, nothing brings your identity back, and the people you talk to would have to start again with a new you.",
                bundle: .module)
        }
        // COPY END 3fe7fb47
    }

    private func turnOnErasing(_ count: Int?) {
        guard let count, controller.lock?.eraseAfter == nil, let recovery = controller.recovery,
            !recovery.isSaved()
        else {
            Task { await controller.setEraseAfter(count) }
            return
        }
        if recovery.unsaved() != nil {
            savingKeyFirst = count
        } else {
            riskingNoKey = count
        }
    }

    private func saveKeySheet(then count: Int) -> some View {
        NavigationStack {
            if let recovery = controller.recovery, let key = recovery.unsaved() {
                RecoveryKeyView(text: key.text, fingerprint: key.fingerprint) {
                    await recovery.markSaved()
                    savingKeyFirst = nil
                    await controller.setEraseAfter(count)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            savingKeyFirst = nil
                            riskingNoKey = count
                        } label: {
                            Text("Not now", bundle: .module)
                        }
                    }
                }
            }
        }
        .themed(.default)
    }

    private func eraseSection(_ lock: AppLock) -> some View {
        // COPY BEGIN 320ac2d4 [NEEDS HUMAN REVIEW]
        Section {
            Picker(selection: Binding(
                get: { lock.eraseAfter },
                set: { count in confirming = .eraseAfter(count) })
            ) {
                Text("Off", bundle: .module).tag(Int?.none)
                Text("After 1 wrong code", bundle: .module).tag(Int?.some(1))
                Text("After 5 wrong codes", bundle: .module).tag(Int?.some(5))
                Text("After 10 wrong codes", bundle: .module).tag(Int?.some(10))
            } label: {
                SettingsRow(icon: "trash.fill", tone: .destructive, title: Text("Erase everything", bundle: .module))
            }
        } footer: {
            Text(
                "Every wrong code counts, wherever the app asks for it. When the count is reached, everything you keep is erased, on every device and in iCloud. Only your recovery key brings your identity back.",
                bundle: .module)
        }
        .groupedRowSurface()
        // COPY END 320ac2d4
    }
}

private struct EraseChoice: Identifiable {
    let count: Int
    var id: Int { count }
}

#if DEBUG
    private struct PreviewBiometrics: Biometrics {
        var name: String? { "Face ID" }
        func state() -> Data? { Data([1]) }
        func evaluate(reason: String) async -> Bool { false }
    }

    #Preview("App lock — setting it up") {
        NavigationStack {
            AppLockSetupView(biometricName: "Face ID", onLock: { _ in true }, onNotNow: {})
        }
        .themed(.default)
    }

    #Preview("App lock — locked") {
        AppLockScreen(
            controller: AppLockController(
                store: AppLockStore(keychain: PreviewKeychain()), biometrics: PreviewBiometrics()))
            .themed(.default)
    }

    private actor PreviewKeychain: KeychainStore {
        func data(for key: KeychainKey) throws -> Data? {
            try JSONEncoder().encode(try AppLock.make("123456", as: .digits, usesBiometrics: false, rounds: 1))
        }
        func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) throws {}
        func remove(_ key: KeychainKey) throws {}
        func removeAll() throws {}
    }
#endif
