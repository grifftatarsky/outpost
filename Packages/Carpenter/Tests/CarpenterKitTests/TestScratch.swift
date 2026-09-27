import Foundation

enum TestScratch {
    static let root: URL = {
        let runs = URL.temporaryDirectory.appending(path: "carpenter-test-runs", directoryHint: .isDirectory)
        let files = FileManager.default
        for name in (try? files.contentsOfDirectory(atPath: runs.path)) ?? [] {
            guard let pid = Int32(name), pid != getpid(), kill(pid, 0) == -1, errno == ESRCH else { continue }
            try? files.removeItem(at: runs.appending(path: name))
        }
        let mine = runs.appending(path: "\(getpid())", directoryHint: .isDirectory)
        try? files.createDirectory(at: mine, withIntermediateDirectories: true)
        return mine
    }()
}
