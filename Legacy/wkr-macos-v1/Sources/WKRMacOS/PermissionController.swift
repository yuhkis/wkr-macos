import CoreGraphics

struct EventPermissionState: Equatable {
    let listen: Bool
    let post: Bool

    var isGranted: Bool { listen && post }
}

enum PermissionController {
    static func current() -> EventPermissionState {
        EventPermissionState(
            listen: CGPreflightListenEventAccess(),
            post: CGPreflightPostEventAccess()
        )
    }

    static func check(requestIfNeeded: Bool) -> EventPermissionState {
        var state = current()
        guard requestIfNeeded, !state.isGranted else { return state }

        if !state.listen {
            _ = CGRequestListenEventAccess()
        }
        if !state.post {
            _ = CGRequestPostEventAccess()
        }
        state = current()
        return state
    }
}
