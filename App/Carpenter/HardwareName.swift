import Foundation

enum HardwareName {
    static var ofThisDevice: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
            !simulated.isEmpty
        {
            return simulated
        }
        var size = 0
        sysctlbyname(model, nil, &size, nil, 0)
        guard size > 0 else { return AppRootView.deviceName }
        var value = [UInt8](repeating: 0, count: size)
        sysctlbyname(model, &value, &size, nil, 0)
        let identifier = String(decoding: value.prefix { $0 != 0 }, as: UTF8.self)
        return identifier.isEmpty ? AppRootView.deviceName : identifier
    }

    private static var model: String {
        #if os(macOS)
            return "hw.model"
        #else
            return "hw.machine"
        #endif
    }
}
