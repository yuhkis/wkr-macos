import Foundation

/// Why conversion is or is not running, in the form the menu bar shows it.
///
/// Deliberately payload-free. The AppKit side compares the previous value with
/// the new one and touches the status item only when they differ, and the
/// comparison runs on the 0.10 s safety timer that shares the main run loop
/// with the event tap source. A case carrying elapsed seconds would differ on
/// every tick and put AppKit work in exactly the place `docs/design.md` keeps
/// clear. Everything that changes continuously is read once, when the user
/// opens the menu.
public enum ConversionStatus: String, Sendable, CaseIterable {
    /// The gate is open and keys are being converted.
    case converting
    /// The current input source is not the one named at launch. The common,
    /// expected case: it happens on every 英数 press.
    case inputSourceMismatch = "input-source"
    /// An application named by `--exclude-app` is frontmost.
    case excludedApplication = "excluded-app"
    /// Some process in this login session holds Secure Event Input.
    case secureInput = "secure-input"
    /// The gate is shut with none of the reasons above set. Reachable while the
    /// tap is tearing itself down: `failClosed` clears its flags synchronously
    /// and only then hops to the main queue, so a timer tick can land in that
    /// window. Naming the state is better than inventing a reason for it.
    case stopping
}

/// What is known about the process holding Secure Event Input.
///
/// Sampled when the user opens the menu, never on the timer. The liveness in
/// particular goes stale within an episode: orphaning produces no falling edge,
/// so a value captured when the gate closed can still read `alive` an hour
/// after the holder exited — which is the exact case where the remedy differs.
public struct SecureInputDetail: Equatable, Sendable {
    public let holderPID: Int32?
    public let liveness: SecureInputHolderLiveness
    public let heldSeconds: Double?
    public let heldSinceLaunch: Bool

    public init(
        holderPID: Int32?,
        liveness: SecureInputHolderLiveness,
        heldSeconds: Double?,
        heldSinceLaunch: Bool
    ) {
        self.holderPID = holderPID
        self.liveness = liveness
        self.heldSeconds = heldSeconds
        self.heldSinceLaunch = heldSinceLaunch
    }
}

/// Everything the menu needs, gathered at the moment it opens.
public struct ConversionMenuContent: Equatable, Sendable {
    public let status: ConversionStatus
    /// The localized name of the current input source. Only `inputSourceMismatch`
    /// uses it.
    public let inputSourceName: String?
    /// Non-nil only when `status == .secureInput`.
    public let secureInput: SecureInputDetail?

    public init(
        status: ConversionStatus,
        inputSourceName: String? = nil,
        secureInput: SecureInputDetail? = nil
    ) {
        self.status = status
        self.inputSourceName = inputSourceName
        self.secureInput = secureInput
    }
}

extension ConversionStatus {
    /// Which reason to show when several conditions are false at once.
    ///
    /// The order is a display choice, not a safety one — the gate itself is
    /// `EventTapController.isConverting`, which this function never modifies and
    /// only reads through `gateOpen`.
    ///
    /// Secure Event Input comes first because it is the only cause the user
    /// neither chose nor can see, and it is the cause of every stoppage measured
    /// so far. The excluded application comes before the input source because it
    /// is the durable condition, and the one where converting would push romaji
    /// into a guest system.
    ///
    /// Testing the three reasons before `gateOpen` is equivalent rather than
    /// weaker: the caller has just handed the same three values to
    /// `applyContext`, so an open gate implies all three are clear. The tests
    /// pin that over the whole truth table.
    ///
    /// - Parameters:
    ///   - gateOpen: `EventTapController.isConverting`, passed through verbatim.
    ///   - statusMenuOpen: `true` while this app's own menu is tracking. The
    ///     menu shuts the gate so that converted romaji cannot land in the
    ///     menu's type-select, and this keeps the menu from explaining that
    ///     self-inflicted closure back to the user as a fault.
    public static func resolve(
        gateOpen: Bool,
        secureInputEnabled: Bool,
        applicationAllowed: Bool,
        inputSourceMatches: Bool,
        statusMenuOpen: Bool
    ) -> ConversionStatus {
        if secureInputEnabled { return .secureInput }
        if !applicationAllowed { return .excludedApplication }
        if !inputSourceMatches { return .inputSourceMismatch }
        if gateOpen { return .converting }
        if statusMenuOpen { return .converting }
        return .stopping
    }
}

