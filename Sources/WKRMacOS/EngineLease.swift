import AppKit
import Darwin
import Foundation

/// Public and future Private builds share this non-blocking per-user lease.
/// Older builds do not know the lease, so they must be stopped before switching.
final class EngineLease {
    private var descriptor: Int32
    static let peerBundleIDs = ["io.github.yuhkis.wkr-macos", "io.github.yuhkis.wkr-macos.public", "io.github.yuhkis.wkr-macos.private", "io.github.yuhkis.wkr-macos.v1", "io.github.yuhkis.wkr-macos.v1-archive"]
    static var peerIsRunning: Bool {
        peerBundleIDs.contains { id in
            NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .contains { $0.processIdentifier != getpid() && !$0.isTerminated }
        }
    }
    init?(url: URL = FileManager.default.temporaryDirectory.appendingPathComponent("wkr-converter-\(getuid()).lock")) {
        let fd = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return nil }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(),
              (info.st_mode & S_IFMT) == S_IFREG, fchmod(fd, S_IRUSR | S_IWUSR) == 0,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return nil }
        descriptor = fd
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}
