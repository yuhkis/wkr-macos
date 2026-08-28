import XCTest
@testable import WKRCore

final class KeyboardGeometryTests: XCTestCase {
    private var geometries: [KeyboardGeometry] { KeyboardGeometry.allBuiltIn }

    func testEveryModelHasABuiltInGeometry() {
        XCTAssertEqual(geometries.count, KeyboardModel.allCases.count)
        for model in KeyboardModel.allCases {
            XCTAssertFalse(
                KeyboardGeometry.builtIn(model).caps.isEmpty,
                "\(model.rawValue) has no keys to draw"
            )
        }
    }

    /// Cap ids address a cap in the rendered page, so a duplicate would make
    /// two keys share a highlight and a tooltip.
    func testCapIDsAreUniqueWithinEachGeometry() {
        for geometry in geometries {
            var seen: Set<String> = []
            for cap in geometry.caps {
                XCTAssertTrue(
                    seen.insert(cap.id).inserted,
                    "\(geometry.model.rawValue) repeats cap id \(cap.id)"
                )
            }
        }
    }

    /// The renderer sizes its viewBox from these two numbers, so a cap outside
    /// them is drawn off the edge of the picture.
    func testEveryCapFitsInsideTheDeclaredExtent() {
        for geometry in geometries {
            for cap in geometry.caps {
                XCTAssertGreaterThanOrEqual(cap.x, -0.001, "\(geometry.model.rawValue) \(cap.id)")
                XCTAssertGreaterThanOrEqual(cap.y, -0.001, "\(geometry.model.rawValue) \(cap.id)")
                XCTAssertLessThanOrEqual(
                    cap.x + cap.width,
                    geometry.widthUnits + 0.001,
                    "\(geometry.model.rawValue) \(cap.id) runs past widthUnits"
                )
                XCTAssertLessThanOrEqual(
                    cap.y + cap.height,
                    geometry.heightUnits + 0.001,
                    "\(geometry.model.rawValue) \(cap.id) runs past heightUnits"
                )
                XCTAssertGreaterThan(cap.width, 0, "\(geometry.model.rawValue) \(cap.id)")
                XCTAssertGreaterThan(cap.height, 0, "\(geometry.model.rawValue) \(cap.id)")
            }
        }
    }

    func testEveryCapIsLabelled() {
        for geometry in geometries {
            for cap in geometry.caps {
                // A blank primary is allowed only for a cap that carries no
                // identity, such as the lower half of the JIS Return key.
                if cap.legend.primary.isEmpty {
                    XCTAssertTrue(
                        cap.identities.isEmpty,
                        "\(geometry.model.rawValue) \(cap.id) is countable but unlabelled"
                    )
                }
            }
        }
    }

    /// A cold cap already means "not pressed in this period". A cap macOS
    /// cannot see has to say so instead, or the picture reads as a measurement
    /// when it is a blind spot.
    func testUncountableCapsDeclareWhy() {
        for geometry in geometries {
            for cap in geometry.caps where cap.identities.isEmpty {
                if cap.legend.primary.isEmpty { continue }
                XCTAssertNotNil(
                    cap.exclusion,
                    "\(geometry.model.rawValue) \(cap.id) carries no count and no reason"
                )
            }
        }
    }

    /// The per-finger table answers "how much is this finger striking", so a
    /// modifier — held, not struck — must stay out of it. All three boards have
    /// to agree or the tabs cannot be read against each other.
    func testNoGeometryFilesAModifierUnderAFinger() {
        for geometry in geometries {
            for cap in geometry.caps where cap.exclusion == .modifier {
                XCTAssertNil(
                    cap.finger,
                    "\(geometry.model.rawValue) \(cap.id) puts a held modifier in the finger table"
                )
            }
        }
    }

    /// Every countable key that is not a modifier has to claim both shift
    /// states, because the recorder files the shift flag for all of them. A cap
    /// claiming only one would record half its presses and draw none of them.
    func testCountableNonModifierCapsClaimBothShiftStates() {
        for geometry in [KeyboardGeometry.jis, .us] {
            for cap in geometry.caps
            where !cap.identities.isEmpty && cap.exclusion != .modifier {
                let codes = Set(cap.identities.map(\.keyCode))
                for code in codes {
                    XCTAssertTrue(
                        cap.identities.contains(KeyIdentity(keyCode: code, isShifted: false))
                            && cap.identities.contains(KeyIdentity(keyCode: code, isShifted: true)),
                        "\(geometry.model.rawValue) \(cap.id) claims only one shift state"
                    )
                }
            }
        }
    }

