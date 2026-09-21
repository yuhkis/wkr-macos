import Foundation

public enum ConversionStatus: String, Sendable, CaseIterable {
    case converting
    case inputSourceMismatch = "input-source"
    case excludedApplication = "excluded-app"
    case secureInput = "secure-input"
    case stopping
}

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

public struct ConversionMenuContent: Equatable, Sendable {
    public let status: ConversionStatus
    public let inputSourceName: String?
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

    public static func symbolName(_ status: ConversionStatus) -> String {
        switch status {
        case .converting: return "keyboard.fill"
        case .inputSourceMismatch: return "keyboard"
        case .excludedApplication: return "keyboard.macwindow"
        case .secureInput: return "lock.fill"
        case .stopping: return "questionmark.circle"
        }
    }

    public static func fallbackGlyph(_ status: ConversionStatus) -> String {
        switch status {
        case .converting: return "変"
        case .inputSourceMismatch: return "待"
        case .excludedApplication: return "外"
        case .secureInput: return "鍵"
        case .stopping: return "不"
        }
    }

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

    public static let openHeatmapTitle = "打鍵頻度のヒートマップを開く"

    public static func keymapLine(fileName: String?) -> String {
        guard let fileName, !fileName.isEmpty else {
            return "キーマップ：組み込みの配列"
        }
        return "キーマップ：\(fileName)"
    }

    public static let chooseKeymapTitle = "キーマップを選ぶ…"

    public static let clearKeymapTitle = "キーマップの指定を解除"

    public static let quitTitle = "終了（次のログインまで変換は止まります）"
}
