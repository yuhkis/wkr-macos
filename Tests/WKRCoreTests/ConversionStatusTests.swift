import XCTest
@testable import WKRCore

final class ConversionStatusTests: XCTestCase {
    /// Every combination of the five inputs `resolve` takes.
    private static let allRows: [(gate: Bool, secure: Bool, allowed: Bool, matches: Bool, menu: Bool)] = {
        var rows: [(Bool, Bool, Bool, Bool, Bool)] = []
        for gate in [false, true] {
            for secure in [false, true] {
                for allowed in [false, true] {
                    for matches in [false, true] {
                        for menu in [false, true] {
                            rows.append((gate, secure, allowed, matches, menu))
                        }
                    }
                }
            }
        }
        return rows
    }()

    private func resolve(
        _ row: (gate: Bool, secure: Bool, allowed: Bool, matches: Bool, menu: Bool)
    ) -> ConversionStatus {
        ConversionStatus.resolve(
            gateOpen: row.gate,
            secureInputEnabled: row.secure,
            applicationAllowed: row.allowed,
            inputSourceMatches: row.matches,
            statusMenuOpen: row.menu
        )
    }

    // MARK: - The safety assertion

    /// The display must never claim conversion is running where the gate would
    /// refuse. `converting` is reachable only with all three reasons clear and
    /// either the gate open or this app's own menu holding it shut.
    func testConvertingRequiresAClearGateOrOurOwnMenu() {
        for row in Self.allRows {
            let reasonsClear = !row.secure && row.allowed && row.matches
            let expected = reasonsClear && (row.gate || row.menu)
            XCTAssertEqual(
                resolve(row) == .converting,
                expected,
                "row \(row)"
            )
        }
    }

    /// Any single reason is enough to stop claiming conversion, whatever the
    /// gate or the menu say.
    func testEveryReasonSuppressesConverting() {
        for row in Self.allRows where row.secure || !row.allowed || !row.matches {
            XCTAssertNotEqual(resolve(row), .converting, "row \(row)")
        }
    }

    /// `stopping` is exactly the unattributed closed gate — the `failClosed`
    /// window where the tap has dropped its flags but the fatal handler has not
    /// run yet.
    func testStoppingIsExactlyTheUnattributedClosedGate() {
        for row in Self.allRows {
            let unattributed = !row.gate && !row.menu && !row.secure && row.allowed && row.matches
            XCTAssertEqual(resolve(row) == .stopping, unattributed, "row \(row)")
        }
    }

    /// While our own menu is open the gate is shut on purpose. The menu must not
    /// report that self-inflicted closure back as a fault.
    func testOpenMenuAloneReportsConverting() {
        XCTAssertEqual(
            ConversionStatus.resolve(
                gateOpen: false,
                secureInputEnabled: false,
                applicationAllowed: true,
                inputSourceMatches: true,
                statusMenuOpen: true
            ),
            .converting
        )
    }

    // MARK: - Precedence

    func testPrecedenceIsPinned() {
        func r(secure: Bool, allowed: Bool, matches: Bool) -> ConversionStatus {
            ConversionStatus.resolve(
                gateOpen: false,
                secureInputEnabled: secure,
                applicationAllowed: allowed,
                inputSourceMatches: matches,
                statusMenuOpen: false
            )
        }
        XCTAssertEqual(r(secure: true, allowed: false, matches: true), .secureInput)
        XCTAssertEqual(r(secure: true, allowed: true, matches: false), .secureInput)
        XCTAssertEqual(r(secure: false, allowed: false, matches: false), .excludedApplication)
        XCTAssertEqual(r(secure: true, allowed: false, matches: false), .secureInput)
    }

    // MARK: - Chrome

