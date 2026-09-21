import Foundation

/// Only anonymous lesson aggregates can cross the practice/native boundary.
public struct PracticeProgress: Codable, Equatable {
    public struct Result: Codable, Equatable {
        public var completed: Int
        public var bestAccuracy: Int
    }
    public var schemaVersion: Int
    public var layoutVersion: String
    public var lessons: [String: Result]
    public static var empty: Self { Self(schemaVersion: 1, layoutVersion: WKRLayout.layoutVersion, lessons: [:]) }
    public static func validated(_ data: Data) -> Self? {
        guard data.count <= 16384,
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.schemaVersion == 1, value.layoutVersion == WKRLayout.layoutVersion,
              value.lessons.count <= PracticeMetadata.lessonIDs.count,
              value.lessons.allSatisfy({ id, result in
                  PracticeMetadata.lessonIDs.contains(id) && (1...1_000_000).contains(result.completed)
                      && (0...100).contains(result.bestAccuracy)
              }) else { return nil }
        return value
    }
}
