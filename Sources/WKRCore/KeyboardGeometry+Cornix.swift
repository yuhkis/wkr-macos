import Foundation

/// A split, column-staggered Corne-style board.
///
/// The positions were measured off Vial's layout view of a real board rather
/// than off a Corne schematic, because the report will be held up next to that
/// window and any disagreement would read as a bug in the report. Every
/// position is given as a cap centre: a thumb key turned 30° has no meaningful
/// corner until the rotation is applied, and the centre is the one point a
/// rotation leaves alone.
extension KeyboardGeometry {
    /// The generic default layout, drawn when no `.vil` is supplied.
    public static let cornix = CornixLayout.builtIn.geometry()

    /// The same physical board relabelled from a Vial export.
    ///
    /// The geometry never comes from the file. A `.vil` records what each matrix
    /// position does, not where that position sits on the board, so the legends
    /// and the identities are the only things worth taking from it.
    public static func cornix(keymap: VialKeymap) -> KeyboardGeometry {
        CornixLayout.builtIn.applying(keymap, layer: 0).geometry()
    }

    /// The board once per layer that has anything countable on it.
    ///
    /// The first board is layer 0 exactly as `cornix(keymap:)` draws it, except
    /// for the caveat that used to say the other layers are invisible — they no
    /// longer are. Every further layer is drawn from the `.vil` alone, with no
    /// built-in fallback: a hole in a higher layer means "this key does nothing
    /// here", and filling it with the layer-0 default would draw a legend the
    /// firmware does not have.
    ///
    /// macOS still never learns which layer a key event came through. What
    /// keeps these boards honest is uniqueness, not attribution: an identity
    /// that exists at one position across all layers belongs to that cap, and
    /// one that exists at several is drawn at each with the shared total and
    /// the shared marker, exactly as a duplicated Enter already is on layer 0.
    public static func cornixLayers(keymap: VialKeymap) -> [KeyboardGeometry] {
        var layerBoards: [KeyboardGeometry] = []
        for index in 1..<max(keymap.layers.count, 1) {
            let board = CornixLayout.blank.applying(keymap, layer: index).geometry(
                idSuffix: "-layer\(index)",
                displayName: "Cornix レイヤー\(index)",
                caveats: CornixMetrics.layerCaveats(index),
                includeShiftWrapCaveats: false
            )
            // A layer nothing can be counted on is firmware bookkeeping, not a
            // picture. Vial exports every slot the firmware has, and this
            // project's own board carries six empty layers.
            guard board.caps.contains(where: { !$0.identities.isEmpty }) else { continue }
            layerBoards.append(board)
        }
        // The base board's caveats are chosen after the filter, not before: a
        // keymap that only populates layer 0 gets exactly one tab, and telling
        // its reader the other layers have tabs of their own would point at
        // tabs that do not exist. The single-board wording is the accurate one
        // there.
        let base = CornixLayout.builtIn.applying(keymap, layer: 0).geometry(
            displayName: KeyboardModel.cornix.displayName,
            caveats: layerBoards.isEmpty
                ? CornixMetrics.caveats
                : CornixMetrics.multiLayerBaseCaveats,
            includeShiftWrapCaveats: true
        )
        return [base] + layerBoards
    }
}

/// One assignment per drawn position, held in drawing order.
///
/// The built-in default and a parsed `.vil` both become one of these before
/// anything is placed, so the two paths cannot drift: there is a single set of
/// coordinates, a single finger table, and a single place where a cap is built.
private struct CornixLayout {
    /// Left half, three rows of six, outer pinky column first.
    var leftMain: [[VialKeyAssignment]]
    /// The three keys the left half keeps in its bottom row's grid, at columns 0...2.
    var leftRow3: [VialKeyAssignment]
    /// Left thumb cluster, outer to inner: the key nearest the pinky side first.
    var leftThumbs: [VialKeyAssignment]
    var leftEncoder: VialKeyAssignment
    /// Right half, three rows of six, stored inner index first so the array
    /// index is the drawn column. A `.vil` stores these rows the other way
    /// round; `applying(_:)` is the one place that gets undone.
    var rightMain: [[VialKeyAssignment]]
    /// Right bottom-row grid in drawn order, x = 11.5, 12.5, 13.5.
    var rightRow3: [VialKeyAssignment]
    /// Right thumb cluster, outer to inner, mirroring `leftThumbs`.
    var rightThumbs: [VialKeyAssignment]
    var rightEncoder: VialKeyAssignment
    /// Shift-wrap sides from every layer of the source keymap, not just the
    /// drawn one. Empty for the built-in default, whose single layer the
    /// layer-0 scan in `shiftWrapCaveats()` already covers.
    var keymapShiftWrapSides: Set<FirmwareShiftSide> = []

