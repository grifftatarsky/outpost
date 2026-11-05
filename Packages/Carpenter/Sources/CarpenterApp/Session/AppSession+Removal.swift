import CarpenterKit
import Foundation

// MARK: When another of this member's devices removes this one

extension AppSession {
    var thisDeviceWasRemoved: Bool {
        guard let enrolment else { return false }
        return replica.registry(for: enrolment.identity.id)?.standing(of: enrolment.device.id)?.revokedAt != nil
    }

    func eraseAfterRemoval() async {
        guard enrolment != nil else { return }
        Diagnostics.identity.notice("this device was removed by another of your devices; erasing what it holds")
        state = .removed
        await eraseWhatThisPhoneKeeps()
        await persistOrReport("the mark that this device was removed") {
            try await IdentityStore(keychain: storage.keychain).markRemoved()
        }
    }
}
