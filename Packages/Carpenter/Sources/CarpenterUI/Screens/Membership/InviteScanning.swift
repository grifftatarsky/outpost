import SwiftUI

#if os(iOS)
    import AVFoundation
    import VisionKit
#endif

public enum InviteScanning: String, Sendable, CaseIterable {
    case unasked
    case on
    case off

    static let storageKey = "invites.scanning"

    enum Offer: Equatable {
        case ask
        case scan
        case nothing
    }

    func offer(deviceCanScan: Bool, wantsToScan: Bool) -> Offer {
        guard deviceCanScan else { return .nothing }
        switch self {
        case .unasked: return wantsToScan ? .scan : .ask
        case .on: return .scan
        case .off: return .nothing
        }
    }

    func after(_ access: CameraAccess) -> InviteScanning {
        switch access {
        case .granted: .on
        case .refused: .off
        case .undecided, .unsupported: self
        }
    }

    @MainActor
    static var deviceCanScan: Bool {
        #if targetEnvironment(simulator)
            true
        #elseif os(iOS)
            DataScannerViewController.isSupported
        #else
            false
        #endif
    }
}

enum CameraAccess: Equatable {
    case unsupported
    case undecided
    case granted
    case refused
}

enum ScanAttempt: Equatable {
    case openScanner
    case askTheSystem
    case explainUnsupported
    case explainRefused

    init(_ access: CameraAccess) {
        switch access {
        case .unsupported: self = .explainUnsupported
        case .undecided: self = .askTheSystem
        case .granted: self = .openScanner
        case .refused: self = .explainRefused
        }
    }
}

