import AppKit
import Foundation
import WKRCore

/// The `--key-frequency-report` and `--key-frequency-reset` launches.
///
/// Both finish and exit without creating an event tap, so neither asks for
/// Input Monitoring or Accessibility. Reading counts the app already wrote is
/// not an input-monitoring operation, and requiring the permission for it would
/// mean the report could not be looked at on a machine where the permission had
/// been revoked.
enum KeyFrequencyReportCommand {
    /// Written next to the store rather than somewhere in the user's documents.
    /// The report is derived data that can be regenerated at any time, so it
    /// belongs beside its source instead of in a place that gets backed up and
    /// synced.
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

        // A missing file is not an error. It is what a first run looks like,
        // and the report still draws the three keyboards so the user can see
        // what they would be getting.
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
            // The counts say something about how their owner types, and so does
            // anything derived from them. The report inherits the store's
            // permissions rather than the umask's.
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
        // Checked before the delete so the message says what actually happened.
        // "removed" printed over a file that was never there reads as a
        // confirmation that counts have been cleared, which is a claim this
        // command would not have been in a position to make.
        let existed = FileManager.default.fileExists(atPath: storeURL.path)
        do {
            try KeyFrequencyRecorder.resetStore(at: storeURL)
        } catch {
            fputs("key-frequency-reset: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
        if existed {
            print("key-frequency-reset: removed \(storeURL.path)")
            // A recorder running in another process still holds its own counts
            // and writes them at its next flush, so a reset while the app is up
            // comes back within two minutes.
            print("key-frequency-reset: stop the app first (make stop) if it is running.")
        } else {
            print("key-frequency-reset: nothing recorded at \(storeURL.path)")
        }
        return EXIT_SUCCESS
    }

    /// The Corne picture, labelled from the Vial export the user supplied when
    /// one was given.
    ///
    /// A `.vil` that cannot be read falls back to the built-in layout with a
    /// line on stderr rather than failing the whole report. The keymap only
    /// decides what is printed on the caps; the counts underneath are the same
    /// either way, so a wrong or missing keymap must not cost the user their
    /// report.
    private static func cornixGeometries(for configuration: AppConfiguration) -> [KeyboardGeometry] {
        guard let path = configuration.vialKeymapPath else { return [.cornix] }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            let keymap = try VialKeymap.parse(data: try Data(contentsOf: url))
            // One tab per layer that has anything countable on it. Only the
            // keymap path gets layers: the built-in default is one generic
            // layer and has nothing to put on more tabs.
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
