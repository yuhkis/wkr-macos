import AppKit
import Foundation
import WKRCore

enum KeyFrequencyReportCommand {
    static let defaultReportFileName = "key-frequency.html"

    static func storeURL(for configuration: AppConfiguration) -> URL? {
        if let path = configuration.keyFrequencyStorePath {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return KeyFrequencyRecorder.defaultStoreURL()
    }

    static func runReport(_ configuration: AppConfiguration) -> Int32 {
        guard let storeURL = storeURL(for: configuration) else {
            fputs("key-frequency-report: could not locate Application Support\n", stderr)
            return EXIT_FAILURE
        }

        let store = KeyFrequencyRecorder.loadStore(at: storeURL) ?? .empty
        if store.days.isEmpty {
            fputs("key-frequency-report: no counts recorded yet (start with --key-frequency on)\n", stderr)
        }

        let geometries: [KeyboardGeometry] = [.jis, .us] + cornixGeometries(for: configuration)

        let html = KeyFrequencyReportRenderer.html(
            store: store,
            geometries: geometries,
            generatedAt: Date()
        )

        let outputURL: URL
        if let path = configuration.keyFrequencyReportPath {
            outputURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            outputURL = storeURL
                .deletingLastPathComponent()
                .appendingPathComponent(defaultReportFileName)
        }

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(html.utf8).write(to: outputURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: outputURL.path
            )
        } catch {
            fputs("key-frequency-report: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }

        print(outputURL.path)
        if configuration.openReport {
            NSWorkspace.shared.open(outputURL)
        }
        return EXIT_SUCCESS
    }

    static func runReset(_ configuration: AppConfiguration) -> Int32 {
        guard let storeURL = storeURL(for: configuration) else {
            fputs("key-frequency-reset: could not locate Application Support\n", stderr)
            return EXIT_FAILURE
        }
        let existed = FileManager.default.fileExists(atPath: storeURL.path)
        do {
            try KeyFrequencyRecorder.resetStore(at: storeURL)
        } catch {
            fputs("key-frequency-reset: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
        if existed {
            print("key-frequency-reset: removed \(storeURL.path)")
            print("key-frequency-reset: stop the app first (make stop) if it is running.")
        } else {
            print("key-frequency-reset: nothing recorded at \(storeURL.path)")
        }
        return EXIT_SUCCESS
    }

    private static func cornixGeometries(for configuration: AppConfiguration) -> [KeyboardGeometry] {
        guard let path = configuration.vialKeymapPath else { return [.cornix] }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            let keymap = try VialKeymap.parse(data: try Data(contentsOf: url))
            return KeyboardGeometry.cornixLayers(keymap: keymap)
        } catch {
            fputs(
                "key-frequency-report: could not read \(url.lastPathComponent) "
                    + "(\(error.localizedDescription)); using the built-in Cornix layout\n",
                stderr
            )
            return [.cornix]
        }
    }
}