    /// A key countable on one tab and uncountable on the next is a contradiction
    /// the reader has no way to resolve.
    func testFunctionKeysAgreeAcrossTheStaggeredBoards() {
        func functionCaps(_ geometry: KeyboardGeometry) -> [KeyCap] {
            geometry.caps.filter { $0.exclusion == .media }
        }
        let jis = functionCaps(.jis)
        let us = functionCaps(.us)
        XCTAssertEqual(jis.count, us.count)
        XCTAssertEqual(
            Set(jis.flatMap(\.identities).map(\.keyCode)),
            Set(us.flatMap(\.identities).map(\.keyCode))
        )
        XCTAssertFalse(jis.isEmpty)
    }

    func testEveryGeometryStatesItsBlindSpots() {
        for geometry in geometries {
            XCTAssertFalse(
                geometry.caveats.isEmpty,
                "\(geometry.model.rawValue) claims to have nothing it cannot see"
            )
        }
    }

    /// This project's whole conversion gate turns on these two keys, so they
    /// have to be present and countable wherever the keyboard has them.
    func testJISAndCornixBothCarryEisuAndKana() {
        let eisu = KeyIdentity(keyCode: 0x66)
        let kana = KeyIdentity(keyCode: 0x68)
        for geometry in [KeyboardGeometry.jis, .cornix] {
            let identities = Set(geometry.caps.flatMap(\.identities))
            XCTAssertTrue(identities.contains(eisu), "\(geometry.model.rawValue) has no 英数")
            XCTAssertTrue(identities.contains(kana), "\(geometry.model.rawValue) has no かな")
        }
    }

    /// Apple prints caps lock left of A and control at the bottom left. Drawing
    /// a common remap instead would put caps where the reader's fingers never
    /// found it.
    func testJISPutsCapsLockAndControlWhereAppleDoes() throws {
        let geometry = KeyboardGeometry.jis
        let capsLock = try XCTUnwrap(geometry.caps.first { $0.id == "caps-lock" })
        XCTAssertEqual(capsLock.x, 0, accuracy: 0.001)
        XCTAssertEqual(capsLock.y, 3, accuracy: 0.001, "caps lock belongs on the home row")

        let control = try XCTUnwrap(geometry.caps.first { $0.id == "control" })
        XCTAssertEqual(control.y, 5, accuracy: 0.001, "control belongs in the bottom row")
        XCTAssertEqual(
            geometry.caps.filter { $0.identities.contains(KeyIdentity(keyCode: 0x3B)) }.count, 1,
            "there is one control key on this board"
        )
    }

    /// A gap inside a heatmap reads as a key that was never pressed, and an
    /// overlap hides one cap behind another. Rotated caps are left out: the
    /// Corne's thumb keys are meant to converge and an axis-aligned test would
    /// report them wrongly.
    func testUnrotatedCapsNeitherOverlapNorLeaveHoles() {
        for geometry in geometries {
            let caps = geometry.caps.filter { $0.rotation == 0 && !$0.legend.primary.isEmpty }
            for (index, a) in caps.enumerated() {
                for b in caps[(index + 1)...] {
                    let overlapX = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
                    let overlapY = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
                    XCTAssertFalse(
                        overlapX > 0.001 && overlapY > 0.001,
                        "\(geometry.model.rawValue): \(a.id) overlaps \(b.id)"
                    )
                }
            }
        }
    }

    /// A hole in the middle of a row is what breaks a heatmap: an empty unit
    /// between two caps reads as a key that was never pressed. A ragged right
    /// edge does not — the function row genuinely ends at F12 — so only interior
    /// gaps are checked, over the whole row band so that the half-height arrow
    /// pair counts as filling its column.
    func testStaggeredBoardRowsHaveNoInteriorGaps() {
        for geometry in [KeyboardGeometry.jis, .us] {
            let rowTops = Set(geometry.caps.filter { $0.height == 1 }.map(\.y)).sorted()
            for top in rowTops {
                let band = geometry.caps.filter { $0.y < top + 1 - 0.001 && $0.y + $0.height > top + 0.001 }
                let spans = band.map { ($0.x, $0.x + $0.width) }.sorted { $0.0 < $1.0 }
                var reach = spans.first?.1 ?? 0
                for span in spans.dropFirst() {
                    XCTAssertLessThanOrEqual(
                        span.0,
                        reach + 0.001,
                        "\(geometry.model.rawValue) row y=\(top) has a gap before x=\(span.0)"
                    )
                    reach = max(reach, span.1)
                }
            }
        }
    }

