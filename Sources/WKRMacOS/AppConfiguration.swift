import Foundation
import WKRCore

enum AppConfigurationError: LocalizedError {
    case missingValue(String)
    case invalidMode(String)
    case missingInputSource
    case missingInputMode
    case optimisticAcknowledgementRequired
    case invalidEnglishFallback(String)
    case invalidSymbolLayer(String)
    case invalidKeyFrequency(String)
    case invalidKeyFrequencyRetention(String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(argument):
            return "missing value for \(argument)"
        case let .invalidMode(mode):
            return "unsupported output mode: \(mode)"
        case .missingInputSource:
            return "--input-source-id is required; run --print-input-source first"
        case .missingInputMode:
            return "--input-mode-id is required; run --print-input-source while Apple Japanese Hiragana is active"
        case .optimisticAcknowledgementRequired:
            return "optimistic mode requires --allow-unverified-optimistic"
        case let .invalidEnglishFallback(value):
            let supported = EnglishFallbackTrigger.allCases
                .map(\.rawValue)
                .joined(separator: ", ")
            return "unsupported english fallback trigger: \(value) (supported: \(supported))"
        case let .invalidSymbolLayer(value):
            return "unsupported symbol layer setting: \(value) (supported: on, off)"
        case let .invalidKeyFrequency(value):
            return "unsupported key frequency setting: \(value) (supported: on, off)"
        case let .invalidKeyFrequencyRetention(value):
            return "unsupported key frequency retention: \(value) (supported: all, or a positive number of days)"
        }
    }
}

/// What this launch is for.
///
/// Everything except `run` finishes without creating an event tap, so none of
/// them need an input source and none of them ask for permissions.
enum LaunchAction: Equatable {
    case run
    case printInputSource
    case keyFrequencyReport
    case keyFrequencyReset
}

struct AppConfiguration {
    let action: LaunchAction
    let inputSourceID: String?
    let inputModeID: String?
    let outputMode: OutputMode
    let outputModeName: String
    let requestPermissions: Bool
    /// Bundle identifiers that must never be converted, however the input
    /// source is set. Virtual machines and remote desktops forward keystrokes
    /// to a guest with its own input method, so rewriting them here produces
    /// garbage in the guest.
    let excludedApplications: Set<String>
    /// Which key pressed while `英数` is held replaces the connect-back with
    /// the letters the user actually typed. Set with `--english-fallback` or
    /// the `EnglishFallbackTrigger` user default; the flag wins.
    let englishFallbackTrigger: EnglishFallbackTrigger
    /// Whether the 59 `Y` symbol rules are in the table. They inject Unicode,
    /// which commits with no chance to convert and cannot be sent at all while
    /// a pre-edit is open, so turning them off is a supported choice. `Y` then
    /// passes through. Set with `--symbol-layer` or the `SymbolLayer` user
    /// default; the flag wins.
    let symbolLayerEnabled: Bool
    /// Whether per-key press counts are kept. Off unless asked for: this is the
    /// only feature that writes anything derived from keystrokes to disk, so it
    /// is opt-in rather than opt-out. What it may and may not hold is in
    /// `docs/design.md` section 9. Set with `--key-frequency` or the
    /// `KeyFrequencyLog` user default; the flag wins.
    let keyFrequencyEnabled: Bool
    /// How many days of counts to keep, or `nil` to keep every day.
    ///
    /// Nothing is dropped unless this is set: the counts are the point of
    /// turning the feature on, and the oldest of them are what answer whether a
    /// layout change moved the load. Set with `--key-frequency-retention` or the
    /// `KeyFrequencyRetentionDays` user default; the flag wins.
    let keyFrequencyRetainedDays: Int?
    /// Where the counts live. `nil` means the standard location under
    /// Application Support.
    let keyFrequencyStorePath: String?
    /// Where `--key-frequency-report` writes its HTML. `nil` means next to the
    /// store.
    let keyFrequencyReportPath: String?
    /// Open the report in the default browser once it is written.
    let openReport: Bool
    /// A Vial `.vil` export used to label the Cornix picture with the keymap
    /// actually flashed to the keyboard. Without it the built-in default is
    /// drawn. Set with `--vil` or the `VialKeymapPath` user default.
    let vialKeymapPath: String?

