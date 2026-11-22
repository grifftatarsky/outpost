import CloudKit
import Foundation

public enum CloudKitHold {
    public static func isHeld(_ container: CKContainer) async -> Bool {
        (try? await container.accountStatus()) == .temporarilyUnavailable
    }

    public static func isSecurityHold(_ error: any Error) -> Bool {
        if let error = error as? CKError {
            if error.code == .accountTemporarilyUnavailable { return true }
            if let partials = error.partialErrorsByItemID?.values, partials.contains(where: isSecurityHold) {
                return true
            }
        }
        return mentionsProtectedCloudStorage(error as NSError, depth: 0)
    }

    private static func mentionsProtectedCloudStorage(_ error: NSError, depth: Int) -> Bool {
        guard depth < 5 else { return false }
        let said = [error.domain, error.localizedDescription, error.userInfo[NSDebugDescriptionErrorKey] as? String ?? ""]
            .joined(separator: " ")
        if said.contains("ProtectedCloudStorage") || said.contains("PCSNoPublicIdentity")
            || said.range(of: #"\bPCS[A-Z]\w*"#, options: .regularExpression) != nil
        {
            return true
        }
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
        return mentionsProtectedCloudStorage(underlying, depth: depth + 1)
    }
}
