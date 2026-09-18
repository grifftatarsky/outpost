import CarpenterApp

extension AppSession {
    func optIntoNames() async {
        await setSharesName(true)
        await setShowsOthersNames(true)
    }
}
