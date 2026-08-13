import Foundation
import OSLog

enum AppLog {
    static let logger = Logger(
        subsystem: "io.github.yuhkis.wkr-macos",
        category: "conversion"
    )
}

final class EventCounters {
    private(set) var transformedKeyDowns = 0
    private(set) var bypassedKeyDowns = 0
    private(set) var resets = 0
    private(set) var syntheticActions = 0

    func transformed(actions: Int) {
        transformedKeyDowns += 1
        syntheticActions += actions
    }

    func bypassed() {
        bypassedKeyDowns += 1
    }

    func reset() {
        resets += 1
    }

    func logSummary() {
        AppLog.logger.notice("summary transformed=\(self.transformedKeyDowns, privacy: .public) bypassed=\(self.bypassedKeyDowns, privacy: .public) resets=\(self.resets, privacy: .public) synthetic-actions=\(self.syntheticActions, privacy: .public)")
    }
}
