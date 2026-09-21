import Foundation

public enum SecureInputHolderLiveness: String, Sendable, CaseIterable {
    case alive
    case gone
    case unknown
}

public enum SecureInputLogFields {
    public static func enabledFields(
        holderPID: Int32?,
        liveness: SecureInputHolderLiveness
    ) -> String {
        guard let holderPID, liveness != .unknown else {
            return " holder=unknown"
        }
        return " holder-pid=\(holderPID) holder=\(liveness.rawValue)"
    }

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
