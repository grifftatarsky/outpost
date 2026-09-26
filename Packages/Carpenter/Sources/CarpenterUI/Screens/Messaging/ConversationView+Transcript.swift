import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

// MARK: What was said, and the marks around it

extension ConversationView {
    var transcript: some View {
        ScrollViewReader { scroller in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                if let first = entries.first {
                    stamp(dayHeading(for: first.at))
                        .padding(.bottom, 12)
                }

                ForEach(items) { item in
                    switch item {
                    case .run(let run):
                        MessageRunView(
                            run: run, onHide: onHide, actions: messageActions,
                            onShowDetail: { detailing = $0 },
                            onSeen: onSeen, delay: messageDelay
                        )
                        .padding(.bottom, 8)
                        .id(item.id)
                    case .notice(let notice):
                        let position = noticePositions[notice.id] ?? .alone
                        stamp(NoticeCopy.text(for: notice))
                            .padding(.top, position.opensARun ? 6 : 0)
                            .padding(.bottom, position.closesARun ? 14 : 4)
                            .id(item.id)
                            .transition(.opacity)
                    }
                }

                // A transcript that is quietly short reads as something having failed to load, so
                // the omission is said rather than left to be noticed.
                if hiddenCount > 0 {
                    hiddenNotice
                        .padding(.top, 10)
                }

                Color.clear
                    .frame(height: 1)
                    .id(Self.bottom)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .animation(reduceMotion ? nil : .bouncy(duration: 0.34, extraBounce: 0.12), value: messages.count)
        }
        .measuringBubbleWidth()
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onChange(of: sent) { _, _ in scrollToBottom(scroller) }
        .onChange(of: messages.last?.id) { _, _ in scrollToBottom(scroller) }
        }
    }

    private static let bottom = "conversation.bottom"

    private func scrollToBottom(_ scroller: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            scroller.scrollTo(Self.bottom, anchor: .bottom)
        }
    }

    @ViewBuilder
    private var hiddenNotice: some View {
        if let onRevealHidden {
            // COPY BEGIN d6ec7219 [NEEDS HUMAN REVIEW]
            Button {
                Task { await onRevealHidden() }
            } label: {
                stamp(
                    Text(
                        "\(hiddenCount) hidden by you. Nobody else is affected.",
                        bundle: .module))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text("Show \(hiddenCount) messages you hid in this conversation", bundle: .module))
        } else {
            stamp(Text("\(hiddenCount) hidden by you. Nobody else is affected.", bundle: .module))
            // COPY END d6ec7219
        }
    }

    private func stamp(_ text: Text) -> some View {
        text
            .font(.caption2.weight(.semibold))
            .foregroundStyle(palette.quaternaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func stamp(_ text: String) -> some View {
        stamp(Text(text))
    }

    // COPY BEGIN 9e0c1aab [NEEDS HUMAN REVIEW]
    private func dayHeading(for date: Date) -> String {
        let formatter = RelativeTimestampFormatter()
        let day = formatter.roomsList(for: date, now: clock.now)
        let time = date.formatted(.dateTime.hour().minute())
        return Calendar.current.isDate(date, inSameDayAs: clock.now)
            ? String(localized: "Today \(time)", bundle: .module, comment: "Transcript day heading")
            : "\(day) \(time)"
    }
    // COPY END 9e0c1aab

    // COPY BEGIN ef0e3f33 [NEEDS HUMAN REVIEW]
    func removedNotice(by remover: Member) -> some View {
        ComposerNotice(
            symbol: "person.crop.circle.badge.xmark",
            headline: Text("You were removed from this room", bundle: .module),
            detail: Text(
                "\(remover.displayName) removed you. Everything already here is still yours to read. You will not receive anything new.",
                bundle: .module))
    }
    // COPY END ef0e3f33

    // COPY BEGIN afb31611 [NEEDS HUMAN REVIEW]
    var leftNotice: some View {
        ComposerNotice(
            symbol: "figure.walk.departure",
            headline: Text("You left this room", bundle: .module),
            detail: Text(
                "Everything already here is still yours to read. You will not receive anything new, and the room has been told you left.",
                bundle: .module))
    }
    // COPY END afb31611
}
