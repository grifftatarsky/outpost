import CarpenterKit
import SwiftUI

struct SoloCheckNotice: View {
    @Environment(\.palette) private var palette

    let state: SoloCheckPresentation
    let onAnswer: ((Bool) async -> Void)?
    let onAskAgain: ((Bool) async -> Void)?
    let partner: Member?
    let onBlock: ((ParticipantID) async -> Void)?
    let onStopRequiring: (() async -> Void)?
    let phrase: String?

    @State private var working = false
    @State private var blocking: Member?

    var body: some View {
        Group {
            if case .refused(_, _, let answerable) = state {
                refusal(answerable: answerable)
            } else {
                held
            }
        }
        .padding(.horizontal, CarpenterMetrics.screenMargin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.elevatedSurface)
        .accessibilityElement(children: .contain)
        .confirmingBlock($blocking) { person in await onBlock?(person) }
    }

    private func refusal(answerable: Member?) -> some View {
        RefusedCheck(
            placement: .notice,
            // COPY BEGIN 17ca25c6 [NEEDS HUMAN REVIEW]
            readings: Text(
                "Usually that means one of you read them wrong, or read the ones from another conversation. It can also mean somebody is in the middle of this one.",
                bundle: .module),
            protection: Text(
                "Nothing here has been deleted and nothing has been sent about it. What is already here is what there is to look at.",
                bundle: .module),
            nextStep: answerable == nil
                ? Text(
                    "Read these to each other in person, then check again.", bundle: .module)
                : Text(
                    "\(answerable?.displayName ?? "") has asked again. Read these to each other in person, then answer here.",
                    bundle: .module),
            phrase: phrase
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if state.canAnswer, let onAnswer {
                    answers(onAnswer)
                } else if let onAskAgain {
                    Button {
                        Task { working = true; await onAskAgain(false); working = false }
                    } label: {
                        Text("Check again", bundle: .module).primaryAction()
                    }
                    .prominentActionButton()
                    .disabled(working)
                }
                block
            }
            // COPY END 17ca25c6
        }
    }

    private func answers(_ onAnswer: @escaping (Bool) async -> Void) -> some View {
        AdaptiveStack(spacing: 10) {
            // COPY BEGIN 72934cc1 [NEEDS HUMAN REVIEW]
            Button {
                Task { working = true; await onAnswer(false); working = false }
            } label: {
                Text("They do not match", bundle: .module)
                    .font(CarpenterFont.button)
                    .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
                    .background(
                        palette.elevatedSurface,
                        in: .rect(
                            cornerRadius: CarpenterMetrics.buttonRadius, style: .continuous))
            }
            .foregroundStyle(palette.primaryText)
            .disabled(working)
            // COPY END 72934cc1

            // COPY BEGIN fbf3b5f0 [NEEDS HUMAN REVIEW]
            Button {
                Task { working = true; await onAnswer(true); working = false }
            } label: {
                Text("They match", bundle: .module).primaryAction()
            }
            .prominentActionButton()
            .disabled(working)
            // COPY END fbf3b5f0
        }
    }

    private var held: some View {
        ComposerNotice(symbol: symbol, headline: headline, detail: explanation) {
            VStack(alignment: .leading, spacing: 12) {
                if state.canAnswer, let phrase {
                    VerificationPhrase(phrase)
                        .frame(maxWidth: .infinity)
                }
                if state.canAnswer, let onAnswer { answers(onAnswer) }
                stopRequiring
                block
            }
        }
    }

    // COPY BEGIN ebfa1e81 [NEEDS HUMAN REVIEW]
    @ViewBuilder private var stopRequiring: some View {
        if case .heldByYourSetting = state, let onStopRequiring {
            Button {
                Task { working = true; await onStopRequiring(); working = false }
            } label: {
                Text("Stop requiring this", bundle: .module)
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(working)
            .padding(.top, 2)
        }
    }
    // COPY END ebfa1e81

    // COPY BEGIN bf5d6ce6 [NEEDS HUMAN REVIEW]
    @ViewBuilder private var block: some View {
        if let partner, onBlock != nil, !partner.isAnonymous {
            Button {
                blocking = partner
            } label: {
                Text("Block \(partner.displayName)", bundle: .module)
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.destructive)
            }
            .buttonStyle(.plain)
            .disabled(working)
            .padding(.top, 2)
        }
    }
    // COPY END bf5d6ce6

    private let symbol = "person.crop.circle.badge.questionmark"

    // COPY BEGIN 20531eb4 [NEEDS HUMAN REVIEW]
    private var headline: Text {
        switch state {
        case .refused:
            return Text(verbatim: "")
        case .heldByYourSetting:
            return Text("Check who you are talking to first", bundle: .module)
        case .heldByYourChoice:
            return Text("Held until this is answered", bundle: .module)
        case .nothing, .waitingOnThem, .waitingOnYou:
            return Text(verbatim: "")
        }
    }
    // COPY END 20531eb4

    private var explanation: Text {
        // COPY BEGIN 432ca2b5 [NEEDS HUMAN REVIEW]
        switch state {
        case .refused:
            return Text(verbatim: "")
        case .heldByYourSetting(let askedBy, let since):
            if askedBy != nil {
                return Text(
                    "You asked to check who you are talking to before a conversation opens. They have asked too — read these to each other, then answer here.",
                    bundle: .module)
            } else if since != nil {
                return Text(
                    "You asked to check who you are talking to before a conversation opens. Your question is the one standing — this opens when they answer it, or when you stop requiring it.",
                    bundle: .module)
            } else {
                return Text(
                    "You asked to check who you are talking to before a conversation opens. Ask them under Check who I am talking to, in this conversation's menu, then read the characters to each other.",
                    bundle: .module)
            }
        case .heldByYourChoice:
            return Text(
                "You chose to wait until this is answered. Nothing has been sent about it beyond the question itself, and nothing here says whether they have seen it.",
                bundle: .module)
        case .nothing, .waitingOnThem, .waitingOnYou:
            return Text(verbatim: "")
        }
        // COPY END 432ca2b5
    }
}

