import Foundation

extension KeyboardGeometry {
    public static let cornix = CornixLayout.builtIn.geometry()

    public static func cornix(keymap: VialKeymap) -> KeyboardGeometry {
        CornixLayout.builtIn.applying(keymap, layer: 0).geometry()
    }

    public static func cornixLayers(keymap: VialKeymap) -> [KeyboardGeometry] {
        var layerBoards: [KeyboardGeometry] = []
        for index in 1..<max(keymap.layers.count, 1) {
            let board = CornixLayout.blank.applying(keymap, layer: index).geometry(
                idSuffix: "-layer\(index)",
                displayName: "Cornix レイヤー\(index)",
                caveats: CornixMetrics.layerCaveats(index),
                includeShiftWrapCaveats: false
            )
            guard board.caps.contains(where: { !$0.identities.isEmpty }) else { continue }
            layerBoards.append(board)
        }
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

private struct CornixLayout {
    var leftMain: [[VialKeyAssignment]]
    var leftRow3: [VialKeyAssignment]
    var leftThumbs: [VialKeyAssignment]
    var leftEncoder: VialKeyAssignment
    var rightMain: [[VialKeyAssignment]]
    var rightRow3: [VialKeyAssignment]
    var rightThumbs: [VialKeyAssignment]
    var rightEncoder: VialKeyAssignment
    var keymapShiftWrapSides: Set<FirmwareShiftSide> = []

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

    func applying(_ keymap: VialKeymap, layer: Int) -> CornixLayout {
        var layout = self
        layout.keymapShiftWrapSides = keymap.firmwareShiftSides
        let rows = keymap.layers.indices.contains(layer) ? keymap.layers[layer] : []

        func entry(_ row: Int, _ index: Int) -> VialKeyAssignment? {
            guard rows.indices.contains(row) else { return nil }
            let entries = rows[row]
            guard entries.indices.contains(index) else { return nil }
            let assignment = entries[index]
            return assignment.raw.trimmingCharacters(in: .whitespacesAndNewlines) == "-1"
                ? nil
                : assignment
        }

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
                if let assignment = entry(4 + row, 5 - column) {
                    layout.rightMain[row][column] = assignment
                }
            }
        }
        if let assignment = encoder(in: 4..<8) {
            layout.rightEncoder = assignment
        }
        for position in 0..<3 {
            if let assignment = entry(7, 2 - position) {
                layout.rightRow3[position] = assignment
            }
        }
        for thumb in 0..<3 {
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

    private func shiftWrapCaveats() -> [String] {
        let assignments = leftMain.flatMap { $0 } + leftRow3 + leftThumbs
            + rightMain.flatMap { $0 } + rightRow3 + rightThumbs
        let sides = Set(assignments.compactMap(\.firmwareShiftSide))
            .union(keymapShiftWrapSides)
        var caveats: [String] = []
        if sides.contains(.left) {
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

private enum CornixMetrics {
    static let leftStagger: [Double] = [0, 0, 0.25, 0.5, 0.25, 0]

    static let rightStagger: [Double] = Array(leftStagger.reversed())

    static let rightInnerColumnX = 8.5

    static let leftThumbPositions: [(x: Double, y: Double, rotation: Double)] = [
        (3.51, 3.10, 0),
        (4.60, 3.18, 15),
        (5.63, 3.43, 30),
    ]

    static let rightThumbPositions: [(x: Double, y: Double, rotation: Double)] = [
        (9.99, 3.10, 0),
        (8.90, 3.18, -15),
        (7.87, 3.43, -30),
    ]

    static let leftEncoderCentre = (x: 6.00, y: 1.49)
    static let rightEncoderCentre = (x: 7.50, y: 1.49)

    static let xOrigin = 0.75
    static let yOrigin = 1.25

    static let widthUnits = 15.0

    static let heightUnits = 5.75

    static func leftFinger(column: Int) -> KeyCap.Finger? {
        switch column {
        case 0, 1: return .leftPinky
        case 2: return .leftRing
        case 3: return .leftMiddle
        case 4, 5: return .leftIndex
        default: return nil
        }
    }

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
            legend: KeyCapLegend(
                assignment.legend.primary,
                assignment.legend.secondary,
                secondaryIsShifted: false
            ),
            exclusion: assignment.exclusion,
            finger: assignment.exclusion == .modifier ? nil : finger
        )
    }

    private static func identities(for assignment: VialKeyAssignment) -> [KeyIdentity] {
        guard let identity = assignment.identity else { return [] }
        guard !identity.isShifted else { return [identity] }
        return [identity, KeyIdentity(keyCode: identity.keyCode, isShifted: true)]
    }

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

    static let multiLayerBaseCaveats = [
        "このタブはレイヤー0です。数えられるキーがあるレイヤーは、それぞれのタブにあります（マクロやメディアキーしか無いレイヤーはタブになりません）。",
        "レイヤーキーの hold はキーボードのファームウェア内で完結するため macOS には届きません。数えられるのは tap 側の動作だけです。",
        "ロータリーエンコーダの回転と押下は system-defined イベントで届くため、event tap では数えられません。",
        "同じキーコードを複数のキー（別のレイヤーを含む）が送る場合、macOS からはどれが押されたか区別できません。合算値を各キーに表示し、共有マークを付けます。",
        "Shift を押しながらの打鍵は、同じ物理キーの打鍵として同じキーに合算しています。Shift 付きと Shift なしの内訳はキーの詳細に出ます。",
        "⌘⌥ など Command / Control / Option を含むキーは、修飾キー付き入力を数えない方針のため数値を出しません。",
        "指ごとの集計は「その指が叩いた回数」です。修飾キーは押しっぱなしにするもので叩く回数とは性質が違うため、指の集計には入れていません（キーごとの数値には出ます）。",
    ]

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