    /// The generic default this project defines: the QMK crkbd default layer
    /// with 英数 and かな placed beside Space and Enter, because this app
    /// exists to drive Apple日本語入力 and a picture without its two gate keys
    /// would hide the point. It is nobody's real keymap. The bottom-row grid
    /// keys vary too much between builds to guess at, so they stay blank until
    /// a `.vil` fills them in.
    ///
    /// Written as the same QMK tokens a `.vil` carries, and decoded by the same
    /// decoder, so the default and an imported layout can never disagree about
    /// what `KC_LANG2` is called or which identity it counts under.
    static let builtIn = CornixLayout(
        leftMain: [
            decoded("KC_TAB", "KC_Q", "KC_W", "KC_E", "KC_R", "KC_T"),
            decoded("KC_LCTRL", "KC_A", "KC_S", "KC_D", "KC_F", "KC_G"),
            decoded("KC_LSHIFT", "KC_Z", "KC_X", "KC_C", "KC_V", "KC_B"),
        ],
        leftRow3: decoded("KC_NO", "KC_NO", "KC_NO"),
        leftThumbs: decoded("KC_LGUI", "KC_LANG2", "KC_SPACE"),
        leftEncoder: VialKeymap.decode(token: "KC_MUTE"),
        rightMain: [
            decoded("KC_Y", "KC_U", "KC_I", "KC_O", "KC_P", "KC_BSPACE"),
            decoded("KC_H", "KC_J", "KC_K", "KC_L", "KC_SCOLON", "KC_QUOTE"),
            decoded("KC_N", "KC_M", "KC_COMMA", "KC_DOT", "KC_SLASH", "KC_ESCAPE"),
        ],
        rightRow3: decoded("KC_NO", "KC_NO", "KC_NO"),
        rightThumbs: decoded("KC_RALT", "KC_LANG1", "KC_ENTER"),
        rightEncoder: VialKeymap.decode(token: "KC_MUTE")
    )

    private static func decoded(_ tokens: String...) -> [VialKeyAssignment] {
        tokens.map(VialKeymap.decode(token:))
    }

    /// Every position empty. The receiver for higher layers, where a missing
    /// entry means "sends nothing" and must stay blank rather than inherit the
    /// layer-0 default.
    static let blank: CornixLayout = {
        let none = VialKeymap.decode(token: "KC_NO")
        let row = [VialKeyAssignment](repeating: none, count: 6)
        return CornixLayout(
            leftMain: [row, row, row],
            leftRow3: [none, none, none],
            leftThumbs: [none, none, none],
            leftEncoder: none,
            rightMain: [row, row, row],
            rightRow3: [none, none, none],
            rightThumbs: [none, none, none],
            rightEncoder: none
        )
    }()

