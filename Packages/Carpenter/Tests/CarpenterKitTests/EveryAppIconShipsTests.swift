import Foundation
import Testing

@testable import CarpenterKit

@Suite("Every app icon ships")
struct EveryAppIconShipsTests {
    private var repository: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    private var catalogue: URL { repository.appending(path: "App/Carpenter/Assets.xcassets") }

    @Test("Every choice has an icon set and a preview in the catalogue")
    func everyChoiceIsDrawn() {
        for choice in AppIconChoice.allCases {
            let set = choice.alternateName ?? "AppIcon"
            #expect(
                FileManager.default.fileExists(atPath: catalogue.appending(path: "\(set).appiconset/Contents.json").path),
                "\(choice) has no icon set named \(set)")
            #expect(
                FileManager.default.fileExists(atPath: catalogue.appending(path: "\(choice.previewAssetName).imageset/Contents.json").path),
                "\(choice) has no preview named \(choice.previewAssetName)")
        }
    }

    @Test("Every alternate icon is named to the build, and nothing else is")
    func theBuildKnowsEveryAlternate() throws {
        let project = try String(
            contentsOf: repository.appending(path: "App/Carpenter.xcodeproj/project.pbxproj"), encoding: .utf8)
        let lists = project.matches(of: /"ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES\[sdk=iphone\*\]" = "([^"]*)";/)
        #expect(!lists.isEmpty, "the build names no alternate icons")

        let expected = Set(AppIconChoice.allCases.compactMap(\.alternateName))
        for list in lists {
            let named = Set(list.1.split(separator: " ").map(String.init))
            #expect(named == expected, "the build and the choices disagree: \(named.symmetricDifference(expected).sorted())")
        }
    }

    @Test("Every icon set in the catalogue is one somebody can choose")
    func nothingIsLeftBehind() throws {
        let sets = try FileManager.default.contentsOfDirectory(atPath: catalogue.path)
            .filter { $0.hasSuffix(".appiconset") }
            .map { String($0.dropLast(".appiconset".count)) }
        let chosen = Set(AppIconChoice.allCases.map { $0.alternateName ?? "AppIcon" })
        #expect(Set(sets) == chosen, "orphaned or missing sets: \(Set(sets).symmetricDifference(chosen).sorted())")
    }

    @Test("No app icon carries an alpha channel, which App Store Connect refuses on upload")
    func everyIconIsOpaque() throws {
        let sets = try FileManager.default.contentsOfDirectory(atPath: catalogue.path).filter { $0.hasSuffix(".appiconset") }
        for set in sets {
            let folder = catalogue.appending(path: set)
            for file in try FileManager.default.contentsOfDirectory(atPath: folder.path) where file.hasSuffix(".png") {
                let bytes = try Data(contentsOf: folder.appending(path: file))
                let colourType = bytes.count > 25 ? bytes[25] : 0
                #expect(colourType == 2, "\(set)/\(file) has PNG colour type \(colourType); 2 is RGB with no alpha")
            }
        }
    }

    @Test("A member who has never chosen sees the icon the app ships with selected")
    func theDefaultIsThePrimary() {
        #expect(AppIconChoice.default.alternateName == nil)
    }

    @Test("Every drawing offers every colour")
    func everyMarkIsComplete() {
        for mark in AppIconChoice.Mark.allCases {
            let accents = Set(AppIconChoice.all(in: mark).compactMap(\.accent))
            #expect(accents.count == Accent.allCases.count - 1, "\(mark) is missing a colour")
            #expect(AppIconChoice.all(in: mark).contains { $0.ground == .white })
            #expect(AppIconChoice.all(in: mark).contains { $0.ground == .black })
        }
    }
}
