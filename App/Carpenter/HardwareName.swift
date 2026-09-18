import Foundation
import UIKit

enum HardwareName {
    static var ofThisDevice: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
            !simulated.isEmpty
        {
            return simulated
        }
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return UIDevice.current.model }
        var value = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.machine", &value, &size, nil, 0)
        let identifier = String(decoding: value.prefix { $0 != 0 }, as: UTF8.self)
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
}
