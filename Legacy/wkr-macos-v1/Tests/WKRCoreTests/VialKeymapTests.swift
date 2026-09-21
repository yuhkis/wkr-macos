import XCTest
@testable import WKRCore

final class VialKeymapTests: XCTestCase {
    private func decode(_ token: String) -> VialKeyAssignment {
        VialKeymap.decode(token: token)
    }


    func testLettersMapToTheirMacOSKeyCodes() {
        XCTAssertEqual(decode("KC_A").identity, KeyIdentity(keyCode: 0x00))
        XCTAssertEqual(decode("KC_S").identity, KeyIdentity(keyCode: 0x01))
        XCTAssertEqual(decode("KC_B").identity, KeyIdentity(keyCode: 0x0B))
        XCTAssertEqual(decode("KC_Q").identity, KeyIdentity(keyCode: 0x0C))
        XCTAssertEqual(decode("KC_Y").identity, KeyIdentity(keyCode: 0x10))
        XCTAssertEqual(decode("KC_T").identity, KeyIdentity(keyCode: 0x11))
    }

    func testDigitsFollowTheMacOSOrderingRatherThanTheObviousOne() {
        XCTAssertEqual(decode("KC_5").identity, KeyIdentity(keyCode: 0x17))
        XCTAssertEqual(decode("KC_6").identity, KeyIdentity(keyCode: 0x16))
        XCTAssertEqual(decode("KC_7").identity, KeyIdentity(keyCode: 0x1A))
        XCTAssertEqual(decode("KC_8").identity, KeyIdentity(keyCode: 0x1C))
        XCTAssertEqual(decode("KC_9").identity, KeyIdentity(keyCode: 0x19))
        XCTAssertEqual(decode("KC_0").identity, KeyIdentity(keyCode: 0x1D))
    }

    func testJISOnlyKeycodes() {
        XCTAssertEqual(decode("KC_JYEN").identity, KeyIdentity(keyCode: 0x5D))
        XCTAssertEqual(decode("KC_RO").identity, KeyIdentity(keyCode: 0x5E))
        XCTAssertEqual(decode("KC_LANG1").identity, KeyIdentity(keyCode: 0x68))
        XCTAssertEqual(decode("KC_LANG2").identity, KeyIdentity(keyCode: 0x66))
    }

    func testBracketKeysUseTheirMacOSPositions() {
        XCTAssertEqual(decode("KC_RBRACKET").identity, KeyIdentity(keyCode: 0x1E))
        XCTAssertEqual(decode("KC_NONUS_HASH").identity, KeyIdentity(keyCode: 0x2A))
    }

    func testAbbreviatedAliasesDecodeIdenticallyToTheLongForm() {
        XCTAssertEqual(decode("KC_BSPC").identity, decode("KC_BSPACE").identity)
        XCTAssertEqual(decode("KC_ENT").identity, decode("KC_ENTER").identity)
        XCTAssertEqual(decode("KC_SPC").identity, decode("KC_SPACE").identity)
        XCTAssertEqual(decode("KC_SCLN").identity, decode("KC_SCOLON").identity)
    }


    func testShiftWrapperAndShiftModTapAreNotTheSameKey() {
        let wrapped = decode("LSFT(KC_ENTER)")
        let modTap = decode("LSFT_T(KC_ENTER)")

        XCTAssertEqual(wrapped.identity, KeyIdentity(keyCode: 0x24, isShifted: true))
        XCTAssertEqual(modTap.identity, KeyIdentity(keyCode: 0x24, isShifted: false))
        XCTAssertNotEqual(wrapped.identity, modTap.identity)
    }

    func testShiftModTapsExposeSideSpecificHoldIdentities() throws {
        let left = decode("LSFT_T(KC_LANG2)")
        XCTAssertEqual(left.identity, KeyIdentity(keyCode: 0x66))
        let leftHold = try XCTUnwrap(left.holdAction)
        XCTAssertEqual(leftHold.legend, "LShift")
        XCTAssertEqual(leftHold.identity, KeyIdentity(keyCode: 0x38))
        XCTAssertEqual(leftHold.exclusion, .modifier)

        let right = decode("RSFT_T(KC_LANG1)")
        XCTAssertEqual(right.identity, KeyIdentity(keyCode: 0x68))
        let rightHold = try XCTUnwrap(right.holdAction)
        XCTAssertEqual(rightHold.legend, "RShift")
        XCTAssertEqual(rightHold.identity, KeyIdentity(keyCode: 0x3C))
        XCTAssertEqual(rightHold.exclusion, .modifier)
    }

