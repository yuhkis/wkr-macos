import Foundation
import WKRCore

public final class PracticeProgressStore {
    private static var storageIdentifier: String {
        let practice = "io.github.yuhkis.wkr-practice"
        return Bundle.main.bundleIdentifier == practice ? practice : "io.github.yuhkis.wkr-macos.public"
    }
    public let url: URL
    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.storageIdentifier, isDirectory: true).appendingPathComponent("practice-progress-v2.json")
    }
    public func load() throws -> PracticeProgress? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let value = PracticeProgress.validated(data) else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }
    public func save(_ value: PracticeProgress) throws {
        let data = try JSONEncoder().encode(value)
        guard PracticeProgress.validated(data) != nil else { throw CocoaError(.fileWriteUnknown) }
        // Preserve an unreadable existing file; explicit deletion is available.
        _ = try load()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let directory = url.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent(".practice-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: data); try handle.close() } catch { try? handle.close(); throw error }
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary, options: .usingNewMetadataOnly)
        } else { try FileManager.default.moveItem(at: temporary, to: url) }
    }
    public func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
