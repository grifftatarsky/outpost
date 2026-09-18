#if os(macOS)
    import CarpenterKit
    import SwiftUI

    // MARK: The Mac's Settings window: the same pages, as panes

    extension YouView {
        enum SettingsPane: String, Hashable {
            case appearance, behaviour, notifications, privacy, outpost, devices, data, debug
        }

        var settingsPanes: some View {
            TabView(selection: $settingsPane) {
                Tab(value: SettingsPane.appearance) {
                    pane { appearanceScreen }
                } label: {
                    Label {
                        Text("Appearance", bundle: .module)
                    } icon: {
                        Image(systemName: "paintpalette")
                    }
                }
                Tab(value: SettingsPane.behaviour) {
                    pane { behaviourScreen }
                } label: {
                    Label {
                        Text("Behavior", bundle: .module)
                    } icon: {
                        Image(systemName: "hand.tap")
                    }
                }
                if notifications != nil {
                    Tab(value: SettingsPane.notifications) {
                        pane { notificationsScreen }
                    } label: {
                        Label {
                            Text("Notifications", bundle: .module)
                        } icon: {
                            Image(systemName: "bell.badge")
                        }
                    }
                }
                Tab(value: SettingsPane.privacy) {
                    pane { privacyScreen }
                } label: {
                    Label {
                        Text("Privacy & Safety", bundle: .module)
                    } icon: {
                        Image(systemName: "hand.raised")
                    }
                }
                Tab(value: SettingsPane.outpost) {
                    pane { outpostSettingsScreen }
                } label: {
                    Label {
                        Text("Outposts", bundle: .module)
                    } icon: {
                        Image(systemName: "rectangle.stack")
                    }
                }
                Tab(value: SettingsPane.devices) {
                    pane { devicesScreen }
                } label: {
                    Label {
                        Text("Devices", bundle: .module)
                    } icon: {
                        Image(systemName: "laptopcomputer.and.iphone")
                    }
                }
                Tab(value: SettingsPane.data) {
                    pane { dataScreen }
                } label: {
                    Label {
                        Text("Data", bundle: .module)
                    } icon: {
                        Image(systemName: "internaldrive")
                    }
                }
                #if DEBUG
                    if debugActions != nil {
                        Tab(value: SettingsPane.debug) {
                            pane { debugScreen }
                        } label: {
                            Label {
                                Text("Debug", bundle: .module)
                            } icon: {
                                Image(systemName: "ladybug")
                            }
                        }
                    }
                #endif
            }
        }

        var dataScreen: some View {
            List {
                thisDevice
                if onEraseEverything != nil { erase }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
        }

        func pane(@ViewBuilder _ page: () -> some View) -> some View {
            NavigationStack { page() }
                .frame(width: 580, height: 540)
        }
    }
#endif
