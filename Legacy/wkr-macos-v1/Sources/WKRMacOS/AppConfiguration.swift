import Foundation
import WKRCore

enum AppConfigurationError: LocalizedError {
    case unsupportedOption
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
        case .unsupportedOption: return "unsupported option for the v1 archive"
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

enum LaunchAction: Equatable {
    case run
    case version
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
    let excludedApplications: Set<String>
    let englishFallbackTrigger: EnglishFallbackTrigger
    let symbolLayerEnabled: Bool
    let keyFrequencyEnabled: Bool
    let keyFrequencyRetainedDays: Int?
    let keyFrequencyStorePath: String?
    let keyFrequencyReportPath: String?
    let openReport: Bool
    let vialKeymapPath: String?

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
            case "--version":
                action = .version
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
                if tokens[index].hasPrefix("--") { throw AppConfigurationError.unsupportedOption }
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