struct SoloCheckLine: View {
    @Environment(\.palette) private var palette

    let state: SoloCheckPresentation
    let onAnswer: ((Bool) async -> Void)?
    let phrase: String?

    @State private var answering = false

    // COPY BEGIN 56ea5d36 [NEEDS HUMAN REVIEW]
    var body: some View {
        switch state {
        case .waitingOnThem:
            line(Text("You asked to check who you are talking to.", bundle: .module))
        case .waitingOnYou(let askedBy, _):
            line(
                Text(
                    "\(askedBy.displayName) has asked to check who you are before carrying on.",
                    bundle: .module))
        case .nothing, .heldByYourSetting, .heldByYourChoice, .refused:
            EmptyView()
        }
    }
    // COPY END 56ea5d36

    private func line(_ text: Text) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .accessibilityHidden(true)
            text
                .font(CarpenterFont.caption)
                .foregroundStyle(palette.secondaryText)
            Spacer(minLength: 0)
            // COPY BEGIN 2fb2deb0 [NEEDS HUMAN REVIEW]
            if state.canAnswer, onAnswer != nil {
                Button {
                    answering = true
                } label: {
                    Text("Answer", bundle: .module)
                        .font(CarpenterFont.rowDetail.weight(.semibold))
                        .foregroundStyle(palette.accentColor)
                        .padding(.vertical, 8)
                        .padding(.leading, 8)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            // COPY END 2fb2deb0
        }
        .padding(.horizontal, CarpenterMetrics.screenMargin)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(palette.elevatedSurface)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $answering) {
            AnswerWhoYouAreTalkingToSheet(
                onAnswer: { matched in await onAnswer?(matched) }, phrase: phrase)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

struct AskWhoYouAreTalkingToSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let onAsk: (Bool) async -> Void
    let phrase: String?

    @State private var holding = false
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // COPY BEGIN 9501f864 [NEEDS HUMAN REVIEW]
                    ChoiceRow(
                        title: Text("Keep talking", bundle: .module),
                        detail: Text(
                            "A quiet line says the check is open. Nothing else changes.",
                            bundle: .module),
                        isSelected: !holding
                    ) { holding = false }
                    // COPY END 9501f864

                    // COPY BEGIN 2ddce609 [NEEDS HUMAN REVIEW]
                    ChoiceRow(
                        title: Text("Hold until it is answered", bundle: .module),
                        detail: Text(
                            "Closes your side of this conversation. Theirs is untouched — they are told you asked, and they can answer.",
                            bundle: .module),
                        isSelected: holding
                    ) { holding = true }
                } header: {
                    Text("Until they answer", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "Both of you already have the same characters. Read them to each other, out loud, on a line you trust.",
                        bundle: .module)
                    // COPY END 2ddce609
                }
                .groupedRowSurface()

                if let phrase {
                    Section {
                        VerificationPhrase(phrase)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .groupedRowSurface()
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            // COPY BEGIN daba07eb [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("Who you are talking to", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            working = true
                            await onAsk(holding)
                            working = false
                            dismiss()
                        }
                    } label: {
                        Text("Ask", bundle: .module)
                    }
                    .disabled(working)
                }
            // COPY END daba07eb
            }
        }
    }
}

struct AnswerWhoYouAreTalkingToSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let onAnswer: (Bool) async -> Void
    let phrase: String?

    @State private var working = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                // COPY BEGIN 975affde [NEEDS HUMAN REVIEW]
                Text(
                    "Read these to each other, out loud, on a line you trust.",
                    bundle: .module)
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                // COPY END 975affde

                if let phrase {
                    VerificationPhrase(phrase)
                        .frame(maxWidth: .infinity)
                }

                AdaptiveStack(spacing: 10) {
                    // COPY BEGIN fd066c84 [NEEDS HUMAN REVIEW]
                    Button {
                        Task { working = true; await onAnswer(false); working = false; dismiss() }
                    } label: {
                        Text("They do not match", bundle: .module)
                            .font(CarpenterFont.button)
                            .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
                            .background(
                                palette.elevatedSurface,
                                in: .rect(
                                    cornerRadius: CarpenterMetrics.buttonRadius,
                                    style: .continuous))
                    }
                    .foregroundStyle(palette.primaryText)
                    .disabled(working)
                    // COPY END fd066c84

                    // COPY BEGIN b3f3d160 [NEEDS HUMAN REVIEW]
                    Button {
                        Task { working = true; await onAnswer(true); working = false; dismiss() }
                    } label: {
                        Text("They match", bundle: .module).primaryAction()
                    }
                    .prominentActionButton()
                    .disabled(working)
                    // COPY END b3f3d160
                }

                // COPY BEGIN 5b00c4bd [NEEDS HUMAN REVIEW]
                Text(
                    "Saying they do not match closes this conversation, both ways, until you have checked again in person. Nothing already here is deleted.",
                    bundle: .module)
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                // COPY END 5b00c4bd

                Spacer(minLength: 0)
            }
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.background)
            // COPY BEGIN c409c3fa [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("Who you are talking to", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Not now", bundle: .module) }
                }
            }
            // COPY END c409c3fa
        }
    }
}
