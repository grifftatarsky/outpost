import CarpenterKit
import SwiftUI

public struct DraftKeeping: Sendable {
    public let read: @MainActor @Sendable (DraftPlace) -> String
    public let keep: @MainActor @Sendable (String, DraftPlace) -> Void
    public let outpostCount: @MainActor @Sendable () -> Int
    public let deleteOutpost: @MainActor @Sendable () -> Void

    public init(
        read: @escaping @MainActor @Sendable (DraftPlace) -> String,
        keep: @escaping @MainActor @Sendable (String, DraftPlace) -> Void,
        outpostCount: @escaping @MainActor @Sendable () -> Int = { 0 },
        deleteOutpost: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.read = read
        self.keep = keep
        self.outpostCount = outpostCount
        self.deleteOutpost = deleteOutpost
    }
}

extension EnvironmentValues {
    @Entry public var drafts: DraftKeeping? = nil
}

extension View {
    func keepsDraft(_ words: String, at place: DraftPlace, restore: @escaping (String) -> Void) -> some View {
        modifier(KeepsDraft(words: words, place: place, restore: restore))
    }
}

private struct KeepsDraft: ViewModifier {
    @Environment(\.drafts) private var drafts
    @Environment(\.scenePhase) private var scenePhase
    @State private var pending: Task<Void, Never>?

    let words: String
    let place: DraftPlace
    let restore: (String) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard words.isEmpty, let kept = drafts?.read(place), !kept.isEmpty else { return }
                restore(kept)
            }
            .onChange(of: words) { _, typed in
                typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? keepNow(typed) : keepSoon(typed)
            }
            .onDisappear { keepNow(words) }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { keepNow(words) }
            }
    }

    private func keepSoon(_ typed: String) {
        guard let drafts else { return }
        pending?.cancel()
        let place = place
        pending = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, drafts.read(place) != typed else { return }
            drafts.keep(typed, place)
        }
    }

    private func keepNow(_ typed: String) {
        pending?.cancel()
        guard let drafts, drafts.read(place) != typed else { return }
        drafts.keep(typed, place)
    }
}
