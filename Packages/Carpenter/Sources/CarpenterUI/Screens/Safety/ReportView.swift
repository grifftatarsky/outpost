import CarpenterKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/*
 * The report as a file somebody can hand to something else.
 *
 * The form reads a report to decide whether it is one, and reading needs bytes.
 * Plain text, deliberately: it is the only thing the app will ever hand over
 * about a message, and a reader can check every word of it first.
 */
private struct ReportFile: Transferable {
    let text: String
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { file in
            Data(file.text.utf8)
        }
        .suggestedFileName { $0.name }
    }
}

public struct ReportView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.clock) private var clock

    private let item: ViewedItem

    @State private var description = ""
    @State private var leaving = false
    @State private var copied = false
    @State private var noBrowser = false

    private static let cyberTipline = URL(string: "https://report.cybertip.org/")!
    private static let cybertipCanada = URL(string: "https://www.cybertip.ca/")!

    public init(item: ViewedItem) {
        self.item = item
    }

    private var report: AbuseReport {
        AbuseReport(
            description: description,
            sender: item.author.id,
            senderName: item.author.isPlaceholder ? nil : item.author.displayName,
            entry: item.entry,
            sentAt: item.at,
            kind: item.isMedia ? .photo : .text,
            reportedAt: clock.now,
            appVersion: Branding.version)
    }

    // COPY BEGIN 2f94d344 [NEEDS HUMAN REVIEW]
    private var fileName: String {
        let day = clock.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "\(Branding.displayName) report \(item.author.id.shortCode) \(day)"
    }
    // COPY END 2f94d344

    private var reportFile: ReportFile {
        ReportFile(text: report.body, name: fileName)
    }

    private var formHost: String { Branding.reportFormURL?.host() ?? "" }

    private var canSend: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Branding.reportFormURL != nil
    }

    public var body: some View {
        NavigationStack {
            List {
                // COPY BEGIN 82a3a54b [NEEDS HUMAN REVIEW]
                Section {
                    TextField(text: $description, axis: .vertical) {
                        Text("What happened?", bundle: .module)
                    }
                    .lineLimit(3...8)
                } header: {
                    Text("In your words", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "Say what you saw. This is the whole of what is sent about it — the words and any photo stay on your device.",
                        bundle: .module)
                }
                .groupedRowSurface()
                // COPY END 82a3a54b

                // COPY BEGIN 5aa4676a [NEEDS HUMAN REVIEW]
                Section {
                    row(Text("Who sent it", bundle: .module), value: "\(item.author.displayName) · \(item.author.id.shortCode)")
                    row(
                        item.isMedia
                            ? Text("Which photo", bundle: .module)
                            : Text("Which words", bundle: .module),
                        value: String(report.messageID.prefix(12)) + "…")
                    row(Text("When", bundle: .module), value: item.at.formatted(date: .abbreviated, time: .shortened))
                    row(Text("What it is", bundle: .module), value: item.isMedia
                        ? String(localized: "A photo", bundle: .module)
                        : String(localized: "Words", bundle: .module))
                } header: {
                    Text("What goes with it", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "Not the words and not the photo. This app cannot attach them, and does not try. Nothing tells \(item.author.displayName) that you reported them.",
                        bundle: .module)
                }
                .groupedRowSurface()
                // COPY END 5aa4676a

                Section {
                    // COPY BEGIN 898cc145 [NEEDS HUMAN REVIEW]
                    Link(destination: Self.cyberTipline) {
                        Label {
                            Text("CyberTipline (United States)", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.up.right.square").foregroundStyle(palette.accentColor)
                        }
                    }
                    Link(destination: Self.cybertipCanada) {
                        Label {
                            Text("Cybertip.ca (Canada)", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.up.right.square").foregroundStyle(palette.accentColor)
                        }
                    }
                } header: {
                    Text("If this involves a child", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "Keep your own copy, and report it directly as well. These are the people who can act on it.",
                        bundle: .module)
                    // COPY END 898cc145
                }
                .groupedRowSurface()

                Section {
                    // COPY BEGIN 43d5589d [NEEDS HUMAN REVIEW]
                    Button {
                        leaving = true
                    } label: {
                        Text("Continue in your browser", bundle: .module).primaryAction()
                    }
                    .prominentActionButton()
                    .disabled(!canSend)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(
                        "This app sends nothing itself. The report is copied for you and \(formHost) opens, where you paste it and say how to reach you.",
                        bundle: .module)
                    // COPY END 43d5589d
                }

                Section {
                    // COPY BEGIN 08d848fb [NEEDS HUMAN REVIEW]
                    ShareLink(
                        item: reportFile,
                        preview: SharePreview(fileName, image: Image(systemName: "doc.text"))
                    ) {
                        Label {
                            Text("Save a copy", bundle: .module)
                        } icon: {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundStyle(palette.accentColor)
                        }
                    }
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    // COPY END 08d848fb

                    // COPY BEGIN 6da4670d [NEEDS HUMAN REVIEW]
                    Button {
                        copy(report.body)
                    } label: {
                        Label {
                            copied
                                ? Text("Copied", bundle: .module)
                                : Text("Copy the report", bundle: .module)
                        } icon: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(palette.accentColor)
                        }
                    }
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Keep it yourself", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "Worth doing before you send it. A report names a message by a fingerprint, and the fingerprint only means something while the message is still on your device.",
                        bundle: .module)
                    // COPY END 6da4670d
                }
                .groupedRowSurface()

                // COPY BEGIN 3bbdea2e [NEEDS HUMAN REVIEW]
                if noBrowser {
                    Section {
                        EmptyView()
                    } header: {
                        Text("No browser opened", bundle: .module).sectionHeading()
                    } footer: {
                        Text(
                            "Copy the report above, then go to \(formHost) in any browser.",
                            bundle: .module)
                    }
                    .groupedRowSurface()
                }
                // COPY END 3bbdea2e
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(palette.background)
            // COPY BEGIN 19f2f045 [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("Report", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
            }
            .confirmationDialog(
                Text("Leave the app to send this?", bundle: .module),
                isPresented: $leaving,
                titleVisibility: .visible
            ) {
                Button { leave() } label: { Text("Copy and continue", bundle: .module) }
                Button(role: .cancel) {} label: { Text("Not yet", bundle: .module) }
            } message: {
                Text(
                    "Your report is copied and \(formHost) opens in whichever browser this phone uses. Paste it there. Nothing is sent until you send it.",
                    bundle: .module)
            }
            // COPY END 19f2f045
        }
    }

    private func leave() {
        guard let form = Branding.reportFormURL else {
            noBrowser = true
            return
        }
        copy(report.body)
        openURL(form) { accepted in
            if !accepted { noBrowser = true }
        }
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
            UIPasteboard.general.string = text
        #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
        copied = true
    }

    private func row(_ label: Text, value: String) -> some View {
        HStack {
            label
                .font(CarpenterFont.rowDetail)
                .foregroundStyle(palette.primaryText)
            Spacer()
            Text(verbatim: value)
                .font(CarpenterFont.rowDetail)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}

#if DEBUG
    #Preview("Report a message") {
        ReportView(item: ViewedItem(Fixtures.conversation[0]))
            .themed(.default)
    }
#endif
