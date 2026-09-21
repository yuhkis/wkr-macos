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
    /// Two call sites are permitted: a Secure Event Input state transition, and
    /// the user opening the status menu. Never the 0.10 s safety timer or any
    /// paint path — that timer shares the main run loop with the event tap
    /// source, and an IOKit round trip per tick is work in exactly the place
    /// `docs/design.md`「7. 採否の記録」says to keep clear.
    ///
    /// The menu re-queries rather than reusing the value captured at the rising
    /// edge, because liveness goes stale inside an episode: an orphaned count
    /// produces no falling edge, so a holder that exited an hour ago still reads
    /// `alive` from the cached value. That is the one case where the remedy
    /// differs, so the menu pays for a fresh query each time it opens.
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