/// Every user-facing string for the status display.
///
/// Kept here, in the target the tests can import, because the wording is the
/// feature. The difference between "wait" and "log out" is one line of text,
/// and getting it wrong once already cost an hour and a meeting.
///
/// Nothing here can emit a process name, a path, or a bundle identifier: the
/// only values substituted are a PID number and the input source name the OS
/// reports for the user's own current setting. A menu bar is read while the
/// screen is being shared and is the most screenshot-prone surface on the
/// machine, so it carries no more identity than the log does.
public enum ConversionStatusText {
    public static func statusTitle(_ status: ConversionStatus) -> String {
        switch status {
        case .converting: return "変換中"
        case .inputSourceMismatch: return "待機中：入力ソースが対象外"
        case .excludedApplication: return "待機中：除外アプリが前面"
        case .secureInput: return "停止中：Secure Event Input"
        case .stopping: return "停止中：原因不明"
        }
    }

    /// The SF Symbol drawn in the menu bar. States are told apart by shape, not
    /// colour. Every name here shipped well before the app's macOS 14 floor.
    public static func symbolName(_ status: ConversionStatus) -> String {
        switch status {
        case .converting: return "keyboard.fill"
        case .inputSourceMismatch: return "keyboard"
        case .excludedApplication: return "keyboard.macwindow"
        case .secureInput: return "lock.fill"
        case .stopping: return "questionmark.circle"
        }
    }

    /// Drawn as text when the symbol cannot be loaded. A status item with
    /// neither an image nor a title is invisible, which would remove the only
    /// surface this whole feature adds.
    public static func fallbackGlyph(_ status: ConversionStatus) -> String {
        switch status {
        case .converting: return "変"
        case .inputSourceMismatch: return "待"
        case .excludedApplication: return "外"
        case .secureInput: return "鍵"
        case .stopping: return "不"
        }
    }

    /// The lines between the title and the remedy. Empty for `converting`.
    public static func detailLines(_ content: ConversionMenuContent) -> [String] {
        switch content.status {
        case .converting, .stopping:
            return []
        case .excludedApplication:
            return []
        case .inputSourceMismatch:
            guard let name = content.inputSourceName else {
                return ["現在の入力ソース：取得できません"]
            }
            return ["現在の入力ソース：\(name)"]
        case .secureInput:
            guard let detail = content.secureInput else { return [] }
            return [holderLine(detail), elapsedLine(detail)]
        }
    }

    static func holderLine(_ detail: SecureInputDetail) -> String {
        guard let pid = detail.holderPID, detail.liveness != .unknown else {
            return "保持プロセス：特定できません"
        }
        switch detail.liveness {
        case .alive: return "保持プロセス：PID \(pid)（動作中）"
        case .gone: return "保持プロセス：PID \(pid)（終了済み）"
        case .unknown: return "保持プロセス：特定できません"
        }
    }

    /// Formats the elapsed time, keeping a lower bound distinguishable from a
    /// measurement. Under a minute it reports whole seconds, above it whole
    /// minutes: the difference that matters is 0.4 s versus an hour, not
    /// precision.
    static func elapsedLine(_ detail: SecureInputDetail) -> String {
        guard let seconds = detail.heldSeconds, seconds.isFinite, seconds >= 0 else {
            return "経過時間：計測できていません"
        }
        if detail.heldSinceLaunch {
            if seconds < 60 {
                return "経過時間：少なくとも\(Int(seconds))秒（起動時点で既に有効）"
            }
            return "経過時間：少なくとも約\(Int((seconds / 60).rounded()))分（起動時点で既に有効）"
        }
        if seconds < 1 { return "経過時間：1秒未満" }
        if seconds < 60 { return "経過時間：\(Int(seconds))秒" }
        return "経過時間：約\(Int((seconds / 60).rounded()))分"
    }

    /// What to do about it. `nil` while converting, because there is nothing to do.
    public static func remedyLine(_ content: ConversionMenuContent) -> String? {
        switch content.status {
        case .converting:
            return nil
        case .inputSourceMismatch:
            return "対処：入力ソースを Apple日本語入力の「ひらがな」に戻してください"
        case .excludedApplication:
            return "対処：不要です。--exclude-app の指定どおり素通ししています"
        case .stopping:
            return "対処：ログの conversion-stopped / event-tap-disabled 行を確認してください"
        case .secureInput:
            guard let detail = content.secureInput else {
                return "対処：ログの secure-event-input 行を確認してください"
            }
            switch detail.liveness {
            case .alive:
                guard let pid = detail.holderPID else {
                    return "対処：ログの secure-event-input 行を確認してください"
                }
                return "対処：解放を待つか、そのプロセスを終了してください（ps -p \(pid) -o comm= で確認できます）"
            case .gone:
                return "対処：ログアウトして再ログインしてください。他の操作では戻りません"
            case .unknown:
                return "対処：ログの secure-event-input 行を確認してください"
            }
        }
    }

    /// The one enabled item. Named so the consequence is visible before it is
    /// chosen: under the login agent, `KeepAlive` is false.
    public static let quitTitle = "終了（次のログインまで変換は止まります）"
}
