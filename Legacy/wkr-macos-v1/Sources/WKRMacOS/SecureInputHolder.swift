import Darwin
import Foundation
import IOKit
import WKRCore

enum SecureInputHolder {
    static func current() -> (pid: Int32?, liveness: SecureInputHolderLiveness) {
        guard let pid = holderPID() else { return (nil, .unknown) }
        return (pid, isRunning(pid) ? .alive : .gone)
    }

    private static func holderPID() -> Int32? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(root) }

        let property = IORegistryEntryCreateCFProperty(
            root,
            "IOConsoleUsers" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
        guard let sessions = property as? [[String: Any]] else { return nil }

        for session in sessions {
            guard let value = session["kCGSSessionSecureInputPID"] as? NSNumber else {
                continue
            }
            return value.int32Value
        }
        return nil
    }

    private static func isRunning(_ pid: Int32) -> Bool {
        guard kill(pid, 0) != 0 else { return true }
        return errno == EPERM
    }
}
