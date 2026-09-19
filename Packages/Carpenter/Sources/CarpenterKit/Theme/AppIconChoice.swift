import Foundation

public enum AppIconChoice: String, CaseIterable, Hashable, Sendable, Codable {
    case fullCobalt, fullVerdigris, fullSignalAmber, fullOxblood
    case fullAubergine, fullHangarSlate, fullOliveDrab
    case plainLight, plainDark

    case antennaCobalt, antennaVerdigris, antennaSignalAmber, antennaOxblood
    case antennaAubergine, antennaHangarSlate, antennaOliveDrab
    case antennaWhite, antennaBlack

    case mailboxCobalt, mailboxVerdigris, mailboxSignalAmber, mailboxOxblood
    case mailboxAubergine, mailboxHangarSlate, mailboxOliveDrab
    case mailboxWhite, mailboxBlack

    case filledCobalt, filledVerdigris, filledSignalAmber, filledOxblood
    case filledAubergine, filledHangarSlate, filledOliveDrab
    case filledWhite, filledBlack

    public static let `default` = AppIconChoice.plainLight

    public enum Mark: Hashable, Sendable, CaseIterable {
        case full, antenna, mailbox, filledMailbox

        public var displayName: String {
            switch self {
            case .full: String(localized: "Classic", bundle: .module, comment: "App icon drawing: the mailbox on its stand")
            case .antenna: String(localized: "Antenna", bundle: .module, comment: "App icon drawing: the mailbox with an antenna")
            case .mailbox: String(localized: "Mailbox", bundle: .module, comment: "App icon drawing: the mailbox alone")
            case .filledMailbox:
                String(localized: "Filled mailbox", bundle: .module, comment: "App icon drawing: the mailbox alone, drawn solid")
            }
        }
    }

    public var mark: Mark {
        if rawValue.hasPrefix("antenna") { return .antenna }
        if rawValue.hasPrefix("mailbox") { return .mailbox }
        if rawValue.hasPrefix("filled") { return .filledMailbox }
        return .full
    }

    public static func all(in mark: Mark) -> [AppIconChoice] {
        allCases.filter { $0.mark == mark }
    }

    public var alternateName: String? {
        self == .plainLight ? nil : "AppIcon-\(catalogueSuffix)"
    }

    public var previewAssetName: String {
        "\(alternateName ?? "AppIcon")-Preview"
    }

    public var ground: Ground {
        switch self {
        case .plainLight, .antennaWhite, .mailboxWhite, .filledWhite: .white
        case .plainDark, .antennaBlack, .mailboxBlack, .filledBlack: .black
        default: .accent
        }
    }

    public enum Ground: Hashable, Sendable {
        case white, black, accent
    }

    public var accent: Accent? {
        switch self {
        case .plainLight, .plainDark, .antennaWhite, .antennaBlack, .mailboxWhite, .mailboxBlack, .filledWhite,
            .filledBlack:
            nil
        case .fullCobalt, .antennaCobalt, .mailboxCobalt, .filledCobalt: .cobalt
        case .fullVerdigris, .antennaVerdigris, .mailboxVerdigris, .filledVerdigris: .verdigris
        case .fullSignalAmber, .antennaSignalAmber, .mailboxSignalAmber, .filledSignalAmber: .signalAmber
        case .fullOxblood, .antennaOxblood, .mailboxOxblood, .filledOxblood: .oxblood
        case .fullAubergine, .antennaAubergine, .mailboxAubergine, .filledAubergine: .aubergine
        case .fullHangarSlate, .antennaHangarSlate, .mailboxHangarSlate, .filledHangarSlate: .hangarSlate
        case .fullOliveDrab, .antennaOliveDrab, .mailboxOliveDrab, .filledOliveDrab: .oliveDrab
        }
    }

    public var displayName: String {
        guard let accent else {
            return ground == .black
                ? String(localized: "Black", bundle: .module, comment: "App icon name, a white mark on black")
                : String(localized: "White", bundle: .module, comment: "App icon name, a black mark on white")
        }
        return accent.displayName
    }

    public var spokenName: String {
        String(
            localized: "\(displayName), \(mark.displayName)", bundle: .module,
            comment: "App icon read aloud: its color, then which drawing")
    }

    private var catalogueSuffix: String {
        let prefix =
            switch mark {
            case .full: "Full"
            case .antenna: "Antenna"
            case .mailbox: "Mailbox"
            case .filledMailbox: "MailboxFilled"
            }
        switch accent {
        case .cobalt: return prefix + "Cobalt"
        case .verdigris: return prefix + "Verdigris"
        case .signalAmber: return prefix + "SignalAmber"
        case .oxblood: return prefix + "Oxblood"
        case .aubergine: return prefix + "Aubergine"
        case .hangarSlate: return prefix + "HangarSlate"
        case .oliveDrab: return prefix + "OliveDrab"
        case .monochrome, nil:
            if mark == .full { return ground == .black ? "PlainDark" : "PlainLight" }
            return prefix + (ground == .black ? "Black" : "White")
        }
    }
}