    /// A status item with neither an image nor a title is invisible, which would
    /// delete the only surface this feature adds.
    func testEveryStatusHasRenderableChrome() {
        for status in ConversionStatus.allCases {
            XCTAssertFalse(ConversionStatusText.statusTitle(status).isEmpty, "\(status)")
            XCTAssertFalse(ConversionStatusText.symbolName(status).isEmpty, "\(status)")
            let glyph = ConversionStatusText.fallbackGlyph(status)
            XCTAssertEqual(glyph.count, 1, "fallback glyph for \(status) must be one character")
        }
    }

    // MARK: - Holder wording

    func testHolderLineWordingIsPinned() {
        func line(_ liveness: SecureInputHolderLiveness, pid: Int32? = 4321) -> String {
            ConversionStatusText.holderLine(
                SecureInputDetail(
                    holderPID: pid,
                    liveness: liveness,
                    heldSeconds: 1,
                    heldSinceLaunch: false
                )
            )
        }
        XCTAssertEqual(line(.alive), "保持プロセス：PID 4321（動作中）")
        XCTAssertEqual(line(.gone), "保持プロセス：PID 4321（終了済み）")
        XCTAssertEqual(line(.unknown), "保持プロセス：特定できません")
        // An unclassifiable PID is worth no more than none: showing the number
        // beside "特定できません" would invite acting on it.
        XCTAssertFalse(line(.unknown).contains("4321"))
        XCTAssertEqual(line(.alive, pid: nil), "保持プロセス：特定できません")
    }

    /// The branch that cost an hour and a meeting on 2026-09-03. Pinning it is
    /// the reason this wording lives in a testable target.
    func testGoneRemedyIsLogoutAndAliveIsNot() {
        func remedy(_ liveness: SecureInputHolderLiveness) -> String? {
            ConversionStatusText.remedyLine(
                ConversionMenuContent(
                    status: .secureInput,
                    secureInput: SecureInputDetail(
                        holderPID: 4321,
                        liveness: liveness,
                        heldSeconds: 10,
                        heldSinceLaunch: false
                    )
                )
            )
        }
        XCTAssertEqual(
            remedy(.gone),
            "対処：ログアウトして再ログインしてください。他の操作では戻りません"
        )
        XCTAssertNotEqual(remedy(.alive), remedy(.gone))
        XCTAssertEqual(
            remedy(.alive),
            "対処：解放を待つか、そのプロセスを終了してください（ps -p 4321 -o comm= で確認できます）"
        )
    }

    // MARK: - Elapsed time

    func testElapsedFormattingBoundaries() {
        func line(_ seconds: Double?, sinceLaunch: Bool = false) -> String {
            ConversionStatusText.elapsedLine(
                SecureInputDetail(
                    holderPID: 1,
                    liveness: .alive,
                    heldSeconds: seconds,
                    heldSinceLaunch: sinceLaunch
                )
            )
        }
        XCTAssertEqual(line(nil), "経過時間：計測できていません")
        XCTAssertEqual(line(0.4), "経過時間：1秒未満")
        XCTAssertEqual(line(12.0), "経過時間：12秒")
        XCTAssertEqual(line(59.9), "経過時間：59秒")
        XCTAssertEqual(line(60.0), "経過時間：約1分")
        XCTAssertEqual(line(3642.2), "経過時間：約61分")

        // A lower bound must never be presented as a measurement.
        XCTAssertEqual(line(12.0, sinceLaunch: true), "経過時間：少なくとも12秒（起動時点で既に有効）")
        XCTAssertEqual(line(3642.2, sinceLaunch: true), "経過時間：少なくとも約61分（起動時点で既に有効）")
        XCTAssertTrue(line(60.0, sinceLaunch: true).contains("少なくとも"))
    }

    func testElapsedRejectsNonsenseValues() {
        func line(_ seconds: Double) -> String {
            ConversionStatusText.elapsedLine(
                SecureInputDetail(
                    holderPID: 1,
                    liveness: .alive,
                    heldSeconds: seconds,
                    heldSinceLaunch: false
                )
            )
        }
        XCTAssertEqual(line(-1), "経過時間：計測できていません")
        XCTAssertEqual(line(.infinity), "経過時間：計測できていません")
        XCTAssertEqual(line(.nan), "経過時間：計測できていません")
    }

