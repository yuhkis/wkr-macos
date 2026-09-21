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
                if cap.legend.primary.isEmpty {
                    XCTAssertTrue(
                        cap.identities.isEmpty,
                        "\(geometry.model.rawValue) \(cap.id) is countable but unlabelled"
                    )
                }
            }
        }
    }

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

    func testJISAndCornixBothCarryEisuAndKana() {
        let eisu = KeyIdentity(keyCode: 0x66)
        let kana = KeyIdentity(keyCode: 0x68)
        for geometry in [KeyboardGeometry.jis, .cornix] {
            let identities = Set(geometry.caps.flatMap(\.identities))
            XCTAssertTrue(identities.contains(eisu), "\(geometry.model.rawValue) has no 英数")
            XCTAssertTrue(identities.contains(kana), "\(geometry.model.rawValue) has no かな")
        }
    }

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

    func testCornixShiftModTapsSplitThreeCapsAndShareLeftShiftWithDedicatedKey() throws {
        let keymap = try VialKeymap.parse(data: Data(Self.splitShiftKeymap.utf8))
        let boards = KeyboardGeometry.cornixLayers(keymap: keymap)
        XCTAssertEqual(boards.map(\.displayName), [
            KeyboardModel.cornix.displayName,
            "Cornix レイヤー2",
        ])

        let caps = boards.flatMap(\.caps)
        let leftShift = KeyIdentity(keyCode: 0x38)
        let splitCaps = caps.filter { $0.tapHold?.hold.identities == [leftShift] }
        XCTAssertEqual(splitCaps.count, 3)
        for cap in splitCaps {
            XCTAssertEqual(cap.tapHold?.hold.legend, "LShift", cap.id)
            XCTAssertEqual(cap.tapHold?.hold.exclusion, .modifier, cap.id)
        }

        let tapParts = Dictionary(
            uniqueKeysWithValues: try splitCaps.map { cap in
                (cap.id, try XCTUnwrap(cap.tapHold).tap)
            }
        )
        XCTAssertEqual(tapParts["cornix-l-r0-c1"]?.legend, "A")
        XCTAssertEqual(tapParts["cornix-l-r0-c1"]?.identities, [
            KeyIdentity(keyCode: 0x00),
            KeyIdentity(keyCode: 0x00, isShifted: true),
        ])
        XCTAssertEqual(tapParts["cornix-r-r0-c4"]?.legend, "B")
        XCTAssertEqual(tapParts["cornix-r-r0-c4"]?.identities, [
            KeyIdentity(keyCode: 0x0B),
            KeyIdentity(keyCode: 0x0B, isShifted: true),
        ])
        XCTAssertEqual(tapParts["cornix-l-r0-c2-layer2"]?.legend, "C")
        XCTAssertEqual(tapParts["cornix-l-r0-c2-layer2"]?.identities, [
            KeyIdentity(keyCode: 0x08),
            KeyIdentity(keyCode: 0x08, isShifted: true),
        ])

        let dedicated = try XCTUnwrap(caps.first { $0.id == "cornix-l-r0-c0" })
        XCTAssertNil(dedicated.tapHold)
        XCTAssertEqual(dedicated.exclusion, .modifier)
        XCTAssertTrue(dedicated.identities.contains(leftShift))

        let actionClaims = caps.flatMap { cap -> [[KeyIdentity]] in
            if let tapHold = cap.tapHold {
                return [tapHold.tap.identities, tapHold.hold.identities]
            }
            return [cap.identities]
        }
        XCTAssertEqual(
            actionClaims.filter { $0.contains(leftShift) }.count,
            4,
            "three hold halves and the dedicated key must claim one shared Left Shift total"
        )

        let layerTapCaps = try XCTUnwrap(caps.first { $0.id == "cornix-l-r1-c1" })
        XCTAssertEqual(layerTapCaps.tapHold?.tap.legend, "Caps")
        XCTAssertEqual(layerTapCaps.tapHold?.tap.exclusion, .modifier)
        XCTAssertEqual(layerTapCaps.tapHold?.hold.legend, "Layer 2")
        XCTAssertEqual(layerTapCaps.tapHold?.hold.exclusion, .layerHold)
    }

    private static let splitShiftKeymap = #"""
    {"version": 1, "layout": [
      [["KC_LSHIFT", "LSFT_T(KC_A)", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "LT2(KC_CAPSLOCK)", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO"],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "LSFT_T(KC_B)", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO"],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1]],
      [["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO"],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO"],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1]],
      [["KC_NO", "KC_NO", "LSFT_T(KC_C)", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO"],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO"],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1]]
    ]}
    """#

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

    func testCornixShiftedActionsDoNotAlsoClaimTheUnshiftedKey() throws {
        let geometry = KeyboardGeometry.cornix(keymap: try Self.sharedEnterKeymap())
        let shiftedReturn = KeyIdentity(keyCode: 0x24, isShifted: true)
        let shiftedOnly = geometry.caps.filter { $0.identities == [shiftedReturn] }
        XCTAssertEqual(shiftedOnly.count, 1)
    }

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

        XCTAssertFalse(KeyboardGeometry.cornix.caveats.contains { $0.contains("ラップ") })
    }

    func testShiftWrapNoteSurvivesWrapsHiddenOnHigherLayers() throws {
        let vil = #"""
        {"version": 1, "layout": [
          [["KC_TAB", "KC_Q", "KC_W", "KC_E", "KC_R", "KC_T", -1],
           ["KC_LCTRL", "KC_A", "KC_S", "KC_D", "KC_F", "KC_G", -1],
           ["KC_LSHIFT", "KC_Z", "KC_X", "KC_C", "KC_V", "KC_B", "KC_MUTE"],
           ["KC_NO", "KC_NO", "KC_NO", "KC_LGUI", "KC_SPACE", "KC_LANG2", -1],
           ["KC_Y", "KC_U", "KC_I", "KC_O", "KC_P", "KC_BSPACE", -1],
           ["KC_H", "KC_J", "KC_K", "KC_L", "KC_SCOLON", "KC_QUOTE", "KC_MUTE"],
           ["KC_N", "KC_M", "KC_COMMA", "KC_DOT", "KC_SLASH", "KC_ESCAPE", -1],
           ["KC_NO", "KC_NO", "KC_NO", "KC_RALT", "RSFT(KC_ENTER)", "KC_ENTER", -1]],
          [["KC_NO", "LSFT(KC_1)", "LSFT(KC_2)", "KC_NO", "KC_NO", "KC_NO", -1]]
        ]}
        """#
        let keymap = try VialKeymap.parse(data: Data(vil.utf8))
        XCTAssertEqual(keymap.firmwareShiftSides, [.left, .right])

        let geometry = KeyboardGeometry.cornix(keymap: keymap)
        XCTAssertTrue(
            geometry.caveats.contains { $0.contains("LSft ラップ") },
            "the layer-1 wraps still press left Shift and the note must say so"
        )
        XCTAssertTrue(geometry.caveats.contains { $0.contains("RSft ラップ") })
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

        let identities = Set(relabelled.caps.flatMap(\.identities))
        XCTAssertTrue(identities.contains(KeyIdentity(keyCode: 0x32)), "backquote did not land")
        XCTAssertFalse(identities.contains(KeyIdentity(keyCode: 0x30)), "Tab should be gone")

        let y = try XCTUnwrap(relabelled.caps.first { $0.identities.contains(KeyIdentity(keyCode: 0x10)) })
        let p = try XCTUnwrap(relabelled.caps.first { $0.identities.contains(KeyIdentity(keyCode: 0x23)) })
        XCTAssertLessThan(y.x, p.x, "Y must sit inboard of P")
    }


    private let layeredVil = #"""
    {"version": 1, "layout": [
      [["KC_TAB", "KC_Q", "KC_W", "KC_E", "KC_R", "KC_T", -1],
       ["KC_LCTRL", "KC_A", "KC_S", "KC_D", "KC_F", "KC_G", -1],
       ["KC_LSHIFT", "KC_Z", "KC_X", "KC_C", "KC_V", "KC_B", "KC_MUTE"],
       ["KC_NO", "KC_NO", "KC_NO", "KC_LGUI", "LT1(KC_SPACE)", "KC_LANG2", -1],
       ["KC_Y", "KC_U", "KC_I", "KC_O", "KC_P", "KC_BSPACE", -1],
       ["KC_H", "KC_J", "KC_K", "KC_L", "KC_SCOLON", "KC_QUOTE", "KC_MUTE"],
       ["KC_N", "KC_M", "KC_COMMA", "KC_DOT", "KC_SLASH", "KC_ESCAPE", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_RALT", "KC_LANG1", "KC_ENTER", -1]],
      [["KC_NO", "RSFT(KC_1)", "KC_TRNS", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_1", "KC_2", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_MUTE"],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_LEFT", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_MUTE"],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1]],
      [["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_LEFT", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_MUTE"],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_MUTE"],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1]],
      [["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_MUTE"],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_MUTE"],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO", -1]]
    ]}
    """#

    func testCornixLayersDrawsOnlyLayersWithCountableContent() throws {
        let keymap = try VialKeymap.parse(data: Data(layeredVil.utf8))
        let boards = KeyboardGeometry.cornixLayers(keymap: keymap)
        XCTAssertEqual(boards.count, 3, "layer 0, layer 1, layer 2")
        XCTAssertEqual(boards[0].displayName, KeyboardModel.cornix.displayName)
        XCTAssertEqual(boards[1].displayName, "Cornix レイヤー1")
        XCTAssertEqual(boards[2].displayName, "Cornix レイヤー2")
        for board in boards {
            XCTAssertEqual(board.model, .cornix, "the family key the renderer groups by")
        }
    }

    func testLayerBoardsDoNotInheritTheBaseLayerCaps() throws {
        let keymap = try VialKeymap.parse(data: Data(layeredVil.utf8))
        let layer1 = KeyboardGeometry.cornixLayers(keymap: keymap)[1]

        let tabPosition = try XCTUnwrap(layer1.caps.first { $0.id == "cornix-l-r0-c0-layer1" })
        XCTAssertTrue(tabPosition.identities.isEmpty)
        XCTAssertEqual(tabPosition.legend.primary, "")

        let shifted1 = try XCTUnwrap(layer1.caps.first { $0.id == "cornix-l-r0-c1-layer1" })
        XCTAssertEqual(shifted1.identities, [KeyIdentity(keyCode: 0x12, isShifted: true)])
        XCTAssertEqual(shifted1.legend.secondary, "RSft")

        let plain1 = try XCTUnwrap(layer1.caps.first { $0.id == "cornix-l-r1-c1-layer1" })
        XCTAssertTrue(plain1.identities.contains(KeyIdentity(keyCode: 0x12, isShifted: false)))
        XCTAssertTrue(plain1.identities.contains(KeyIdentity(keyCode: 0x12, isShifted: true)))
    }

    func testLayerCapsKeepTheirPositionsAndFingers() throws {
        let keymap = try VialKeymap.parse(data: Data(layeredVil.utf8))
        let boards = KeyboardGeometry.cornixLayers(keymap: keymap)
        let base = boards[0]
        let layer1 = boards[1]
        for cap in layer1.caps {
            let baseID = String(cap.id.dropLast("-layer1".count))
            let sibling = try XCTUnwrap(base.caps.first { $0.id == baseID }, baseID)
            XCTAssertEqual(cap.x, sibling.x, accuracy: 0.0001, cap.id)
            XCTAssertEqual(cap.y, sibling.y, accuracy: 0.0001, cap.id)
            XCTAssertEqual(cap.rotation, sibling.rotation, accuracy: 0.0001, cap.id)
            if !cap.identities.isEmpty {
                XCTAssertEqual(cap.finger, sibling.finger, cap.id)
            }
        }
    }

    func testAnIdentityOnTwoLayersIsClaimedByBoth() throws {
        let keymap = try VialKeymap.parse(data: Data(layeredVil.utf8))
        let boards = KeyboardGeometry.cornixLayers(keymap: keymap)
        let left = KeyIdentity(keyCode: 0x7B, isShifted: false)
        XCTAssertTrue(boards[1].caps.contains { $0.identities.contains(left) })
        XCTAssertTrue(boards[2].caps.contains { $0.identities.contains(left) })
        for board in boards.dropFirst() {
            XCTAssertFalse(board.caveats.isEmpty, board.displayName)
            XCTAssertTrue(
                board.caveats.contains { $0.contains("合算") },
                "\(board.displayName) must explain shared totals"
            )
        }
    }

    func testLayeredBaseBoardDropsTheLayersAreInvisibleCaveat() throws {
        let keymap = try VialKeymap.parse(data: Data(layeredVil.utf8))
        let base = KeyboardGeometry.cornixLayers(keymap: keymap)[0]
        XCTAssertFalse(base.caveats.contains { $0.contains("描いているのはレイヤー0だけ") })
        XCTAssertTrue(base.caveats.contains { $0.contains("それぞれのタブ") })
        XCTAssertTrue(
            KeyboardGeometry.cornix(keymap: keymap).caveats
                .contains { $0.contains("描いているのはレイヤー0だけ") }
        )
    }

    func testLayerBoardCapIDsAreUniqueAcrossTheFamily() throws {
        let keymap = try VialKeymap.parse(data: Data(layeredVil.utf8))
        var seen: Set<String> = []
        for board in KeyboardGeometry.cornixLayers(keymap: keymap) {
            for cap in board.caps {
                XCTAssertTrue(seen.insert(cap.id).inserted, cap.id)
            }
        }
    }

    func testCornixLayersDegradesToOneBoard() throws {
        let single = try VialKeymap.parse(data: Data(#"{"version":1,"layout":[[["KC_A"]]]}"#.utf8))
        XCTAssertEqual(KeyboardGeometry.cornixLayers(keymap: single).count, 1)
    }

    func testSingleTabKeepsTheSingleBoardCaveats() throws {
        let vil = #"""
        {"version":1,"layout":[
          [["KC_A", "KC_B"]],
          [["KC_NO", "KC_NO"]],
          [["KC_MUTE", "KC_NO"]]
        ]}
        """#
        let boards = KeyboardGeometry.cornixLayers(
            keymap: try VialKeymap.parse(data: Data(vil.utf8))
        )
        XCTAssertEqual(boards.count, 1, "an all-KC_NO layer and a media-only layer are not tabs")
        XCTAssertTrue(boards[0].caveats.contains { $0.contains("描いているのはレイヤー0だけ") })
        XCTAssertFalse(boards[0].caveats.contains { $0.contains("それぞれのタブ") })
    }

    func testCornixSecondariesAreNeverShiftedLegends() throws {
        let keymap = try VialKeymap.parse(data: Data(layeredVil.utf8))
        for board in KeyboardGeometry.cornixLayers(keymap: keymap) {
            for cap in board.caps where cap.legend.secondary != nil {
                XCTAssertFalse(
                    cap.legend.secondaryIsShifted,
                    "\(board.displayName) \(cap.id) claims its hold label is a shifted legend"
                )
            }
        }
        let jis2 = try XCTUnwrap(KeyboardGeometry.jis.caps.first { $0.legend.primary == "2" })
        XCTAssertTrue(jis2.legend.secondaryIsShifted)
    }

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
