import Foundation

/// Whether the process that holds Secure Event Input still exists.
///
/// `gone` is the interesting one. The session-wide Secure Event Input count is
/// supposed to be reclaimed when a holder exits, but it is not always: on
/// 2026-09-02 the count outlived its holder and only a logout cleared it. That
/// case looks identical to `alive` from the key state alone, and the two need
/// completely different responses, so the log has to tell them apart.
public enum SecureInputHolderLiveness: String, Sendable, CaseIterable {
    /// The holder is running. Quitting it, or closing its password field,
    /// releases the count.
    case alive
    /// The holder has exited but the count is still held. Nothing short of
    /// ending the login session reclaims it.
    case gone
    /// No holder could be read. Absence of the key means "holder unknown", not
    /// "Secure Event Input is off" — `IsSecureEventInputEnabled()` is the only
    /// authority on the state itself.
    case unknown
}

/// Builds the trailing fields of the `secure-event-input` log lines.
///
/// Kept here, apart from the IOKit query, so the wording is covered by tests:
/// this text is what a later investigation has to read, and it has already been
/// wrong once. Only numbers and fixed keywords are ever produced, so the result
/// is safe to log as public — see `docs/design.md`「6. macOS側コンポーネント」.
public enum SecureInputLogFields {
    /// Fields appended to `secure-event-input enabled=true`.
    ///
    /// The PID is emitted bare, without resolving it to a process name. The
    /// name would say which other applications are running, and these logs are
    /// collected into sysdiagnose archives; a bare number is enough to look the
    /// holder up on the spot with `ps`, and says nothing after the fact.
    public static func enabledFields(
        holderPID: Int32?,
        liveness: SecureInputHolderLiveness
    ) -> String {
        guard let holderPID, liveness != .unknown else {
            return " holder=unknown"
        }
        return " holder-pid=\(holderPID) holder=\(liveness.rawValue)"
    }

    /// Fields appended to `secure-event-input enabled=false`.
    ///
    /// - Parameters:
    ///   - heldSeconds: How long the gate was closed, or `nil` when the process
    ///     never saw the matching rising edge.
    ///   - sinceLaunch: `true` when Secure Event Input was already enabled at
    ///     the first observation, which makes the duration a lower bound rather
    ///     than a measurement.
    public static func disabledFields(
        heldSeconds: Double?,
        sinceLaunch: Bool
    ) -> String {
        guard let heldSeconds else { return "" }
        let rounded = (heldSeconds * 10).rounded() / 10
        guard sinceLaunch else { return " held-seconds=\(rounded)" }
        return " held-seconds=\(rounded) since=launch"
    }
}
