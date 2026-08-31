import XCTest
@testable import WKRCore

final class VialKeymapTests: XCTestCase {
    private func decode(_ token: String) -> VialKeyAssignment {
        VialKeymap.decode(token: token)
    }

    // MARK: - Basic keycodes

    func testLettersMapToTheirMacOSKeyCodes() {
        // Not sequential: macOS orders these by the original Apple keyboard's
        // wiring, so a table that assumes A..Z run 0x00..0x19 is wrong.
        XCTAssertEqual(decode("KC_A").identity, KeyIdentity(keyCode: 0x00))
        XCTAssertEqual(decode("KC_S").identity, KeyIdentity(keyCode: 0x01))
        XCTAssertEqual(decode("KC_B").identity, KeyIdentity(keyCode: 0x0B))
        XCTAssertEqual(decode("KC_Q").identity, KeyIdentity(keyCode: 0x0C))
        XCTAssertEqual(decode("KC_Y").identity, KeyIdentity(keyCode: 0x10))
        XCTAssertEqual(decode("KC_T").identity, KeyIdentity(keyCode: 0x11))
    }

    /// 5 and 6 are swapped relative to naive ordering, and so are 7 and 8.
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

    /// On a JIS keyboard macOS prints `[` and `]` for these two. Getting them
    /// the wrong way round would swap two live keys in the picture.
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

    // MARK: - The distinction the whole file turns on

    /// `LSFT(KC_ENTER)` sends Shift+Return. `LSFT_T(KC_ENTER)` sends a plain
    /// Return when tapped and Shift when held. They are different keys in the
    /// tally, and a keymap that carries both must keep them apart.
    func testShiftWrapperAndShiftModTapAreNotTheSameKey() {
        let wrapped = decode("LSFT(KC_ENTER)")
        let modTap = decode("LSFT_T(KC_ENTER)")

        XCTAssertEqual(wrapped.identity, KeyIdentity(keyCode: 0x24, isShifted: true))
        XCTAssertEqual(modTap.identity, KeyIdentity(keyCode: 0x24, isShifted: false))
        XCTAssertNotEqual(wrapped.identity, modTap.identity)
    }

    /// The tap remains the ordinary key while the independently observable
    /// hold is filed under the side-specific flags-changed key code. Keeping
    /// both identities is what lets the report split one cap without adding
    /// the modifier total to the tap total.
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

    /// A tapped mod-tap sends the bare key, so it is counted like any other.
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

    /// A wrapper that adds Command, Control or Option produces an event the
    /// recorder refuses to count, so the cap has to be marked rather than drawn
    /// as merely unused.
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

    // MARK: - Raw hex

    /// Vial shows a custom QK_MODS key as bare hex. Decoded through the
    /// QK_MODS range, `0xc04` is mods 0x0C (Option|Command) over basic keycode
    /// 0x04 (`KC_A`), so it is Command+Option+A.
    func testRawModsHexDecodesToTheModifiedBasicKey() {
        let assignment = decode("0xc04")
        XCTAssertEqual(assignment.exclusion, .shortcut)
        XCTAssertEqual(assignment.legend.primary, "A")
        XCTAssertEqual(assignment.legend.secondary, "⌘⌥")
    }

    /// A shortcut key must not carry the inner key code. The recorder never
    /// counts an event with Command, Control or Option set, so every press
    /// filed under `kVK_ANSI_A` came from the plain `A` key elsewhere on the
    /// board — and a ⌘⌥A cap that kept the identity would display that other
    /// key's total as its own.
    func testShortcutKeysBorrowNoOtherKeysCount() {
        for token in ["0xc04", "LGUI(KC_LBRACKET)", "LCTL(KC_SPACE)", "LALT(KC_SPACE)", "C_S(KC_UP)"] {
            let assignment = decode(token)
            XCTAssertNil(assignment.identity, "\(token) must claim no identity")
            XCTAssertEqual(assignment.exclusion, .shortcut, "\(token)")
        }
    }

    /// Shift is the one modifier that does keep the identity, because a shifted
    /// key event is counted and the shift state is part of what is counted.
    func testShiftOnlyWrappersKeepTheirIdentity() {
        XCTAssertEqual(decode("LSFT(KC_1)").identity, KeyIdentity(keyCode: 0x12, isShifted: true))
        XCTAssertNil(decode("LSFT(KC_1)").exclusion)
    }

    /// `RSFT(…)` is the escape hatch from the firmware-held-Shift ambiguity:
    /// it must produce the same shifted identity as `LSFT(…)` while macOS
    /// reports its modifier edge under the right-hand key code.
    func testRightShiftWrapperMatchesTheLeftOneExceptForItsSide() {
        let right = decode("RSFT(KC_ENTER)")
        XCTAssertEqual(right.identity, KeyIdentity(keyCode: 0x24, isShifted: true))
        XCTAssertNil(right.exclusion)
        XCTAssertEqual(right.legend.secondary, "RSft")
        XCTAssertEqual(right.identity, decode("LSFT(KC_ENTER)").identity)
    }