    /// User default that holds the trigger between launches. A settings window
    /// can write the same key once the menu bar item exists.
    static let englishFallbackDefaultsKey = "EnglishFallbackTrigger"
    static let symbolLayerDefaultsKey = "SymbolLayer"
    static let keyFrequencyDefaultsKey = "KeyFrequencyLog"
    static let keyFrequencyRetentionDefaultsKey = "KeyFrequencyRetentionDays"
    static let vialKeymapPathDefaultsKey = "VialKeymapPath"

    static func parse(
        arguments: [String],
        defaults: UserDefaults = .standard
    ) throws -> AppConfiguration {
        var action = LaunchAction.run
        var inputSourceID: String?
        var inputModeID: String?
        var modeName = "deferred"
        var requestPermissions = false
        var allowOptimistic = false
        var excludedApplications: Set<String> = []
        var englishFallbackName = defaults.string(forKey: englishFallbackDefaultsKey)
        var symbolLayerName = defaults.string(forKey: symbolLayerDefaultsKey)
        var keyFrequencyName = defaults.string(forKey: keyFrequencyDefaultsKey)
        var keyFrequencyRetentionName = defaults.string(forKey: keyFrequencyRetentionDefaultsKey)
        var keyFrequencyStorePath: String?
        var keyFrequencyReportPath: String?
        var openReport = false
        var vialKeymapPath = defaults.string(forKey: vialKeymapPathDefaultsKey)

        // `--flag=value` is split so it behaves like `--flag value`. Unknown
        // arguments are ignored on purpose: macOS injects its own (`-psn_…`,
        // `-NSDocumentRevisionsDebugMode`) into bundled apps started by launchd
        // or `open --args`, and rejecting those would turn an ordinary launch
        // into a silent startup failure.
        let tokens = arguments.dropFirst().flatMap { argument -> [String] in
            guard argument.hasPrefix("--"),
                  let separator = argument.firstIndex(of: "=")
            else {
                return [argument]
            }
            return [
                String(argument[..<separator]),
                String(argument[argument.index(after: separator)...]),
            ]
        }
        var index = 0

        while index < tokens.count {
            switch tokens[index] {
            case "--print-input-source":
                action = .printInputSource
            case "--key-frequency-report":
                action = .keyFrequencyReport
            case "--key-frequency-reset":
                action = .keyFrequencyReset
            case "--key-frequency":
                index += 1
                guard index < tokens.count else {
                    throw AppConfigurationError.missingValue("--key-frequency")
                }
                keyFrequencyName = tokens[index]
            case "--key-frequency-retention":
                index += 1
                guard index < tokens.count else {
                    throw AppConfigurationError.missingValue("--key-frequency-retention")
                }
                keyFrequencyRetentionName = tokens[index]
            case "--key-frequency-store":
                index += 1
                guard index < tokens.count else {
                    throw AppConfigurationError.missingValue("--key-frequency-store")
                }
                keyFrequencyStorePath = tokens[index]
            case "--key-frequency-report-output", "--output":
                index += 1
                guard index < tokens.count else {
                    throw AppConfigurationError.missingValue("--key-frequency-report-output")
                }
                keyFrequencyReportPath = tokens[index]
            case "--vil":
                index += 1
                guard index < tokens.count else {
                    throw AppConfigurationError.missingValue("--vil")
                }
                vialKeymapPath = tokens[index]
            case "--open":
                openReport = true
            case "--input-source-id":
                index += 1
                guard index < tokens.count else {
                    throw AppConfigurationError.missingValue("--input-source-id")
                }
                inputSourceID = tokens[index]
            case "--input-mode-id":
                index += 1
                guard index < tokens.count else {
                    throw AppConfigurationError.missingValue("--input-mode-id")
                }
                inputModeID = tokens[index]
            case "--mode":
                index += 1
                guard index < tokens.count else {
                    throw AppConfigurationError.missingValue("--mode")
                }
                modeName = tokens[index]
            case "--exclude-app":
                index += 1
                guard index < tokens.count else {
                    throw AppConfigurationError.missingValue("--exclude-app")
                }
                excludedApplications.insert(tokens[index])
            case "--english-fallback":
                index += 1
                guard index < tokens.count else {
                    throw AppConfigurationError.missingValue("--english-fallback")
                }
                englishFallbackName = tokens[index]
            case "--symbol-layer":
                index += 1
                guard index < tokens.count else {
                    throw AppConfigurationError.missingValue("--symbol-layer")
                }
                symbolLayerName = tokens[index]
            case "--request-permissions":
                requestPermissions = true
            case "--allow-unverified-optimistic":
                allowOptimistic = true
            default:
                break
            }
            index += 1
        }

        let outputMode: OutputMode
        switch modeName {
        case "deferred":
            outputMode = .deferredRomaji
        case "optimistic":
            guard allowOptimistic else {
                throw AppConfigurationError.optimisticAcknowledgementRequired
            }
            outputMode = .optimisticRomaji(.fullLayoutExperimental)
        case "prefix":
            outputMode = .prefixRomaji
        default:
            throw AppConfigurationError.invalidMode(modeName)
        }

        let englishFallbackTrigger: EnglishFallbackTrigger
        if let englishFallbackName {
            guard let trigger = EnglishFallbackTrigger(rawValue: englishFallbackName) else {
                throw AppConfigurationError.invalidEnglishFallback(englishFallbackName)
            }
            englishFallbackTrigger = trigger
        } else {
            englishFallbackTrigger = .default
        }

        let symbolLayerEnabled: Bool
        switch symbolLayerName {
        case nil, "on":
            symbolLayerEnabled = true
        case "off":
            symbolLayerEnabled = false
        case let other?:
            throw AppConfigurationError.invalidSymbolLayer(other)
        }

        let keyFrequencyEnabled: Bool
        switch keyFrequencyName {
        case nil, "off":
            keyFrequencyEnabled = false
        case "on":
            keyFrequencyEnabled = true
        case let other?:
            throw AppConfigurationError.invalidKeyFrequency(other)
        }

        let keyFrequencyRetainedDays: Int?
        switch keyFrequencyRetentionName {
        case nil, "all":
            keyFrequencyRetainedDays = nil
        case let other?:
            // Zero and negatives are rejected rather than read as "keep
            // nothing": a tally that throws itself away at every write is never
            // what someone meant to ask for, and `--key-frequency-reset` is the
            // command for clearing counts.
            guard let days = Int(other), days > 0 else {
                throw AppConfigurationError.invalidKeyFrequencyRetention(other)
            }
            keyFrequencyRetainedDays = days
        }

        if action == .run, inputSourceID == nil {
            throw AppConfigurationError.missingInputSource
        }
        if action == .run, inputModeID == nil {
            throw AppConfigurationError.missingInputMode
        }

        return AppConfiguration(
            action: action,
            inputSourceID: inputSourceID,
            inputModeID: inputModeID,
            outputMode: outputMode,
            outputModeName: modeName,
            requestPermissions: requestPermissions,
            excludedApplications: excludedApplications,
            englishFallbackTrigger: englishFallbackTrigger,
            symbolLayerEnabled: symbolLayerEnabled,
            keyFrequencyEnabled: keyFrequencyEnabled,
            keyFrequencyRetainedDays: keyFrequencyRetainedDays,
            keyFrequencyStorePath: keyFrequencyStorePath,
            keyFrequencyReportPath: keyFrequencyReportPath,
            openReport: openReport,
            vialKeymapPath: vialKeymapPath
        )
    }
}
