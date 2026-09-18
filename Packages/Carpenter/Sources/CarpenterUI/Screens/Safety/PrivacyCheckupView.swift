import CarpenterKit
import SwiftUI

public struct PrivacyCheckupView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let owner: Member
    private let onFinish: (PrivacyChoices) async -> Void
    private let onSkip: (() async -> Void)?

    @State private var choices: PrivacyChoices
    @State private var path: [Route] = []
    @State private var finishing = false

    public init(
        owner: Member,
        current: PrivacyChoices,
        onFinish: @escaping (PrivacyChoices) async -> Void,
        onSkip: (() async -> Void)? = nil
    ) {
        self.owner = owner
        self.onFinish = onFinish
        self.onSkip = onSkip
        _choices = State(initialValue: current)
    }

    enum Preset: Hashable {
        case familiar, lockedDown

        var choices: PrivacyChoices {
            switch self {
            case .familiar: .familiar
            case .lockedDown: .lockedDown
            }
        }
    }

    enum Step: Int, Hashable, CaseIterable {
        case shareName, sharePhoto, shareFocus, showOthersNames, showOthersPhotos, showOthersFocus,
            readReceipts, blurSensitive, blockKnownAbusers, soloCheck, restoreAsks, restoreHold,
            outpostsOn, outpostReach, outpostFace, outpostReview

        func next(under choices: PrivacyChoices) -> Step? {
            var candidate = Step(rawValue: rawValue + 1)
            while let step = candidate, !step.applies(under: choices) {
                candidate = Step(rawValue: step.rawValue + 1)
            }
            return candidate
        }

        func applies(under choices: PrivacyChoices) -> Bool {
            switch self {
            case .outpostReach, .outpostFace, .outpostReview: return choices.outposts.isOn
            default: return true
            }
        }

        func position(under choices: PrivacyChoices) -> (at: Int, of: Int) {
            let walk = Step.allCases.filter { $0.applies(under: choices) }
            return ((walk.firstIndex(of: self) ?? 0) + 1, walk.count)
        }

        static let firstOutpostPage = Step.outpostsOn
    }

    enum Route: Hashable {
        case preset(Preset)
        case step(Step)
    }

    public var body: some View {
        NavigationStack(path: $path) {
            doors
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .preset(let preset):
                        PresetPage(preset: preset, owner: owner, finishing: finishing) {
                            choices = preset.choices
                            path.append(.step(.firstOutpostPage))
                        }
                    case .step(let step):
                        StepPage(step: step, owner: owner, choices: $choices, finishing: finishing) {
                            if let next = step.next(under: choices) {
                                path.append(.step(next))
                            } else {
                                finish(with: choices)
                            }
                        }
                    }
                }
        }
    }

    private func finish(with chosen: PrivacyChoices) {
        guard !finishing else { return }
        finishing = true
        Task {
            await onFinish(chosen)
            finishing = false
        }
    }

    private var doors: some View {
        List {
            SettingsHeaderCard(
                icon: "hand.raised.fill",
                title: Text("Who sees what", bundle: .module),
                paragraph: Text(
                    "Before you talk to anybody, choose what this device tells other people. Nothing leaves it until you send something, and everything here can be changed later under You › Privacy & Safety.",
                    bundle: .module))

            Section {
                NavigationLink(value: Route.preset(.familiar)) {
                    SettingsRow(
                        icon: "person.2.fill",
                        title: Text("Familiar and open", bundle: .module),
                        subtitle: Text(
                            "Share the way Messages does: your name and photo, theirs, and when you have notifications silenced.",
                            bundle: .module))
                }
                NavigationLink(value: Route.preset(.lockedDown)) {
                    SettingsRow(
                        icon: "lock.fill",
                        title: Text("Locked down", bundle: .module),
                        subtitle: Text(
                            "Share as little as possible: codes instead of names, and nobody talks to you alone until you have checked who they are.",
                            bundle: .module))
                }
            } footer: {
                Text("Each one shows you what it looks like before you take it.", bundle: .module)
            }
            .groupedRowSurface()

            Section {
                NavigationLink(value: Route.step(.shareName)) {
                    SettingsRow(
                        icon: "slider.horizontal.3", tone: .device,
                        title: Text("Customize privacy settings", bundle: .module),
                        subtitle: Text("One switch at a time, with what each one changes.", bundle: .module))
                }
            }
            .groupedRowSurface()

            if let onSkip {
                Section {
                    Button {
                        guard !finishing else { return }
                        finishing = true
                        Task {
                            await onSkip()
                            finishing = false
                        }
                    } label: {
                        Text("Decide later", bundle: .module)
                            .font(CarpenterFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Until you decide, everything stays off.", bundle: .module)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(Text("Privacy", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if onSkip == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
            }
        }
        .disabled(finishing)
    }
}
