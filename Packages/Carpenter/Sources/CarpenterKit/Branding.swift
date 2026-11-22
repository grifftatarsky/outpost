import Foundation

public enum Branding {
    public static var displayName: String {
        let info = Bundle.main.infoDictionary
        let name =
            info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? ""
        return name.isEmpty ? fallbackDisplayName : name
    }

    private static var fallbackDisplayName: String {
        ProcessInfo.processInfo.environment["APP_DISPLAY_NAME"] ?? ""
    }

    public static var urlScheme: String {
        let types = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]]
        let schemes = types?.compactMap { $0["CFBundleURLSchemes"] as? [String] }.flatMap(\.self)
        return schemes?.first ?? ProcessInfo.processInfo.environment["APP_URL_SCHEME"] ?? ""
    }

    public static var reportFormURL: URL? {
        let raw =
            Bundle.main.infoDictionary?["ReportFormURL"] as? String
            ?? ProcessInfo.processInfo.environment["APP_REPORT_FORM_URL"] ?? ""
        return raw.isEmpty ? nil : URL(string: raw)
    }

    public static var contactFormURL: URL? {
        let raw =
            Bundle.main.infoDictionary?["ContactFormURL"] as? String
            ?? ProcessInfo.processInfo.environment["APP_CONTACT_FORM_URL"] ?? ""
        return raw.isEmpty ? nil : URL(string: raw)
    }

    public static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        switch (short.isEmpty, build.isEmpty) {
        case (false, false): return "\(short) (\(build))"
        case (false, true): return short
        case (true, false): return build
        case (true, true): return "unknown"
        }
    }
}
