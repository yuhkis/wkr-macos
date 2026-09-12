import AppKit
import Foundation
import WKRCore

/// The `--key-frequency-report`, `--key-frequency-archive` and
/// `--key-frequency-reset` launches.
///
/// Both finish and exit without creating an event tap, so neither asks for
/// Input Monitoring or Accessibility. Reading counts the app already wrote is
/// not an input-monitoring operation, and requiring the permission for it would
/// mean the report could not be looked at on a machine where the permission had
/// been revoked.
enum KeyFrequencyReportCommand {
    /// Written next to the store, and named after it.
    ///
    /// Beside its source rather than in the user's documents because the report
    /// is derived data that can be regenerated at any time, and named after the
    /// file it was drawn from because more than one tally can exist: the live
    /// one and any number of archived ones. A fixed name would mean opening an
    /// archive silently replaced the report of the current tally — same path,
    /// atomic write, no warning. The live store keeps producing
    /// `key-frequency.html`, which is what it was called before.
    static func defaultReportURL(for storeURL: URL) -> URL {
        storeURL
            .deletingLastPathComponent()
            .appendingPathComponent(storeURL.deletingPathExtension().lastPathComponent + ".html")
    }

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

        // A missing file is not an error *for the default path*. It is what a
        // first run looks like, and the report still draws the keyboards so the
        // user can see what they would be getting. A path someone typed or
        // picked is a different matter: it asserts that a tally is there, and
        // answering an unreadable file with an empty picture looks like the
        // file was read and found empty.
        let store: KeyFrequencyStore
        if let loaded = KeyFrequencyRecorder.loadStore(at: storeURL) {
            store = loaded
        } else if configuration.keyFrequencyStorePath != nil {
            fputs(
                "key-frequency-report: could not read \(storeURL.lastPathComponent) as a tally\n",
                stderr
            )
            return EXIT_FAILURE
        } else {
            store = .empty
        }
        if store.days.isEmpty {
            fputs("key-frequency-report: no counts recorded yet (start with --key-frequency on)\n", stderr)
        }

        let geometries: [KeyboardGeometry] = [.jis, .us] + cornixGeometries(for: configuration)

        let html = KeyFrequencyReportRenderer.html(
            store: store,
            geometries: geometries,
            generatedAt: Date(),
            // The name only, never the path: the report is a single file meant
            // to be keepable and sendable, and the directory above it carries a
            // home directory, often a cloud folder, frequently an account name.
            // The same rule the menu bar follows.
            sourceFileName: storeURL.lastPathComponent
        )

        let outputURL: URL
        if let path = configuration.keyFrequencyReportPath {
            outputURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            outputURL = defaultReportURL(for: storeURL)
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

    /// Move the tally aside and start a new one, keeping every count.
    ///
    /// The app does this by itself when the rule table changes, which is the
    /// case that matters; this is the same thing on demand, for anyone who
    /// wants a clean picture from today without giving up the old one.
    static func runArchive(_ configuration: AppConfiguration) -> Int32 {
        guard let storeURL = storeURL(for: configuration) else {
            fputs("key-frequency-archive: could not locate Application Support\n", stderr)
            return EXIT_FAILURE
        }
        switch KeyFrequencyRecorder.rotate(
            storeURL: storeURL,
            layout: WKRLayout.layoutIdentifier,
            force: true
        ) {
        case let .rotated(fileName, days):
            let directory = KeyFrequencyRecorder.archiveDirectory(for: storeURL)
            print("key-frequency-archive: moved \(days) day(s) to \(directory.appendingPathComponent(fileName).path)")
            // The running app keeps its own counts since the last write and
            // will put them in a fresh file at its next flush, so an archive
            // taken while it is up starts the new tally two minutes late.
            print("key-frequency-archive: stop the app first (make stop) if it is running.")
            return EXIT_SUCCESS
        case .notNeeded:
            print("key-frequency-archive: nothing to archive at \(storeURL.path)")
            return EXIT_SUCCESS
        case .failed:
            fputs("key-frequency-archive: could not move the tally aside; it was left alone\n", stderr)
            return EXIT_FAILURE
        }
    }

    static func runReset(_ configuration: AppConfiguration) -> Int32 {
        guard let storeURL = storeURL(for: configuration) else {
            fputs("key-frequency-reset: could not locate Application Support\n", stderr)
            return EXIT_FAILURE
        }
        // An archive is the only copy there is of a layout's counts, and this
        // command deletes what it is pointed at. Refusing is not protecting the
        // user from themselves: `rm` is right there, and typing it is a
        // different act from running the command that clears today's tally.
        guard !KeyFrequencyRecorder.isArchived(storeURL) else {
            fputs(
                "key-frequency-reset: \(storeURL.lastPathComponent) is an archived tally; "
                    + "remove it yourself if that is what you mean\n",
                stderr
            )
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
