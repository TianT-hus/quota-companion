import Foundation
import Darwin

/// An advisory lock is released by the OS even after a crash; no stale PID files.
final class CompanionInstanceLease {
    private let descriptor: Int32
    private init(_ descriptor: Int32) { self.descriptor = descriptor }
    static func acquire(directory: URL? = nil) -> CompanionInstanceLease? {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuotaCompanion")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { return nil }
        let fd = Darwin.open(directory.appendingPathComponent("app-instance.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(fd); return nil }
        return CompanionInstanceLease(fd)
    }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}
