import Foundation

#if canImport(Darwin)
    import Darwin
#endif

struct CrossProcessLock {
    private let url: URL

    init(forDirectory directory: URL) {
        url = directory.appending(path: ".carpenter.lock")
    }

    func whileLocked<T>(_ work: () throws -> T) rethrows -> T {
        #if canImport(Darwin)
            guard let descriptor = open() else { return try work() }
            defer {
                flock(descriptor, LOCK_UN)
                close(descriptor)
            }
            return try work()
        #else
            return try work()
        #endif
    }

    #if canImport(Darwin)
        private func open() -> Int32? {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

            let descriptor = Darwin.open(url.path, O_RDWR | O_CREAT, 0o644)
            guard descriptor >= 0 else { return nil }
            guard flock(descriptor, LOCK_EX) == 0 else {
                close(descriptor)
                return nil
            }
            return descriptor
        }
    #endif
}
