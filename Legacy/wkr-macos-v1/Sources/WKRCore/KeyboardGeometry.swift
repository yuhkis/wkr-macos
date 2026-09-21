import Foundation

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

public struct KeyCapLegend: Equatable, Sendable, Codable {
    public let primary: String
    public let secondary: String?
    public let secondaryIsShifted: Bool

    public init(_ primary: String, _ secondary: String? = nil, secondaryIsShifted: Bool = true) {
        self.primary = primary
        self.secondary = secondary
        self.secondaryIsShifted = secondaryIsShifted
    }
}

public struct KeyCapActionPart: Equatable, Sendable, Codable {
    public let legend: String
    public let identities: [KeyIdentity]
    public let exclusion: KeyCapExclusion?

    public init(
        legend: String,
        identities: [KeyIdentity] = [],
        exclusion: KeyCapExclusion? = nil
    ) {
        self.legend = legend
        self.identities = identities
        self.exclusion = exclusion
    }
}

public struct KeyCapTapHold: Equatable, Sendable, Codable {
    public let tap: KeyCapActionPart
    public let hold: KeyCapActionPart

    public init(tap: KeyCapActionPart, hold: KeyCapActionPart) {
        self.tap = tap
        self.hold = hold
    }
}

public enum KeyCapExclusion: String, Equatable, Sendable, Codable {
    case modifier
    case layerHold
    case compoundModifierHold
    case encoder
    case media
    case mouse
    case shortcut
    case unmappedOnMacOS
}

public struct KeyCap: Equatable, Sendable, Codable {
    public let id: String
    public let identities: [KeyIdentity]
    public let tapHold: KeyCapTapHold?
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let rotation: Double
    public let legend: KeyCapLegend
    public let exclusion: KeyCapExclusion?
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
        tapHold: KeyCapTapHold? = nil,
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
        self.tapHold = tapHold
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
    public let widthUnits: Double
    public let heightUnits: Double
    public let caps: [KeyCap]
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