    /// Lay a parsed `.vil` over the built-in default.
    ///
    /// Every read is bounds-checked and every miss keeps the default cap. Being
    /// handed a short file, or one exported from a different Corne revision, is
    /// an ordinary thing rather than an error: relabelling what is there and
    /// leaving the rest alone gives the user a usable picture, where trapping
    /// would take the whole report down over one key they do not have.
    func applying(_ keymap: VialKeymap, layer: Int) -> CornixLayout {
        var layout = self
        layout.keymapShiftWrapSides = keymap.firmwareShiftSides
        let rows = keymap.layers.indices.contains(layer) ? keymap.layers[layer] : []

        func entry(_ row: Int, _ index: Int) -> VialKeyAssignment? {
            guard rows.indices.contains(row) else { return nil }
            let entries = rows[row]
            guard entries.indices.contains(index) else { return nil }
            let assignment = entries[index]
            // Vial writes -1 for a matrix position the exporting board does not
            // have. Every position drawn here exists on the board this geometry
            // was measured from, so -1 means the file describes a different
            // revision, and the built-in cap is a better guess than a blank one.
            //
            // `KC_NO` is the opposite case and must not share this branch: the
            // position exists and the user has deliberately blanked it. Falling
            // back to the built-in would draw a legend they removed, over a live
            // count belonging to whatever else on the board sends that code.
            return assignment.raw.trimmingCharacters(in: .whitespacesAndNewlines) == "-1"
                ? nil
                : assignment
        }

        // The seventh slot of any row in the half, whichever one the board put
        // it in. `nil` when the half has no encoder at all.
        func encoder(in rows: Range<Int>) -> VialKeyAssignment? {
            rows.lazy.compactMap { entry($0, 6) }.first { !$0.isAbsent }
        }

        for row in 0..<3 {
            for column in 0..<6 {
                if let assignment = entry(row, column) {
                    layout.leftMain[row][column] = assignment
                }
            }
        }
        // Vial has nowhere else to put an encoder, so it rides along in the
        // seventh slot of one of the half's rows — but not the same row on both
        // halves, because that slot follows the matrix wiring rather than the
        // picture. The board this was measured from carries the left encoder on
        // its row 2 and the right on its row 1. Scanning for it costs three
        // lookups and survives a board that wires it somewhere else again.
        if let assignment = encoder(in: 0..<4) {
            layout.leftEncoder = assignment
        }
        for column in 0..<3 {
            if let assignment = entry(3, column) {
                layout.leftRow3[column] = assignment
            }
        }
        for thumb in 0..<3 {
            if let assignment = entry(3, 3 + thumb) {
                layout.leftThumbs[thumb] = assignment
            }
        }

        for row in 0..<3 {
            for column in 0..<6 {
                // The file walks the right half outer column first; the drawing
                // runs inner to outer, so the six entries are read backwards.
                // The encoder in slot 6 is deliberately outside this reversal.
                if let assignment = entry(4 + row, 5 - column) {
                    layout.rightMain[row][column] = assignment
                }
            }
        }
        if let assignment = encoder(in: 4..<8) {
            layout.rightEncoder = assignment
        }
        for position in 0..<3 {
            // Same reversal for the bottom row: the file's first entry is the
            // outer key at x = 13.5.
            if let assignment = entry(7, 2 - position) {
                layout.rightRow3[position] = assignment
            }
        }
        for thumb in 0..<3 {
            // Thumbs are not reversed. Vial stores both clusters outer-most
            // first, which is already the order these three positions are in.
            if let assignment = entry(7, 3 + thumb) {
                layout.rightThumbs[thumb] = assignment
            }
        }
        return layout
    }