#if os(iOS)
    extension CameraAccess {
        @MainActor
        static var current: CameraAccess {
            guard DataScannerViewController.isSupported else { return .unsupported }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .notDetermined: return .undecided
            case .authorized: return DataScannerViewController.isAvailable ? .granted : .refused
            default: return .refused
            }
        }

        @MainActor
        static func askingIfUndecided() async -> CameraAccess {
            guard current == .undecided else { return current }
            _ = await AVCaptureDevice.requestAccess(for: .video)
            return current
        }
    }

    struct CameraRefusedNote: View {
        @Environment(\.palette) private var palette
        @Environment(\.openURL) private var openURL

        let access: CameraAccess

        var body: some View {
            switch access {
            case .unsupported:
                // COPY BEGIN 0e0bd3cd [NEEDS HUMAN REVIEW]
                Text("This device cannot scan codes. Paste the invite instead.", bundle: .module)
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            case .refused:
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "The camera is turned off for this app. You can turn it on in the Settings app, or paste the invite instead.",
                        bundle: .module
                    )
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    if let settings = URL(string: UIApplication.openSettingsURLString) {
                        Button { openURL(settings) } label: {
                            Text("Open Settings", bundle: .module)
                                .font(CarpenterFont.footnote.weight(.semibold))
                        }
                        .tint(palette.accentColor)
                        .tappable()
                    }
                // COPY END 0e0bd3cd
                }
            case .granted, .undecided:
                EmptyView()
            }
        }
    }

    struct InviteCodeButtons: View {
        @Environment(\.palette) private var palette
        @AppStorage(InviteScanning.storageKey) private var scanning: InviteScanning = .unasked

        @Binding var wantsToScan: Bool
        let accepts: (String) -> Bool
        let onPaste: (String) -> Void
        let onScan: (String) -> Void

        @State private var isScanning = false
        @State private var notice: CameraAccess?

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                if scanning.offer(deviceCanScan: InviteScanning.deviceCanScan, wantsToScan: wantsToScan)
                    == .scan
                {
                    AdaptiveStack(spacing: 10) {
                        PasteCodeButton(onPaste: onPaste)
                        scanButton
                    }
                } else {
                    PasteCodeButton(onPaste: onPaste)
                }

                if let notice { CameraRefusedNote(access: notice) }
            }
            .sheet(isPresented: $isScanning) {
                InviteScannerSheet(accepts: accepts) { code in
                    isScanning = false
                    onScan(code)
                }
            }
        }

        // COPY BEGIN a6e460d2 [NEEDS HUMAN REVIEW]
        private var scanButton: some View {
            Button(action: scan) {
                Label {
                    Text("Scan", bundle: .module)
                } icon: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .codeEntryButtonChrome()
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.primaryText)
        }
        // COPY END a6e460d2

        private func scan() {
            notice = nil
            Task {
                let access = await CameraAccess.askingIfUndecided()
                scanning = scanning.after(access)
                if access == .granted {
                    isScanning = true
                } else {
                    notice = access
                }
            }
        }
    }

    struct InviteScanningQuestion: View {
        @Environment(\.palette) private var palette
        @AppStorage(InviteScanning.storageKey) private var scanning: InviteScanning = .unasked

        @Binding var wantsToScan: Bool

        var body: some View {
            if scanning.offer(deviceCanScan: InviteScanning.deviceCanScan, wantsToScan: wantsToScan)
                == .ask
            {
                question
            }
        }

        private var question: some View {
            VStack(alignment: .leading, spacing: 10) {
                // COPY BEGIN 8cc71634 [NEEDS HUMAN REVIEW]
                Text("Scan invites with the camera?", bundle: .module)
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                Text(
                    "A Scan button would sit beside Paste and read the QR code on somebody's screen. The camera looks only for an invite and keeps nothing it sees. The first time you scan, iOS asks whether this app may use the camera. You can change this later in Behavior.",
                    bundle: .module
                )
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                // COPY END 8cc71634

                // COPY BEGIN b3bbfd73 [NEEDS HUMAN REVIEW]
                AdaptiveStack(spacing: 10) {
                    Button { wantsToScan = true } label: {
                        Text("Turn on scanning", bundle: .module)
                    }
                    .quietActionButton()
                    Button { scanning = .off } label: {
                        Text("Not now", bundle: .module)
                    }
                    .quietActionButton()
                }
                // COPY END b3bbfd73
            }
            .padding(14)
            .background(
                palette.elevatedSurface,
                in: .rect(cornerRadius: CarpenterMetrics.cardRadius, style: .continuous))
        }
    }

    struct InviteScanningSetting: View {
        @AppStorage(InviteScanning.storageKey) private var scanning: InviteScanning = .unasked

        @State private var notice: CameraAccess?

        var body: some View {
            // COPY BEGIN 7b2baf9b [NEEDS HUMAN REVIEW]
            if InviteScanning.deviceCanScan {
                Section {
                    SettingsToggle(
                        icon: "qrcode.viewfinder",
                        title: Text("Scan invites with the camera", bundle: .module),
                        isOn: Binding(get: { scanning == .on }, set: change))
                    if let notice { CameraRefusedNote(access: notice) }
                } footer: {
                    Text(
                        "Puts a Scan button beside Paste when you join a room. The camera looks only for an invite and keeps nothing it sees. It stays off until this app has been allowed to use the camera; if you said no to that, it is turned back on in the Settings app.",
                        bundle: .module)
                }
                .groupedRowSurface()
            }
            // COPY END 7b2baf9b
        }

        private func change(_ wanted: Bool) {
            notice = nil
            guard wanted else {
                scanning = .off
                return
            }
            Task {
                let access = await CameraAccess.askingIfUndecided()
                scanning = scanning.after(access)
                if access != .granted { notice = access }
            }
        }
    }

    struct InviteScannerSheet: View {
        @Environment(\.palette) private var palette
        @Environment(\.dismiss) private var dismiss

        let accepts: (String) -> Bool
        let found: (String) -> Void

        @State private var sawSomethingElse = false
        @State private var stopped = false

        var body: some View {
            NavigationStack {
                InviteScanner(
                    accepts: accepts, found: found,
                    sawSomethingElse: { sawSomethingElse = true },
                    stopped: { stopped = true }
                )
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    guidance
                        .font(CarpenterFont.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.horizontal, CarpenterMetrics.screenMargin)
                        .padding(.bottom, 32)
                }
                // COPY BEGIN 4906735d [NEEDS HUMAN REVIEW]
                .navigationTitle(Text("Scan an invite", bundle: .module))
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                    }
                }
                // COPY END 4906735d
            }
        }

        // COPY BEGIN 9a259e6a [NEEDS HUMAN REVIEW]
        private var guidance: Text {
            if stopped {
                return Text("The camera stopped. Close this and paste the invite instead.", bundle: .module)
            }
            if sawSomethingElse {
                return Text("That code is not an invite this device can use.", bundle: .module)
            }
            return Text("Point the camera at the invite's QR code.", bundle: .module)
        }
        // COPY END 9a259e6a
    }

    private struct InviteScanner: UIViewControllerRepresentable {
        let accepts: (String) -> Bool
        let found: (String) -> Void
        let sawSomethingElse: () -> Void
        let stopped: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        func makeUIViewController(context: Context) -> DataScannerViewController {
            let scanner = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.qr])],
                qualityLevel: .balanced,
                recognizesMultipleItems: false,
                isHighFrameRateTrackingEnabled: false,
                isPinchToZoomEnabled: true,
                isGuidanceEnabled: true,
                isHighlightingEnabled: true)
            scanner.delegate = context.coordinator
            let coordinator = context.coordinator
            Task { @MainActor in
                do {
                    try scanner.startScanning()
                } catch {
                    coordinator.parent.stopped()
                }
            }
            return scanner
        }

        func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
            context.coordinator.parent = self
        }

        static func dismantleUIViewController(
            _ scanner: DataScannerViewController, coordinator: Coordinator
        ) {
            scanner.stopScanning()
        }

        @MainActor
        final class Coordinator: NSObject, DataScannerViewControllerDelegate {
            var parent: InviteScanner
            private var isFinished = false

            init(_ parent: InviteScanner) {
                self.parent = parent
            }

            func dataScanner(
                _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                allItems: [RecognizedItem]
            ) {
                guard !isFinished else { return }
                for item in addedItems {
                    guard case .barcode(let code) = item, let payload = code.payloadStringValue
                    else { continue }
                    guard parent.accepts(payload) else {
                        parent.sawSomethingElse()
                        continue
                    }
                    isFinished = true
                    dataScanner.stopScanning()
                    parent.found(payload)
                    return
                }
            }

            func dataScanner(
                _ dataScanner: DataScannerViewController,
                becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
            ) {
                parent.stopped()
            }
        }
    }
#endif
