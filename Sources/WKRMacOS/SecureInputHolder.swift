import Darwin
import Foundation
import IOKit
import WKRCore

/// Reads which process holds the session's Secure Event Input.
///
/// `IsSecureEventInputEnabled()` says *that* the gate is closed but never *who*
/// closed it, and the answer decides what the user should do: quit that
/// application, wait for the system to release it, or end the login session.
/// The holder is exposed through the undocumented `kCGSSessionSecureInputPID`
/// entry of IOKit's `IOConsoleUsers`, readable without any privilege.
///
/// Being undocumented, this is used for reporting only. The conversion gate
/// itself never consults it: `IsSecureEventInputEnabled()` stays the sole
/// authority, so a future macOS that drops or renames the key degrades the log
/// line to `holder=unknown` and changes nothing about when the app converts.
enum SecureInputHolder {
    /// The current holder, queried fresh.
    ///
    /// Call this only when the state actually changes. The safety timer runs at
    /// 10 Hz on the same run loop the event tap is attached to, and an IOKit
    /// round trip on every tick would be work in exactly the place
    /// `docs/design.md` says to keep clear.
    static func current() -> (pid: Int32?, liveness: SecureInputHolderLiveness) {
        guard let pid = holderPID() else { return (nil, .unknown) }
        return (pid, isRunning(pid) ? .alive : .gone)
    }

    private static func holderPID() -> Int32? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return nil }
        // The entry carries a send right that this process now owns. Leaking it
        // once per transition would be slow to matter and impossible to notice,
        // which is exactly why it is released here rather than left to chance.
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

    /// Whether a process with this identifier still exists.
    ///
    /// `EPERM` means it exists and belongs to somebody else, which still counts
    /// as running; only `ESRCH` proves it is gone.
    private static func isRunning(_ pid: Int32) -> Bool {
        guard kill(pid, 0) != 0 else { return true }
        return errno == EPERM
    }
}
