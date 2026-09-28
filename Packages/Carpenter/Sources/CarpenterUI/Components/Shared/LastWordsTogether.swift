import Foundation

extension String {
    var keepingLastWordsTogether: String {
        split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                guard let space = line.lastIndex(of: " ") else { return String(line) }
                return line.replacingCharacters(in: space...space, with: "\u{00A0}")
            }
            .joined(separator: "\n")
    }
}
