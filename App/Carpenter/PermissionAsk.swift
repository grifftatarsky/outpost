#if DEBUG
    import AVFoundation
    import Intents
    import UserNotifications

    enum PermissionAsk {
        static let argument = "--ask"

        static func runIfAsked() async {
            let arguments = ProcessInfo.processInfo.arguments
            guard let flag = arguments.firstIndex(of: argument), arguments.indices.contains(flag + 1) else { return }
            switch arguments[flag + 1] {
            case "camera":
                _ = await AVCaptureDevice.requestAccess(for: .video)
            case "focus":
                _ = await INFocusStatusCenter.default.requestAuthorization()
            case "notifications":
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            default:
                break
            }
        }
    }
#endif
