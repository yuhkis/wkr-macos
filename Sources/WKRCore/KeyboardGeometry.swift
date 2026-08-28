import Foundation

/// A keyboard the report can draw the tally on.
///
/// The tally itself is layout-agnostic: it holds macOS virtual key codes, and
/// every one of these keyboards sends the same codes for the same letters. What
/// differs is where the key sits and what is printed on it, which is exactly
/// what a heatmap needs and exactly what these geometries supply.
public enum KeyboardModel: String, CaseIterable, Sendable, Codable {
    case jis
    case us
    case cornix

    public var displayName: String {
        switch self {
        case .jis: return "JIS (日本語配列)"
        case .us: return "US (ANSI)"
        case .cornix: return "Cornix (分割・列千鳥)"
        }
    }
}

/// What is printed on a key cap.
public struct KeyCapLegend: Equatable, Sendable, Codable {
    /// The unshifted legend, or the key's name (`Tab`, `⌘`).
    public let primary: String
    /// The shifted legend on a staggered board, or the hold action on a
    /// Corne-style board (`LT 1` over `Space`). `nil` when the key has one
    /// meaning only.
    public let secondary: String?

    public init(_ primary: String, _ secondary: String? = nil) {
        self.primary = primary
        self.secondary = secondary
    }
}

/// Why a key cap carries no number, so the picture can say so instead of
/// silently drawing it as unused.
///
/// A cold key is ambiguous on its own: it can mean "never pressed" or "cannot
/// be seen from here". Only the second is a property of the tool, and only the
/// second is worth annotating.
public enum KeyCapExclusion: String, Equatable, Sendable, Codable {
    /// A modifier that reaches macOS as a flags-changed event. Counted only
    /// when frequency logging is on, since that is what widens the event tap.
    case modifier
    /// A layer key whose hold never leaves the keyboard's own firmware. Only
    /// its tap action is visible to macOS, and that is filed under the tap.
    case layerHold
    /// A rotary encoder press or turn. These arrive as system-defined media
    /// events, not key events, so the event tap never sees them.
    case encoder
    /// A media or system key, for the same reason as `encoder`.
    case media
    /// A mouse button emulated by the keyboard. It arrives as a mouse event.
    case mouse
    /// A key whose only action carries Command, Control or Option. Those events
    /// are deliberately not counted; see `docs/design.md` section 9.
    case shortcut
    /// A key macOS has no virtual key code for, or one this decoder cannot
    /// resolve. The PC Menu key is the usual example: macOS never receives it,
    /// so nothing in a key event identifies it. Custom firmware keycodes
    /// (`USER00`, macros) land here too, because what they send is decided
    /// inside the keyboard and is not recoverable from the keymap.
    case unmappedOnMacOS
}

/// One drawn key.
///
/// Coordinates are in key units with the origin at the top left of the drawing,
/// x growing right and y growing down, so a standard 1u key is `1.0 × 1.0` and
/// the renderer only has to pick a pixel size for one unit.
public struct KeyCap: Equatable, Sendable, Codable {
    /// Unique within one `KeyboardGeometry`. Stable across releases so that a
    /// saved report and a new build agree on which cap is which.
    public let id: String
    /// Every counted identity that lands on this cap.
    ///
    /// More than one when a cap covers both shift states of a key that WKR
    /// treats as two (JIS `2` and `"`). Empty when the cap is not countable,
    /// in which case `exclusion` says why.
    ///
    /// The same identity may appear on several caps. A split keyboard can put
    /// Enter under three different fingers, and macOS receives one keycode from
    /// all of them, so the count is a shared total rather than a per-cap one.
    /// The renderer marks those caps instead of dividing the number up, because
    /// dividing would invent precision that does not exist.
    public let identities: [KeyIdentity]
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    /// Degrees clockwise about the cap's own centre. Only the Corne thumb keys
    /// use this.
    public let rotation: Double
    public let legend: KeyCapLegend
    public let exclusion: KeyCapExclusion?
    /// Which finger's column this belongs to, for the per-finger summary.
    public let finger: Finger?

    public enum Finger: String, Equatable, Sendable, Codable, CaseIterable {
        case leftPinky, leftRing, leftMiddle, leftIndex, leftThumb
        case rightThumb, rightIndex, rightMiddle, rightRing, rightPinky

        public var displayName: String {
            switch self {
            case .leftPinky: return "左小指"
            case .leftRing: return "左薬指"
            case .leftMiddle: return "左中指"
            case .leftIndex: return "左人差指"
            case .leftThumb: return "左親指"
            case .rightThumb: return "右親指"
            case .rightIndex: return "右人差指"
            case .rightMiddle: return "右中指"
            case .rightRing: return "右薬指"
            case .rightPinky: return "右小指"
            }
        }
    }

    public init(
        id: String,
        identities: [KeyIdentity] = [],
        x: Double,
        y: Double,
        width: Double = 1,
        height: Double = 1,
        rotation: Double = 0,
        legend: KeyCapLegend,
        exclusion: KeyCapExclusion? = nil,
        finger: Finger? = nil
    ) {
        self.id = id
        self.identities = identities
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.legend = legend
        self.exclusion = exclusion
        self.finger = finger
    }
}

public struct KeyboardGeometry: Equatable, Sendable, Codable {
    public let model: KeyboardModel
    public let displayName: String
    /// Drawing extent in key units, so the renderer can size its viewBox
    /// without walking the caps.
    public let widthUnits: Double
    public let heightUnits: Double
    public let caps: [KeyCap]
    /// Shown under the picture. Says what this particular drawing cannot know.
    public let caveats: [String]

    public init(
        model: KeyboardModel,
        displayName: String,
        widthUnits: Double,
        heightUnits: Double,
        caps: [KeyCap],
        caveats: [String] = []
    ) {
        self.model = model
        self.displayName = displayName
        self.widthUnits = widthUnits
        self.heightUnits = heightUnits
        self.caps = caps
        self.caveats = caveats
    }

    public static func builtIn(_ model: KeyboardModel) -> KeyboardGeometry {
        switch model {
        case .jis: return .jis
        case .us: return .us
        case .cornix: return .cornix
        }
    }

    public static let allBuiltIn: [KeyboardGeometry] = KeyboardModel.allCases.map(builtIn)
}