    func testModTapWithANonShiftModifierKeepsSeparateTapAndHoldIdentities() {
        let altEnter = decode("LALT_T(KC_ENTER)")
        XCTAssertEqual(altEnter.identity, KeyIdentity(keyCode: 0x24, isShifted: false))
        XCTAssertNil(altEnter.exclusion, "a tapped LALT_T sends a plain Return, not Option+Return")
        XCTAssertEqual(altEnter.holdAction?.legend, "LAlt")
        XCTAssertEqual(altEnter.holdAction?.identity, KeyIdentity(keyCode: 0x3A))
        XCTAssertEqual(altEnter.holdAction?.exclusion, .modifier)

        let guiBackspace = decode("RGUI_T(KC_BSPACE)")
        XCTAssertEqual(guiBackspace.identity, KeyIdentity(keyCode: 0x33, isShifted: false))
        XCTAssertNil(guiBackspace.exclusion)
        XCTAssertEqual(guiBackspace.holdAction?.legend, "RGui")
        XCTAssertEqual(guiBackspace.holdAction?.identity, KeyIdentity(keyCode: 0x36))
        XCTAssertEqual(guiBackspace.holdAction?.exclusion, .modifier)

        let compound = decode("C_S_T(KC_A)")
        XCTAssertEqual(compound.identity, KeyIdentity(keyCode: 0x00))
        XCTAssertNil(compound.holdAction?.identity)
        XCTAssertEqual(compound.holdAction?.exclusion, .compoundModifierHold)

        let capsLock = decode("LALT_T(KC_CAPSLOCK)")
        XCTAssertEqual(capsLock.identity, KeyIdentity(keyCode: 0x39))
        XCTAssertEqual(capsLock.exclusion, .modifier)
        XCTAssertEqual(capsLock.holdAction?.identity, KeyIdentity(keyCode: 0x3A))
    }

    func testCommandOrControlWrappersAreMarkedAsShortcuts() {
        XCTAssertEqual(decode("LGUI(KC_LBRACKET)").exclusion, .shortcut)
        XCTAssertEqual(decode("LCTL(KC_SPACE)").exclusion, .shortcut)
        XCTAssertEqual(decode("LALT(KC_SPACE)").exclusion, .shortcut)
        XCTAssertEqual(decode("C_S(KC_UP)").exclusion, .shortcut)
    }

    func testLayerTapKeepsTheTapActionAndMarksTheHold() {
        let space = decode("LT1(KC_SPACE)")
        XCTAssertEqual(space.identity, KeyIdentity(keyCode: 0x31))
        XCTAssertNil(space.exclusion)
        XCTAssertEqual(space.legend.primary, "Space")
        XCTAssertEqual(space.holdAction?.legend, "Layer 1")
        XCTAssertNil(space.holdAction?.identity)
        XCTAssertEqual(space.holdAction?.exclusion, .layerHold)

        let eisu = decode("LT2(KC_LANG2)")
        XCTAssertEqual(eisu.identity, KeyIdentity(keyCode: 0x66))
        XCTAssertNil(eisu.exclusion)
        XCTAssertEqual(eisu.holdAction?.legend, "Layer 2")
        XCTAssertNil(eisu.holdAction?.identity)
        XCTAssertEqual(eisu.holdAction?.exclusion, .layerHold)

        let backspace = decode("LT3(KC_BSPACE)")
        XCTAssertEqual(backspace.identity, KeyIdentity(keyCode: 0x33))
        XCTAssertNil(backspace.exclusion)
        XCTAssertEqual(backspace.holdAction?.legend, "Layer 3")
        XCTAssertNil(backspace.holdAction?.identity)
        XCTAssertEqual(backspace.holdAction?.exclusion, .layerHold)
    }

