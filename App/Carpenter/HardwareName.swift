import Foundation

#if canImport(UIKit)
    import UIKit
#endif

enum HardwareName {
    static var ofThisDevice: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
            !simulated.isEmpty
        {
            return simulated
        }
        #if os(macOS)
            return value(of: "hw.model") ?? ""
        #else
            return value(of: "hw.machine") ?? UIDevice.current.model
        #endif
    }

    private static func value(of name: String) -> String? {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        sysctlbyname(name, &bytes, &size, nil, 0)
        let identifier = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        return identifier.isEmpty ? nil : identifier
    }
}
