import Foundation
import WKRCore

enum AppConfigurationError: LocalizedError {
    case missingValue(String)
    case invalidMode(String)
    case missingInputSource
    case missingInputMode
    case optimisticAcknowledgementRequired

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
        }
    }
}

struct AppConfiguration {
    let printInputSourceOnly: Bool
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

    static func parse(arguments: [String]) throws -> AppConfiguration {
        var printInputSourceOnly = false
        var inputSourceID: String?
        var inputModeID: String?
        var modeName = "deferred"
        var requestPermissions = false
        var allowOptimistic = false
        var excludedApplications: Set<String> = []

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
                printInputSourceOnly = true
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

        if !printInputSourceOnly, inputSourceID == nil {
            throw AppConfigurationError.missingInputSource
        }
        if !printInputSourceOnly, inputModeID == nil {
            throw AppConfigurationError.missingInputMode
        }

        return AppConfiguration(
            printInputSourceOnly: printInputSourceOnly,
            inputSourceID: inputSourceID,
            inputModeID: inputModeID,
            outputMode: outputMode,
            outputModeName: modeName,
            requestPermissions: requestPermissions,
            excludedApplications: excludedApplications
        )
    }
}
