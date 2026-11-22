import CarpenterKit
import SwiftUI

public struct PhotoRequestsHelp: Sendable {
    public var requests: [PhotoRequest]
    public var onSend: (@MainActor @Sendable (PhotoRequest) async -> String?)?
    public var onDismiss: (@MainActor @Sendable (PhotoRequest) async -> Void)?

    public init(
        requests: [PhotoRequest] = [],
        onSend: (@MainActor @Sendable (PhotoRequest) async -> String?)? = nil,
        onDismiss: (@MainActor @Sendable (PhotoRequest) async -> Void)? = nil
    ) {
        self.requests = requests
        self.onSend = onSend
        self.onDismiss = onDismiss
    }
}

extension EnvironmentValues {
    @Entry public var photoRequests = PhotoRequestsHelp()
}

struct PhotoRequestsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.clock) private var clock
    @Environment(\.dismiss) private var dismiss
    @Environment(\.photoRequests) private var help

    let onShow: (MessageID) -> Void

    @State private var sending: Set<PhotoRequest.ID> = []
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(help.requests) { request in
                        row(request)
                    }
                }
                .groupedRowSurface()
            }
            #if os(iOS)
                .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .background(palette.background)
            // COPY BEGIN 4f72d65d [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("Photo requests", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                }
            }
            .alert(
                Text("Could not send it", bundle: .module),
                isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
            ) {
                Button {
                    problem = nil
                } label: {
                    Text("OK", bundle: .module)
                }
            } message: {
                Text(verbatim: problem ?? "")
            }
            // COPY END 4f72d65d
            .onChange(of: help.requests.isEmpty) { _, empty in
                if empty { dismiss() }
            }
        }
    }

    private func row(_ request: PhotoRequest) -> some View {
        HStack(spacing: 12) {
            Button {
                onShow(request.message)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    MediaPictureView(media: request.media, author: request.sender) { _ in }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: request.person.displayName)
                            .font(CarpenterFont.rowTitle)
                            .foregroundStyle(palette.primaryText)
                        Text(verbatim: RelativeTimestampFormatter().compact(for: request.askedAt, now: clock.now))
                            .font(CarpenterFont.caption)
                            .foregroundStyle(palette.tertiaryText)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // COPY BEGIN 208d2d9b [NEEDS HUMAN REVIEW]
            Button {
                Task { await send(request) }
            } label: {
                if sending.contains(request.id) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Send", bundle: .module)
                }
            }
            .buttonStyle(.bordered)
            .disabled(sending.contains(request.id) || help.onSend == nil)
            .accessibilityLabel(Text("Send the photo again to \(request.person.displayName)", bundle: .module))
        }
        .swipeActions {
            if let onDismiss = help.onDismiss {
                Button {
                    Task { await onDismiss(request) }
                } label: {
                    Text("Dismiss", bundle: .module)
                }
            }
        }
        // COPY END 208d2d9b
    }

    private func send(_ request: PhotoRequest) async {
        guard let onSend = help.onSend else { return }
        sending.insert(request.id)
        defer { sending.remove(request.id) }
        problem = await onSend(request)
    }
}