    // MARK: - Input source

    func testInputSourceNameFallsBackWhenAbsent() {
        XCTAssertEqual(
            ConversionStatusText.detailLines(
                ConversionMenuContent(status: .inputSourceMismatch, inputSourceName: "英字")
            ),
            ["現在の入力ソース：英字"]
        )
        XCTAssertEqual(
            ConversionStatusText.detailLines(
                ConversionMenuContent(status: .inputSourceMismatch, inputSourceName: nil)
            ),
            ["現在の入力ソース：取得できません"]
        )
    }

    // MARK: - Privacy

    /// No produced line may carry anything but a PID number and the input source
    /// name the OS reports for the user's own setting. A baked-in process name,
    /// path, or bundle identifier would fail this.
    func testNoProducedLineCanCarryAnIdentity() {
        var produced: [String] = []
        for status in ConversionStatus.allCases {
            produced.append(ConversionStatusText.statusTitle(status))
            for liveness in SecureInputHolderLiveness.allCases {
                for pid in [Int32(1), Int32(81937)] as [Int32?] + [nil] {
                    let content = ConversionMenuContent(
                        status: status,
                        inputSourceName: "ひらがな",
                        secureInput: SecureInputDetail(
                            holderPID: pid,
                            liveness: liveness,
                            heldSeconds: 12,
                            heldSinceLaunch: false
                        )
                    )
                    produced.append(contentsOf: ConversionStatusText.detailLines(content))
                    if let remedy = ConversionStatusText.remedyLine(content) {
                        produced.append(remedy)
                    }
                }
            }
        }
        let templates: Set<String> = [
            "変換中",
            "待機中：入力ソースが対象外",
            "待機中：除外アプリが前面",
            "停止中：Secure Event Input",
            "停止中：原因不明",
            "現在の入力ソース：ひらがな",
            "現在の入力ソース：取得できません",
            "保持プロセス：PID 1（動作中）",
            "保持プロセス：PID 1（終了済み）",
            "保持プロセス：PID 81937（動作中）",
            "保持プロセス：PID 81937（終了済み）",
            "保持プロセス：特定できません",
            "経過時間：12秒",
            "対処：入力ソースを Apple日本語入力の「ひらがな」に戻してください",
            "対処：不要です。--exclude-app の指定どおり素通ししています",
            "対処：ログの conversion-stopped / event-tap-disabled 行を確認してください",
            "対処：ログの secure-event-input 行を確認してください",
            "対処：ログアウトして再ログインしてください。他の操作では戻りません",
            "対処：解放を待つか、そのプロセスを終了してください（ps -p 1 -o comm= で確認できます）",
            "対処：解放を待つか、そのプロセスを終了してください（ps -p 81937 -o comm= で確認できます）",
        ]
        for line in produced {
            XCTAssertTrue(templates.contains(line), "unexpected line: \(line)")
        }
    }

    /// Every enabled menu title starts with a non-ASCII character, so a physical
    /// keystroke reaching the menu's type-select cannot match it.
    func testEnabledTitlesCannotBeReachedByTypeSelect() {
        for title in [ConversionStatusText.quitTitle, ConversionStatusText.openHeatmapTitle] {
            let first = title.unicodeScalars.first
            XCTAssertNotNil(first, title)
            XCTAssertFalse(first!.isASCII, title)
        }
    }

    /// The heatmap entry is offered unconditionally. Counting being off today
    /// says nothing about whether counts exist from before, so gating the entry
    /// on the current setting would hide that history.
    func testHeatmapTitleIsUnconditionalAndNonEmpty() {
        XCTAssertFalse(ConversionStatusText.openHeatmapTitle.isEmpty)
        XCTAssertNotEqual(ConversionStatusText.openHeatmapTitle, ConversionStatusText.quitTitle)
    }
}