    func testStaggeredBoardsCoverTheAlphabet() {
        let letters: Set<UInt16> = [
            0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28,
            0x25, 0x2E, 0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09,
            0x0D, 0x07, 0x10, 0x06,
        ]
        for geometry in geometries {
            let present = Set(geometry.caps.flatMap(\.identities).map(\.keyCode))
            XCTAssertTrue(
                letters.isSubset(of: present),
                "\(geometry.model.rawValue) is missing \(letters.subtracting(present).map { String($0, radix: 16) })"
            )
        }
    }

    // MARK: - Cornix

    /// macOS receives one keycode from every key that sends Return, so a
    /// keymap that puts Return on several keys shares a single total across
    /// them. The picture must be built to say that rather than to hide it.
    func testCornixReturnAndBackspaceAreSharedAcrossSeveralCaps() throws {
        let geometry = KeyboardGeometry.cornix(keymap: try Self.sharedEnterKeymap())
        func caps(carrying identity: KeyIdentity) -> [KeyCap] {
            geometry.caps.filter { $0.identities.contains(identity) }
        }

        XCTAssertEqual(
            caps(carrying: KeyIdentity(keyCode: 0x24, isShifted: false)).count, 3,
            "the thumb Enter, LALT_T and LSFT_T all send a plain Return"
        )
        XCTAssertEqual(
            caps(carrying: KeyIdentity(keyCode: 0x24, isShifted: true)).count, 4,
            "the LSFT(KC_ENTER) key, plus the three plain-Return keys when Shift is held"
        )
        XCTAssertEqual(
            caps(carrying: KeyIdentity(keyCode: 0x33, isShifted: false)).count, 2,
            "the outer-column Backspace and LT1(KC_BSPACE)"
        )
    }

    /// A synthetic keymap that spreads Return over three keys, Shift+Return
    /// over one more, and Backspace over two — the sharing the tests around it
    /// pin down. Applied over the built-in default, which carries one Enter and
    /// one Backspace of its own.
    private static func sharedEnterKeymap() throws -> VialKeymap {
        let vil = """
        {"version": 1, "layout": [[
          [-1, -1, -1, -1, -1, -1, -1],
          [-1, -1, -1, -1, -1, -1, -1],
          [-1, -1, -1, -1, -1, -1, -1],
          ["LT1(KC_BSPACE)", "LSFT(KC_ENTER)", -1, -1, -1, -1, -1],
          [-1, -1, -1, -1, -1, -1, -1],
          [-1, -1, -1, -1, -1, -1, -1],
          [-1, -1, -1, -1, -1, -1, -1],
          ["LALT_T(KC_ENTER)", "LSFT_T(KC_ENTER)", -1, -1, -1, -1, -1]
        ]]}
        """
        return try VialKeymap.parse(data: Data(vil.utf8))
    }

    /// Shift is a physical fact, not a keymap entry: the same `A` key sends a
    /// shifted `A` when Shift is held. A board that claimed only the unshifted
    /// identity would record every `Shift+;` and `Shift+/` and then draw them
    /// nowhere.
    func testCornixLettersAndSymbolsClaimBothShiftStates() {
        let geometry = KeyboardGeometry.cornix
        for keyCode: UInt16 in [0x00, 0x01, 0x29, 0x2C, 0x2B, 0x2F, 0x27] {
            let cap = geometry.caps.first {
                $0.identities.contains(KeyIdentity(keyCode: keyCode))
            }
            XCTAssertNotNil(cap, "no cap sends \(String(keyCode, radix: 16))")
            XCTAssertTrue(
                cap?.identities.contains(KeyIdentity(keyCode: keyCode, isShifted: true)) ?? false,
                "\(cap?.id ?? "?") drops its shifted presses"
            )
        }
    }

