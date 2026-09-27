import CarpenterKit
import PhotosUI
import SwiftUI

#if DEBUG

struct FitTestView: View {
    @Environment(\.palette) private var palette
    let run: @MainActor @Sendable (URL, @escaping @MainActor @Sendable (FitTestStage) -> Void) async -> FitTestReport

    @State private var picked: PhotosPickerItem?
    @State private var stage: FitTestStage?
    @State private var report: FitTestReport?
    @State private var loading = false

    var body: some View {
        List {
            Section {
                PhotosPicker(selection: $picked, matching: .videos, photoLibrary: .shared()) {
                    SettingsRow(
                        icon: "film",
                        title: Text("Choose a video", bundle: .module),
                        detail: Text(
                            "Make it fit, upload the pieces to your outbox, fetch the same pieces back, then delete them. Nothing is sent to anybody.",
                            bundle: .module))
                }
                .disabled(stage != nil || loading)
            }
            .groupedRowSurface()

            if loading || stage != nil {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        stageText
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .groupedRowSurface()
            }

            if let report {
                results(report)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(Text("Test Make it fit", bundle: .module))
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { await start(item) }
        }
    }

    private var stageText: Text {
        switch stage {
        case .fitting: Text("Making it fit…", bundle: .module)
        case .uploading(let done): Text("Uploading piece \(done + 1)…", bundle: .module)
        case .downloading(let done, let total): Text("Fetching piece \(done + 1) of \(total)…", bundle: .module)
        case .clearing: Text("Deleting the test pieces…", bundle: .module)
        case nil: Text("Reading the video…", bundle: .module)
        }
    }

    private func start(_ item: PhotosPickerItem) async {
        report = nil
        loading = true
        let clip = try? await item.loadTransferable(type: PickedClip.self)
        loading = false
        picked = nil
        guard let clip else {
            var failed = FitTestReport()
            failed.failure = String(localized: "The video could not be read.", bundle: .module)
            report = failed
            return
        }
        defer { try? FileManager.default.removeItem(at: clip.url) }
        stage = .fitting
        report = await run(clip.url) { stage = $0 }
        stage = nil
    }

    @ViewBuilder
    private func results(_ report: FitTestReport) -> some View {
        if let failure = report.failure {
            Section {
                Text(verbatim: failure)
                    .foregroundStyle(palette.destructive)
            } header: {
                Text("Stopped", bundle: .module).sectionHeading()
            }
            .groupedRowSurface()
        }
        if report.originalBytes > 0 {
            Section {
                row(Text("Picked", bundle: .module), Self.bytes(report.originalBytes))
                row(Text("Made to fit", bundle: .module), Self.bytes(report.fittedBytes))
                row(Text("Size", bundle: .module), "\(report.width) × \(report.height)")
                row(Text("Length", bundle: .module), Self.duration(report.seconds))
                row(Text("Time to fit", bundle: .module), Self.duration(report.fitSeconds))
            } header: {
                Text("Make it fit", bundle: .module).sectionHeading()
            }
            .groupedRowSurface()
        }
        if report.pieces > 0 {
            Section {
                row(Text("Pieces", bundle: .module), "\(report.pieces)")
                row(Text("Sealed", bundle: .module), Self.bytes(report.sealedBytes))
                row(Text("Time to seal", bundle: .module), Self.duration(report.sealSeconds))
                row(Text("Time to upload", bundle: .module), Self.duration(report.uploadSeconds))
                row(Text("Upload speed", bundle: .module), Self.speed(report.sealedBytes, report.uploadSeconds))
            } header: {
                Text("Upload", bundle: .module).sectionHeading()
            }
            .groupedRowSurface()
        }
        if report.downloadSeconds > 0 {
            Section {
                row(Text("Time to fetch", bundle: .module), Self.duration(report.downloadSeconds))
                row(Text("Fetch speed", bundle: .module), Self.speed(report.sealedBytes, report.downloadSeconds))
                row(Text("Same bytes back", bundle: .module), "\(report.piecesMatched) of \(report.pieces)")
                row(Text("Test pieces deleted", bundle: .module), report.cleared ? "✓" : "✗")
            } header: {
                Text("Fetched back", bundle: .module).sectionHeading()
            }
            .groupedRowSurface()
        }
    }

    private func row(_ title: Text, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .monospacedDigit()
                .foregroundStyle(palette.secondaryText)
        } label: {
            title
                .foregroundStyle(palette.primaryText)
        }
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        seconds < 60
            ? String(format: "%.2f s", seconds)
            : Duration.seconds(seconds.rounded()).formatted(.time(pattern: .minuteSecond))
    }

    static func speed(_ bytes: Int, _ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "–" }
        return ByteCountFormatter.string(fromByteCount: Int64(Double(bytes) / seconds), countStyle: .file) + "/s"
    }
}

#endif