    /// The side is what lets a keymap separate firmware-held Shift from the
    /// physical Shift key, so it has to be read correctly from every wrap form
    /// — and from nothing else.
    func testFirmwareShiftSideIsReadFromEveryWrapForm() {
        XCTAssertEqual(decode("LSFT(KC_ENTER)").firmwareShiftSide, .left)
        XCTAssertEqual(decode("RSFT(KC_ENTER)").firmwareShiftSide, .right)
        // QK_MODS hex: shift-left over KC_ENTER is 0x0228; the right-hand bit
        // (0x10 in the mods byte) moves it to 0x1228.
        XCTAssertEqual(decode("0x228").firmwareShiftSide, .left)
        XCTAssertEqual(decode("0x1228").firmwareShiftSide, .right)
        // A mod-tap taps unshifted, a plain key has no wrap, and a shortcut
        // carries no identity: none of them names a side.
        XCTAssertNil(decode("LSFT_T(KC_ENTER)").firmwareShiftSide)
        XCTAssertNil(decode("KC_A").firmwareShiftSide)
        XCTAssertNil(decode("C_S(KC_UP)").firmwareShiftSide)
        XCTAssertNil(decode("0xc16").firmwareShiftSide)
    }

    func testRawHexInTheBasicRangeMatchesTheNamedKeycode() {
        // 0x28 is KC_ENTER in the HID/QMK basic range.
        XCTAssertEqual(decode("0x28").identity, decode("KC_ENTER").identity)
        // 0x04 is KC_A.
        XCTAssertEqual(decode("0x04").identity, decode("KC_A").identity)
    }

    func testRawHexModTapAndLayerTapUseTheirOwnRanges() {
        // QK_MOD_TAP: 0x2000 | (MOD_LSFT << 8) | KC_ENTER == 0x2228.
        let modTap = decode("0x2228")
        XCTAssertEqual(modTap.identity, KeyIdentity(keyCode: 0x24, isShifted: false))
        XCTAssertEqual(modTap.holdAction?.identity, KeyIdentity(keyCode: 0x38))
        XCTAssertEqual(modTap.holdAction?.exclusion, .modifier)
        // QK_LAYER_TAP: 0x4000 | (layer 1 << 8) | KC_SPACE == 0x412C.
        let layerTap = decode("0x412c")
        XCTAssertEqual(layerTap.identity, KeyIdentity(keyCode: 0x31))
        XCTAssertNil(layerTap.exclusion)
    }

    // MARK: - Totality

    /// An unknown token has to be drawn honestly rather than guessed at, and
    /// must never take the process down mid-report.
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
        // A numeric entry is rewritten as hex before decoding, so a `0` in the
        // layout array — KC_NO written as a number — arrives as "0x0".
        XCTAssertTrue(decode("0x0").isAbsent)
        XCTAssertFalse(decode("KC_A").isAbsent)
    }

    /// Caps Lock reaches macOS as a flags-changed event like every other
    /// modifier, and the recorder counts it through that path. Leaving it
    /// unmarked drew an unannotated half-count.
    func testCapsLockIsMarkedAsAModifier() {
        XCTAssertEqual(decode("KC_CAPSLOCK").identity, KeyIdentity(keyCode: 0x39))
        XCTAssertEqual(decode("KC_CAPSLOCK").exclusion, .modifier)
    }

    /// On layer 0 there is nothing underneath for a transparent key to fall
    /// through to, so it is a cap with no action rather than a cap with no note.
    func testTransparentKeySaysWhyItIsBlank() {
        XCTAssertNil(decode("KC_TRNS").identity)
        XCTAssertEqual(decode("KC_TRNS").exclusion, .unmappedOnMacOS)
    }

    /// When a layer-tap's tap action is itself invisible to macOS, the inner
    /// key's reason is the useful one: `LT1(KC_MUTE)` is missing because it is a
    /// media key, and blaming the layer would send the reader looking in the
    /// wrong place.
    func testUnreachableLayerTapKeepsTheInnerReason() {
        XCTAssertEqual(decode("LT1(KC_MUTE)").exclusion, .media)
        XCTAssertEqual(decode("LT2(KC_BTN1)").exclusion, .mouse)
        XCTAssertEqual(decode("LT1(KC_APPLICATION)").exclusion, .unmappedOnMacOS)
        // A visible tap has no tap-side caveat unless the inner action itself
        // needs one; the invisible layer hold has its own action field.
        XCTAssertNil(decode("LT1(KC_SPACE)").exclusion)
        XCTAssertEqual(decode("LT2(KC_CAPSLOCK)").exclusion, .modifier)
        XCTAssertEqual(decode("LT2(KC_CAPSLOCK)").holdAction?.exclusion, .layerHold)
    }

    // MARK: - File parsing

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
        // The -1 entry still occupies a slot, or every column after it shifts.
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