    func geometry(
        idSuffix: String = "",
        displayName: String = KeyboardModel.cornix.displayName,
        caveats: [String] = CornixMetrics.caveats,
        includeShiftWrapCaveats: Bool = true
    ) -> KeyboardGeometry {
        var caps: [KeyCap] = []
        // Cap ids only need to be unique within one geometry, but a debugging
        // session with six boards open is easier when a layer-1 cap says so.
        func capID(_ base: String) -> String { base + idSuffix }

        for row in 0..<3 {
            for column in 0..<6 {
                caps.append(CornixMetrics.cap(
                    id: capID("cornix-l-r\(row)-c\(column)"),
                    assignment: leftMain[row][column],
                    centreX: Double(column),
                    centreY: Double(row) - CornixMetrics.leftStagger[column],
                    finger: CornixMetrics.leftFinger(column: column)
                ))
            }
        }
        for column in 0..<3 {
            caps.append(CornixMetrics.cap(
                id: capID("cornix-l-r3-c\(column)"),
                assignment: leftRow3[column],
                centreX: Double(column),
                centreY: 3 - CornixMetrics.leftStagger[column],
                // A bottom-row grid key sits under the same finger as the
                // column above it. Only the three turned caps are thumb keys.
                finger: CornixMetrics.leftFinger(column: column)
            ))
        }
        for (index, position) in CornixMetrics.leftThumbPositions.enumerated() {
            caps.append(CornixMetrics.cap(
                id: capID("cornix-l-thumb\(index)"),
                assignment: leftThumbs[index],
                centreX: position.x,
                centreY: position.y,
                rotation: position.rotation,
                finger: .leftThumb
            ))
        }
        caps.append(CornixMetrics.encoderCap(
            id: capID("cornix-l-encoder"),
            assignment: leftEncoder,
            centreX: CornixMetrics.leftEncoderCentre.x,
            centreY: CornixMetrics.leftEncoderCentre.y
        ))

        for row in 0..<3 {
            for column in 0..<6 {
                caps.append(CornixMetrics.cap(
                    id: capID("cornix-r-r\(row)-c\(column)"),
                    assignment: rightMain[row][column],
                    centreX: CornixMetrics.rightInnerColumnX + Double(column),
                    centreY: Double(row) - CornixMetrics.rightStagger[column],
                    finger: CornixMetrics.rightFinger(column: column)
                ))
            }
        }
        for position in 0..<3 {
            // The right half's bottom row mirrors the left's, so it lands on
            // the three outermost columns rather than the innermost three.
            let column = 3 + position
            caps.append(CornixMetrics.cap(
                id: capID("cornix-r-r3-c\(column)"),
                assignment: rightRow3[position],
                centreX: CornixMetrics.rightInnerColumnX + Double(column),
                centreY: 3 - CornixMetrics.rightStagger[column],
                finger: CornixMetrics.rightFinger(column: column)
            ))
        }
        for (index, position) in CornixMetrics.rightThumbPositions.enumerated() {
            caps.append(CornixMetrics.cap(
                id: capID("cornix-r-thumb\(index)"),
                assignment: rightThumbs[index],
                centreX: position.x,
                centreY: position.y,
                rotation: position.rotation,
                finger: .rightThumb
            ))
        }
        caps.append(CornixMetrics.encoderCap(
            id: capID("cornix-r-encoder"),
            assignment: rightEncoder,
            centreX: CornixMetrics.rightEncoderCentre.x,
            centreY: CornixMetrics.rightEncoderCentre.y
        ))

        return KeyboardGeometry(
            model: .cornix,
            displayName: displayName,
            widthUnits: CornixMetrics.widthUnits,
            heightUnits: CornixMetrics.heightUnits,
            caps: caps,
            caveats: caveats + (includeShiftWrapCaveats ? shiftWrapCaveats() : [])
        )
    }

    /// Notes that only apply when this particular keymap wraps Shift into a
    /// tap, written per side because the two sides mean opposite things.
    ///
    /// A wrap presses the side's Shift exactly the way a finger does, and no
    /// bit in the event tells the two apart, so the side's modifier count stops
    /// meaning "the physical Shift key was struck". The way out is physical:
    /// keep the wraps on the hand whose Shift key the board does not have, and
    /// the two counts separate at the key-code level. These lines exist so the
    /// picture says which reading applies to the keymap actually drawn, rather
    /// than making every reader carry the rule in their head.
    private func shiftWrapCaveats() -> [String] {
        // The layer-0 scan stays even though a parsed keymap already carries
        // its own all-layer set: the built-in default has no keymap behind it,
        // and a hand-built layout must not lose its note by bypassing parse().
        let assignments = leftMain.flatMap { $0 } + leftRow3 + leftThumbs
            + rightMain.flatMap { $0 } + rightRow3 + rightThumbs
        let sides = Set(assignments.compactMap(\.firmwareShiftSide))
            .union(keymapShiftWrapSides)
        var caveats: [String] = []
        if sides.contains(.left) {
            // Phrased conditionally on purpose: the scanner sees that the
            // keys exist, not whether the user reaches them, and a stale
            // layer's wraps must not turn this into a false accusation.
            caveats.append(
                "いずれかのレイヤーに、タップ自体が左Shiftを押すキー（LSft ラップ）があります。"
                    + "そのキーを打った分だけ、左Shiftの計数は物理的に左Shiftキーを叩いた回数"
                    + "から乖離します。ラップを RSft に変えると、キーコードの段階で分離できます。"
            )
        }
        if sides.contains(.right) {
            caveats.append(
                "いずれかのレイヤーに、タップ自体が右Shiftを押すキー（RSft ラップ）があります。"
                    + "右Shiftの計数はそのラップを打った回数の目安になります。"
            )
        }
        return caveats
    }
}