    func testPlainLayerSwitchesHaveNoIdentity() {
        for token in ["MO(1)", "TG(2)", "TO(0)", "DF(1)", "OSL(3)"] {
            let assignment = decode(token)
            XCTAssertNil(assignment.identity, "\(token) never reaches macOS")
            XCTAssertEqual(assignment.exclusion, .layerHold, "\(token)")
        }
    }


    func testRawModsHexDecodesToTheModifiedBasicKey() {
        let assignment = decode("0xc04")
        XCTAssertEqual(assignment.exclusion, .shortcut)
        XCTAssertEqual(assignment.legend.primary, "A")
        XCTAssertEqual(assignment.legend.secondary, "⌘⌥")
    }

    func testShortcutKeysBorrowNoOtherKeysCount() {
        for token in ["0xc04", "LGUI(KC_LBRACKET)", "LCTL(KC_SPACE)", "LALT(KC_SPACE)", "C_S(KC_UP)"] {
            let assignment = decode(token)
            XCTAssertNil(assignment.identity, "\(token) must claim no identity")
            XCTAssertEqual(assignment.exclusion, .shortcut, "\(token)")
        }
    }

    func testShiftOnlyWrappersKeepTheirIdentity() {
        XCTAssertEqual(decode("LSFT(KC_1)").identity, KeyIdentity(keyCode: 0x12, isShifted: true))
        XCTAssertNil(decode("LSFT(KC_1)").exclusion)
    }

    func testRightShiftWrapperMatchesTheLeftOneExceptForItsSide() {
        let right = decode("RSFT(KC_ENTER)")
        XCTAssertEqual(right.identity, KeyIdentity(keyCode: 0x24, isShifted: true))
        XCTAssertNil(right.exclusion)
        XCTAssertEqual(right.legend.secondary, "RSft")
        XCTAssertEqual(right.identity, decode("LSFT(KC_ENTER)").identity)
    }

    func testFirmwareShiftSideIsReadFromEveryWrapForm() {
        XCTAssertEqual(decode("LSFT(KC_ENTER)").firmwareShiftSide, .left)
        XCTAssertEqual(decode("RSFT(KC_ENTER)").firmwareShiftSide, .right)
        XCTAssertEqual(decode("0x228").firmwareShiftSide, .left)
        XCTAssertEqual(decode("0x1228").firmwareShiftSide, .right)
        XCTAssertNil(decode("LSFT_T(KC_ENTER)").firmwareShiftSide)
        XCTAssertNil(decode("KC_A").firmwareShiftSide)
        XCTAssertNil(decode("C_S(KC_UP)").firmwareShiftSide)
        XCTAssertNil(decode("0xc16").firmwareShiftSide)
    }

    func testRawHexInTheBasicRangeMatchesTheNamedKeycode() {
        XCTAssertEqual(decode("0x28").identity, decode("KC_ENTER").identity)
        XCTAssertEqual(decode("0x04").identity, decode("KC_A").identity)
    }

    func testRawHexModTapAndLayerTapUseTheirOwnRanges() {
        let modTap = decode("0x2228")
        XCTAssertEqual(modTap.identity, KeyIdentity(keyCode: 0x24, isShifted: false))
        XCTAssertEqual(modTap.holdAction?.identity, KeyIdentity(keyCode: 0x38))
        XCTAssertEqual(modTap.holdAction?.exclusion, .modifier)
        let layerTap = decode("0x412c")
        XCTAssertEqual(layerTap.identity, KeyIdentity(keyCode: 0x31))
        XCTAssertNil(layerTap.exclusion)
    }


    func testUnknownTokensAreDrawnVerbatimWithNoIdentity() {
        for token in ["USER00", "MACRO07", "QK_KB_3", "", "0x", "0xZZZZ", "LT(", "))("] {
            let assignment = decode(token)
            XCTAssertNil(assignment.identity, "unknown token \(token) must not invent an identity")
        }
        XCTAssertEqual(decode("USER00").legend.primary, "USER00")
    }

