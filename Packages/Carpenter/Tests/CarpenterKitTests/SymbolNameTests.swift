#if canImport(AppKit)
    import AppKit
    import Foundation
    import Testing

    @Suite("System symbol names")
    struct SymbolNameTests {
        private var sourceRoots: [URL] {
            let repository = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // CarpenterKitTests
                .deletingLastPathComponent()  // Tests
                .deletingLastPathComponent()  // Carpenter
                .deletingLastPathComponent()  // Packages
                .deletingLastPathComponent()  // <repository>
            return [
                repository.appending(path: "Packages/Carpenter/Sources"),
                repository.appending(path: "App"),
            ]
        }

        @Test("Every symbol the app asks for exists")
        func everySymbolResolves() throws {
            let pattern = /systemName:\s*"([^"]+)"/
            var named: Set<String> = []

            for root in sourceRoots {
                guard
                    let files = FileManager.default.enumerator(
                        at: root, includingPropertiesForKeys: nil)
                else { continue }

                for case let file as URL in files where file.pathExtension == "swift" {
                    guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                    for match in text.matches(of: pattern) {
                        named.insert(String(match.1))
                    }
                }
            }

            #expect(named.count > 20, "the scan found almost nothing, so it is not scanning")

            let missing = named
                .filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
                .sorted()
            #expect(
                missing.isEmpty,
                "these names draw nothing at all: \(missing.joined(separator: ", "))")
        }
    }
#endif