/// Where every cap sits, and the arithmetic that turns a measured centre into
/// the top-left corner `KeyCap` stores.
private enum CornixMetrics {
    /// How far each column of the left half is lifted, outer column first. The
    /// middle finger's column sits half a unit high and its two neighbours a
    /// quarter, which is the stagger that makes the three long fingers land on
    /// their home keys without curling.
    static let leftStagger: [Double] = [0, 0, 0.25, 0.5, 0.25, 0]

    /// The right half is the same PCB flipped over, and this array is stored
    /// inner column first, so its stagger is literally the left half's read
    /// backwards. Deriving it rather than retyping it keeps the halves mirrored
    /// if the measurement is ever corrected.
    static let rightStagger: [Double] = Array(leftStagger.reversed())

    /// The two halves are mirrored about x = 6.75, which puts the left half's
    /// outer column (x = 0) at x = 13.5 and its inner column (x = 5) here.
    static let rightInnerColumnX = 8.5

    /// Left thumb cluster centres, outer to inner. Each key steps further in,
    /// a little lower, and another 15° round, so the thumb travels an arc
    /// instead of a straight line.
    static let leftThumbPositions: [(x: Double, y: Double, rotation: Double)] = [
        (3.51, 3.10, 0),
        (4.60, 3.18, 15),
        (5.63, 3.43, 30),
    ]

    /// The mirror of `leftThumbPositions`: same offsets from the centre line,
    /// same tilt turned the other way.
    static let rightThumbPositions: [(x: Double, y: Double, rotation: Double)] = [
        (9.99, 3.10, 0),
        (8.90, 3.18, -15),
        (7.87, 3.43, -30),
    ]

    static let leftEncoderCentre = (x: 6.00, y: 1.49)
    static let rightEncoderCentre = (x: 7.50, y: 1.49)

    /// The measured centres put the top-left corner of the drawing at
    /// (-0.5, -1.0): x = 0 is the outer column's centre, and the middle column
    /// is lifted half a unit above row 0. `KeyCap` documents its origin as the
    /// top left of the drawing, so the whole board is shifted by this much and
    /// given a 0.25u margin. Shifting every cap by one constant leaves the
    /// layout being compared against the Vial window untouched.
    static let xOrigin = 0.75
    static let yOrigin = 1.25

    /// 14.5u from the outer edge of one pinky column to the other, plus the
    /// 0.25u margin on each side.
    static let widthUnits = 15.0

    /// The lowest drawn point is the bottom corner of the inner thumb key, not
    /// its centre: rotating a 1u cap by 30° pushes its corner (cos30 + sin30)/2
    /// = 0.683u below the centre, so 3.43 + 1.25 + 0.683 = 5.36. 5.75 leaves a
    /// little under 0.4u under it.
    static let heightUnits = 5.75

    /// A Corne gives the index and the little finger two columns each, so six
    /// columns are not six fingers. Columns 0 and 1 both belong to the little
    /// finger — the outer one is a reach, not a sixth finger — and columns 4
    /// and 5 both belong to the index finger.
    static func leftFinger(column: Int) -> KeyCap.Finger? {
        switch column {
        case 0, 1: return .leftPinky
        case 2: return .leftRing
        case 3: return .leftMiddle
        case 4, 5: return .leftIndex
        default: return nil
        }
    }