    func testNonKeyHardwareIsExcludedRatherThanCounted() {
        XCTAssertEqual(decode("KC_MUTE").exclusion, .media)
        XCTAssertEqual(decode("KC_MSEL").exclusion, .media)
        XCTAssertNil(decode("KC_MUTE").identity)
        XCTAssertEqual(decode("KC_BTN1").exclusion, .mouse)
        XCTAssertNil(decode("KC_BTN1").identity)
    }

    func testModifiersCarryTheirOwnKeyCodeSoFlagsChangedCanCountThem() {
        XCTAssertEqual(decode("KC_LSHIFT").identity, KeyIdentity(keyCode: 0x38))
        XCTAssertEqual(decode("KC_LCTRL").identity, KeyIdentity(keyCode: 0x3B))
        XCTAssertEqual(decode("KC_LGUI").identity, KeyIdentity(keyCode: 0x37))
        XCTAssertEqual(decode("KC_RGUI").identity, KeyIdentity(keyCode: 0x36))
        XCTAssertEqual(decode("KC_LSHIFT").exclusion, .modifier)
    }

    func testEmptyMatrixPositionsAndKCNOAreAbsent() {
        XCTAssertTrue(decode("-1").isAbsent)
        XCTAssertTrue(decode("KC_NO").isAbsent)
        XCTAssertTrue(decode("0x0").isAbsent)
        XCTAssertFalse(decode("KC_A").isAbsent)
    }

    func testCapsLockIsMarkedAsAModifier() {
        XCTAssertEqual(decode("KC_CAPSLOCK").identity, KeyIdentity(keyCode: 0x39))
        XCTAssertEqual(decode("KC_CAPSLOCK").exclusion, .modifier)
    }

    func testTransparentKeySaysWhyItIsBlank() {
        XCTAssertNil(decode("KC_TRNS").identity)
        XCTAssertEqual(decode("KC_TRNS").exclusion, .unmappedOnMacOS)
    }

    func testUnreachableLayerTapKeepsTheInnerReason() {
        XCTAssertEqual(decode("LT1(KC_MUTE)").exclusion, .media)
        XCTAssertEqual(decode("LT2(KC_BTN1)").exclusion, .mouse)
        XCTAssertEqual(decode("LT1(KC_APPLICATION)").exclusion, .unmappedOnMacOS)
        XCTAssertNil(decode("LT1(KC_SPACE)").exclusion)
        XCTAssertEqual(decode("LT2(KC_CAPSLOCK)").exclusion, .modifier)
        XCTAssertEqual(decode("LT2(KC_CAPSLOCK)").holdAction?.exclusion, .layerHold)
    }


    private let sampleVil = """
    {"version": 1, "layout": [
      [["KC_TAB", "KC_Q", "KC_W", -1],
       ["KC_LCTRL", "0xc04", "LALT_T(KC_ENTER)", "KC_LGUI"]],
      [["KC_NO", "KC_NO", "KC_NO", -1],
       ["KC_NO", "KC_NO", "KC_NO", "KC_NO"]]
    ]}
    """

    func testParseReadsOnlyTheBaseLayerAndKeepsColumnAlignment() throws {
        let keymap = try VialKeymap.parse(data: Data(sampleVil.utf8))
        XCTAssertEqual(keymap.baseLayer.count, 2)
        XCTAssertEqual(keymap.baseLayer[0].count, 4)
        XCTAssertTrue(keymap.baseLayer[0][3].isAbsent)
        XCTAssertEqual(keymap.baseLayer[0][0].identity, KeyIdentity(keyCode: 0x30))
        XCTAssertEqual(keymap.baseLayer[1][2].identity, KeyIdentity(keyCode: 0x24))
    }

    func testParseRejectsSomethingThatIsNotAVilFile() {
        XCTAssertThrowsError(try VialKeymap.parse(data: Data("not json".utf8)))
        XCTAssertThrowsError(try VialKeymap.parse(data: Data(#"{"version": 1}"#.utf8)))
        XCTAssertThrowsError(try VialKeymap.parse(data: Data(#"{"layout": []}"#.utf8)))
    }
}
