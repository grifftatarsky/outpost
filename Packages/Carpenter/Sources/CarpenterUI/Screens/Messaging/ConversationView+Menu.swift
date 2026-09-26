import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

// MARK: The room's own menu, and what it says about a repair

extension ConversationView {
    private var wantsAttention: Bool { pendingJoinCount > 0 || uncheckedCount > 0 }

    var hasRoomActions: Bool {
        onInvite != nil || onShowInvite != nil || onReviewJoins != nil || onWhoYouAreTalkingTo != nil
            || onAskWhoYouAreTalkingTo != nil || onRoomAccess != nil || onRoomNotifications != nil
            || onRoomMembers != nil || onRepair != nil || notGoneHelp.onShowWaiting != nil
            || onDelete != nil
    }

    var roomMenu: some View {
        Menu {
            // COPY BEGIN fac748d4 [NEEDS HUMAN REVIEW]
            if let onRoomMembers {
                Button(action: onRoomMembers) {
                    Label {
                        Text("Who is in this room", bundle: .module)
                    } icon: {
                        Image(systemName: "person.2")
                    }
                }
            }
            if let onInvite {
                Button(action: onInvite) {
                    Label {
                        Text("Invite someone", bundle: .module)
                    } icon: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            if let onShowInvite {
                Button(action: onShowInvite) {
                    Label {
                        Text("Show the invite", bundle: .module)
                    } icon: {
                        Image(systemName: "qrcode")
                    }
                }
            }
            if let onReviewJoins, pendingJoinCount > 0 || uncheckedCount > 0 {
                Button(action: onReviewJoins) {
                    Label {
                        if pendingJoinCount > 0 {
                            Text("Review \(pendingJoinCount) waiting to join", bundle: .module)
                        } else {
                            Text("Check who joined on your invitation (\(uncheckedCount))", bundle: .module)
                        }
                    } icon: {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                    }
                }
            }
            if let onWhoYouAreTalkingTo {
                Button(action: onWhoYouAreTalkingTo) {
                    Label {
                        Text("Who you are talking to", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark.shield")
                    }
                }
            }
            if onAskWhoYouAreTalkingTo != nil {
                Button {
                    askingCheck = true
                } label: {
                    Label {
                        Text("Check who I am talking to", bundle: .module)
                    } icon: {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                    }
                }
            }
            if let onShowWaiting = notGoneHelp.onShowWaiting {
                Button(action: onShowWaiting) {
                    Label {
                        Text("Who this is waiting on", bundle: .module)
                    } icon: {
                        Image(systemName: "hourglass")
                    }
                }
            }
            if let onRoomNotifications {
                Button(action: onRoomNotifications) {
                    Label {
                        Text("Notifications", bundle: .module)
                    } icon: {
                        Image(systemName: "bell")
                    }
                }
            }
            if let onRoomAccess {
                Button(action: onRoomAccess) {
                    Label {
                        Text("Who gets in", bundle: .module)
                    } icon: {
                        Image(systemName: "lock")
                    }
                }
            }
            // COPY END fac748d4
            if let onRepair {
                Group {
                    if repairTargets.count > 1 {
                        Menu {
                            // COPY BEGIN 01e05e21 [NEEDS HUMAN REVIEW]
                            Button {
                                Task { await onRepair(nil) }
                            } label: {
                                Label {
                                    Text("Everyone in the room", bundle: .module)
                                } icon: {
                                    Image(systemName: "person.3")
                                }
                            }
                            // COPY END 01e05e21
                            Divider()
                            ForEach(repairTargets) { person in
                                Button {
                                    Task { await onRepair(person.id) }
                                } label: {
                                    Text(person.displayName)
                                }
                            }
                        } label: {
                            repairLabel
                        }
                    } else {
                        Button {
                            Task { await onRepair(nil) }
                        } label: {
                            repairLabel
                        }
                    }
                }
                .disabled(repair.map { !$0.isComplete } ?? false)
            }
            // COPY BEGIN 405f1a05 [NEEDS HUMAN REVIEW]
            if let onDelete {
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label {
                        Text("Delete", bundle: .module)
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
                .tint(palette.destructive)
            }
            // COPY END 405f1a05
        } label: {
            Image(systemName: wantsAttention ? "bell.circle.fill" : "ellipsis.circle")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(wantsAttention ? palette.accentFill : palette.primaryText)
        }
        // COPY BEGIN f2cca848 [NEEDS HUMAN REVIEW]
        .accessibilityLabel(
            wantsAttention
                ? Text("Room settings, something needs an answer", bundle: .module)
                : Text("Room settings", bundle: .module))
        // COPY END f2cca848
    }

    // COPY BEGIN 8833362b [NEEDS HUMAN REVIEW]
    private var repairLabel: some View {
        Label {
            Text("Check for missing history", bundle: .module)
        } icon: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
    }
    // COPY END 8833362b
}