    /// The right half's columns are stored inner first, so column `column` is
    /// the mirror of the left half's column `5 - column`.
    static func rightFinger(column: Int) -> KeyCap.Finger? {
        switch leftFinger(column: 5 - column) {
        case .leftPinky: return .rightPinky
        case .leftRing: return .rightRing
        case .leftMiddle: return .rightMiddle
        case .leftIndex: return .rightIndex
        default: return nil
        }
    }

    static func cap(
        id: String,
        assignment: VialKeyAssignment,
        centreX: Double,
        centreY: Double,
        rotation: Double = 0,
        finger: KeyCap.Finger?
    ) -> KeyCap {
        let tapIdentities = identities(for: assignment)
        let tapHold: KeyCapTapHold?
        var allIdentities = tapIdentities
        if let hold = assignment.holdAction {
            let holdIdentities = hold.identity.map { [$0] } ?? []
            for identity in holdIdentities where !allIdentities.contains(identity) {
                allIdentities.append(identity)
            }
            tapHold = KeyCapTapHold(
                tap: KeyCapActionPart(
                    legend: assignment.legend.primary,
                    identities: tapIdentities,
                    // A countable tap can still need a caveat: Caps Lock is
                    // counted through flags-changed rather than keyDown.
                    exclusion: assignment.exclusion
                ),
                hold: KeyCapActionPart(
                    legend: hold.legend,
                    identities: holdIdentities,
                    exclusion: hold.exclusion
                )
            )
        } else {
            tapHold = nil
        }

        return KeyCap(
            id: id,
            identities: allIdentities,
            tapHold: tapHold,
            x: centreX - 0.5 + xOrigin,
            y: centreY - 0.5 + yOrigin,
            rotation: rotation,
            // A `.vil` legend's second line is always a hold or wrap label
            // (`LT 1`, `LAlt_T`, `RSft`), never what Shift+key prints, so the
            // flag is cleared here for every cap on the board. Without it the
            // renderer used "LAlt_T" as the display name of Shift+Enter.
            legend: KeyCapLegend(
                assignment.legend.primary,
                assignment.legend.secondary,
                secondaryIsShifted: false
            ),
            exclusion: assignment.exclusion,
            // A modifier sits in a finger's column but is held rather than
            // struck, and the per-finger table answers "how much is this finger
            // striking". Folding holds into it would put the pinkies at the top
            // of every board and make the figure incomparable to the other two
            // geometries, which keep modifiers out of it for the same reason.
            finger: assignment.exclusion == .modifier ? nil : finger
        )
    }

    /// Everything this cap can send.
    ///
    /// Usually one identity, because a Corne key has one legend on the layer
    /// being drawn. The exception is Shift, which is a physical fact rather than
    /// a keymap entry: holding Shift and striking the `A` key sends a shifted
    /// `A` from that same key, so a cap whose keymap action is unshifted claims
    /// the shifted variant too. Without this the whole symbol layer — every
    /// `Shift+;`, `Shift+/`, `Shift+,` the user reaches for — is recorded and
    /// then drawn nowhere, and the board silently under-reports its own pinky
    /// columns.
    ///
    /// A cap whose action is already shifted, such as `LSFT(KC_ENTER)`, is left
    /// alone: that key sends Shift+Return and nothing else, so claiming the
    /// plain Return as well would take a number off the keys that do send it.
    ///
    /// The reverse relation — one identity on several caps — is normal here and
    /// is left for the renderer to mark, because this table has no way to tell
    /// which Enter was pressed.
    private static func identities(for assignment: VialKeyAssignment) -> [KeyIdentity] {
        guard let identity = assignment.identity else { return [] }
        guard !identity.isShifted else { return [identity] }
        return [identity, KeyIdentity(keyCode: identity.keyCode, isShifted: true)]
    }

