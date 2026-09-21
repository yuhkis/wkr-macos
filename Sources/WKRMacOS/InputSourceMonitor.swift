import Carbon.HIToolbox
import Foundation

struct InputSourceSnapshot: Equatable {
    let sourceID: String
    let modeID: String?
    let localizedName: String?

    static func current() -> InputSourceSnapshot? {
        guard let unmanaged = TISCopyCurrentKeyboardInputSource() else { return nil }
        let source = unmanaged.takeRetainedValue()
        guard let sourceID = stringProperty(source, key: kTISPropertyInputSourceID) else {
            return nil
        }
        return InputSourceSnapshot(
            sourceID: sourceID,
            modeID: stringProperty(source, key: kTISPropertyInputModeID),
            localizedName: stringProperty(source, key: kTISPropertyLocalizedName)
        )
    }

    private static func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}

final class InputSourceMonitor {
    typealias ChangeHandler = (InputSourceSnapshot?) -> Void

    private let handler: ChangeHandler
    private var observer: NSObjectProtocol?

    init(handler: @escaping ChangeHandler) {
        self.handler = handler
    }

    func start() {
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handler(InputSourceSnapshot.current())
        }
        handler(InputSourceSnapshot.current())
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }
}