    /// A key whose keymap action already carries Shift sends only that. Claiming
    /// the plain variant too would take presses off the keys that do send it.
    func testCornixShiftedActionsDoNotAlsoClaimTheUnshiftedKey() throws {
        let geometry = KeyboardGeometry.cornix(keymap: try Self.sharedEnterKeymap())
        let shiftedReturn = KeyIdentity(keyCode: 0x24, isShifted: true)
        // The one LSFT(KC_ENTER) cap sends Shift+Return only; the three
        // plain-Return caps send a bare Return and, with Shift held, a shifted
        // one.
        let shiftedOnly = geometry.caps.filter { $0.identities == [shiftedReturn] }
        XCTAssertEqual(shiftedOnly.count, 1)
    }

    /// The picture must say which Shift reading applies to the keymap it is
    /// actually drawing: a left wrap poisons the left count, a right wrap is a
    /// usage counter, and a keymap with neither needs no note at all.
    func testCornixShiftWrapCaveatsFollowTheKeymap() throws {
        func cornix(replacingThumbWith token: String) throws -> KeyboardGeometry {
            let vil = #"""
            {"version": 1, "layout": [[
              ["KC_TAB", "KC_Q", "KC_W", "KC_E", "KC_R", "KC_T", -1],
              ["KC_LCTRL", "KC_A", "KC_S", "KC_D", "KC_F", "KC_G", -1],
              ["KC_LSHIFT", "KC_Z", "KC_X", "KC_C", "KC_V", "KC_B", "KC_MUTE"],
              ["KC_NO", "KC_NO", "KC_NO", "KC_LGUI", "KC_SPACE", "KC_LANG2", -1],
              ["KC_Y", "KC_U", "KC_I", "KC_O", "KC_P", "KC_BSPACE", -1],
              ["KC_H", "KC_J", "KC_K", "KC_L", "KC_SCOLON", "KC_QUOTE", "KC_MUTE"],
              ["KC_N", "KC_M", "KC_COMMA", "KC_DOT", "KC_SLASH", "KC_ESCAPE", -1],
              ["KC_NO", "KC_NO", "KC_NO", "KC_RALT", "THUMB", "KC_ENTER", -1]
            ]]}
            """#.replacingOccurrences(of: "THUMB", with: token)
            return KeyboardGeometry.cornix(keymap: try VialKeymap.parse(data: Data(vil.utf8)))
        }

        let leftWrapped = try cornix(replacingThumbWith: "LSFT(KC_ENTER)")
        XCTAssertTrue(leftWrapped.caveats.contains { $0.contains("LSft ラップ") })
        XCTAssertFalse(leftWrapped.caveats.contains { $0.contains("RSft ラップ") })

        let rightWrapped = try cornix(replacingThumbWith: "RSFT(KC_ENTER)")
        XCTAssertTrue(rightWrapped.caveats.contains { $0.contains("RSft ラップ") })
        XCTAssertFalse(rightWrapped.caveats.contains { $0.contains("LSft ラップ") })

        let unwrapped = try cornix(replacingThumbWith: "KC_ENTER")
        XCTAssertFalse(unwrapped.caveats.contains { $0.contains("ラップ") })

        // The generic built-in carries no wraps, so it must carry no note.
        XCTAssertFalse(KeyboardGeometry.cornix.caveats.contains { $0.contains("ラップ") })
    }

    func testCornixHasBothEncodersAndNeitherIsCounted() {
        let encoders = KeyboardGeometry.cornix.caps.filter { $0.exclusion == .encoder }
        XCTAssertEqual(encoders.count, 2)
        for encoder in encoders {
            XCTAssertTrue(encoder.identities.isEmpty, "an encoder never reaches the event tap")
        }
    }

    func testCornixShortcutKeyIsMarkedRatherThanLeftLookingUnused() throws {
        XCTAssertTrue(
            KeyboardGeometry.cornix.caps.allSatisfy { $0.exclusion != .shortcut },
            "the built-in default carries no shortcut key"
        )
        let vil = """
        {"version": 1, "layout": [[
          [-1, -1, -1, -1, -1, -1, -1],
          [-1, -1, -1, -1, -1, -1, -1],
          [-1, -1, -1, -1, -1, -1, -1],
          ["0xc04", -1, -1, -1, -1, -1, -1],
          [-1, -1, -1, -1, -1, -1, -1],
          [-1, -1, -1, -1, -1, -1, -1],
          [-1, -1, -1, -1, -1, -1, -1],
          [-1, -1, -1, -1, -1, -1, -1]
        ]]}
        """
        let keymap = try VialKeymap.parse(data: Data(vil.utf8))
        let shortcuts = KeyboardGeometry.cornix(keymap: keymap).caps.filter { $0.exclusion == .shortcut }
        XCTAssertEqual(shortcuts.count, 1, "a ⌘⌥-wrapped key must be marked rather than drawn unused")
    }

    /// The picture is 50 keys: 3x6 plus a 6-key bottom row per half, plus one
    /// encoder per half.
    func testCornixDrawsEveryKeyOnTheBoard() {
        XCTAssertEqual(KeyboardGeometry.cornix.caps.count, 50)
    }

    func testCornixIsRelabelledFromAVialExportWithoutMovingAnyKey() throws {
        let vil = """
        {"version": 1, "layout": [[
          ["KC_GRAVE", "KC_Q", "KC_W", "KC_E", "KC_R", "KC_T", -1],
          ["KC_LCTRL", "KC_A", "KC_S", "KC_D", "KC_F", "KC_G", -1],
          ["KC_LSHIFT", "KC_Z", "KC_X", "KC_C", "KC_V", "KC_B", "KC_MUTE"],
          ["KC_NO", "KC_NO", "KC_NO", "KC_LGUI", "KC_LANG2", "KC_SPACE", -1],
          ["KC_BSPACE", "KC_P", "KC_O", "KC_I", "KC_U", "KC_Y", -1],
          ["KC_QUOTE", "KC_SCOLON", "KC_L", "KC_K", "KC_J", "KC_H", "KC_MUTE"],
          ["KC_ESCAPE", "KC_SLASH", "KC_DOT", "KC_COMMA", "KC_M", "KC_N", -1],
          ["KC_NO", "KC_NO", "KC_NO", "KC_RALT", "KC_LANG1", "KC_ENTER", -1]
        ]]}
        """
        let keymap = try VialKeymap.parse(data: Data(vil.utf8))
        let relabelled = KeyboardGeometry.cornix(keymap: keymap)
        let builtIn = KeyboardGeometry.cornix

        XCTAssertEqual(relabelled.caps.count, builtIn.caps.count)
        for (new, old) in zip(relabelled.caps, builtIn.caps) {
            XCTAssertEqual(new.id, old.id)
            XCTAssertEqual(new.x, old.x, accuracy: 0.0001, "\(new.id) moved")
            XCTAssertEqual(new.y, old.y, accuracy: 0.0001, "\(new.id) moved")
            XCTAssertEqual(new.rotation, old.rotation, accuracy: 0.0001, "\(new.id) rotated")
        }

        // The one key this export changes is the outer left key of row 0, which
        // is Tab in the built-in layout and backquote here.
        let identities = Set(relabelled.caps.flatMap(\.identities))
        XCTAssertTrue(identities.contains(KeyIdentity(keyCode: 0x32)), "backquote did not land")
        XCTAssertFalse(identities.contains(KeyIdentity(keyCode: 0x30)), "Tab should be gone")

        // The right half is stored outer-to-inner and drawn inner-to-outer. If
        // that reversal were dropped, Y would be under the right pinky.
        let y = try XCTUnwrap(relabelled.caps.first { $0.identities.contains(KeyIdentity(keyCode: 0x10)) })
        let p = try XCTUnwrap(relabelled.caps.first { $0.identities.contains(KeyIdentity(keyCode: 0x23)) })
        XCTAssertLessThan(y.x, p.x, "Y must sit inboard of P")
    }

    /// A .vil from a different keyboard must degrade to the built-in caps
    /// rather than trapping. Someone will point this at the wrong file.
    func testCornixSurvivesATruncatedOrForeignVialExport() throws {
        for vil in [
            #"{"version": 1, "layout": [[["KC_A"]]]}"#,
            #"{"version": 1, "layout": [[[], [], [], [], [], [], [], []]]}"#,
            #"{"version": 1, "layout": [[["KC_A", "KC_B"], ["KC_C"]]]}"#,
        ] {
            let keymap = try VialKeymap.parse(data: Data(vil.utf8))
            let geometry = KeyboardGeometry.cornix(keymap: keymap)
            XCTAssertEqual(geometry.caps.count, KeyboardGeometry.cornix.caps.count, vil)
        }
    }
}