    /// An encoder cap, which is never countable whatever the keymap puts on it.
    ///
    /// Both the turn and the press reach macOS as system-defined events rather
    /// than key events, so the event tap never sees them. Taking the identity
    /// from the assignment would draw a number that is always zero and read as
    /// "you never used it".
    static func encoderCap(
        id: String,
        assignment: VialKeyAssignment,
        centreX: Double,
        centreY: Double
    ) -> KeyCap {
        KeyCap(
            id: id,
            identities: [],
            x: centreX - 0.5 + xOrigin,
            y: centreY - 0.5 + yOrigin,
            legend: assignment.legend,
            exclusion: .encoder,
            finger: nil
        )
    }

    /// What this particular picture cannot know. Longer than the staggered
    /// boards' lists because a programmable split keyboard hides more of itself
    /// from macOS than a board whose keys each send one code.
    /// The layer-0 board's caveats when the other layers are drawn beside it.
    /// The single-board list below says the higher layers are invisible, which
    /// stops being true the moment they get tabs of their own.
    static let multiLayerBaseCaveats = [
        "このタブはレイヤー0です。数えられるキーがあるレイヤーは、それぞれのタブにあります（マクロやメディアキーしか無いレイヤーはタブになりません）。",
        "レイヤーキーの hold はキーボードのファームウェア内で完結するため macOS には届きません。数えられるのは tap 側の動作だけです。",
        "ロータリーエンコーダの回転と押下は system-defined イベントで届くため、event tap では数えられません。",
        "同じキーコードを複数のキー（別のレイヤーを含む）が送る場合、macOS からはどれが押されたか区別できません。合算値を各キーに表示し、共有マークを付けます。",
        "Shift を押しながらの打鍵は、同じ物理キーの打鍵として同じキーに合算しています。Shift 付きと Shift なしの内訳はキーの詳細に出ます。",
        "⌘⌥ など Command / Control / Option を含むキーは、修飾キー付き入力を数えない方針のため数値を出しません。",
        "指ごとの集計は「その指が叩いた回数」です。修飾キーは押しっぱなしにするもので叩く回数とは性質が違うため、指の集計には入れていません（キーごとの数値には出ます）。",
    ]

    /// What a layer board needs the reader to know, which is mostly what it
    /// cannot know: the layer a key event came through is not in the event.
    static func layerCaveats(_ index: Int) -> [String] {
        [
            "レイヤー\(index)の割り当てです。macOS はどのレイヤー経由で届いたかを報告しないため、"
                + "同じキーコードがほかのレイヤー（レイヤー0を含む）にもあるキーは合算値で、共有マークが付きます。"
                + "このレイヤーにしか無いキーの数値は、このレイヤーで打った回数そのものです。",
            "空欄はこのレイヤーで何も送らない位置です。▽ は下のレイヤーへ抜ける割り当てで、"
                + "その打鍵は抜け先のキーとして数えられています。",
            "⌘ や ⌃ を含むキー、エンコーダ、修飾キーの扱いはレイヤー0のタブの注記のとおりです。",
        ]
    }

    static let caveats = [
        "レイヤーキーの hold はキーボードのファームウェア内で完結するため macOS には届きません。数えられるのは tap 側の動作だけです。",
        "描いているのはレイヤー0だけです。レイヤーを重ねて出した記号や数字は、同じキーコードを持つレイヤー0のキーに合算されます。レイヤー0に同じキーコードがなければ、どのキーにも現れません。",
        "ロータリーエンコーダの回転と押下は system-defined イベントで届くため、event tap では数えられません。",
        "Enter や Bksp を複数のキーに割り当てている場合、macOS からはどのキーが押されたか区別できません。合算値を各キーに表示します。",
        "Shift を押しながらの打鍵は、同じ物理キーの打鍵として同じキーに合算しています。Shift 付きと Shift なしの内訳はキーの詳細に出ます。",
        "⌘⌥ など Command / Control / Option を含むキーは、修飾キー付き入力を数えない方針のため数値を出しません。",
        "指ごとの集計は「その指が叩いた回数」です。修飾キーは押しっぱなしにするもので叩く回数とは性質が違うため、指の集計には入れていません（キーごとの数値には出ます）。",
    ]
}
