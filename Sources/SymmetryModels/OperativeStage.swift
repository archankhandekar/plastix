import Foundation

/// The operative stage a capture set documents. Presets cover common reconstruction
/// and symmetrization steps; `custom` holds any other label the team uses.
public enum OperativeStage: Codable, Hashable, Sendable {
    case preoperativeMarking
    case afterResection
    case afterImplantOrExpander
    case afterFatGrafting
    case afterClosure
    case custom(String)

    public static let presets: [OperativeStage] = [
        .preoperativeMarking, .afterResection, .afterImplantOrExpander, .afterFatGrafting, .afterClosure,
    ]

    public var label: String {
        switch self {
        case .preoperativeMarking: return "Preoperative marking"
        case .afterResection: return "After mastectomy or resection"
        case .afterImplantOrExpander: return "After implant or expander placement"
        case .afterFatGrafting: return "After fat grafting"
        case .afterClosure: return "After closure"
        case .custom(let text): return text
        }
    }
}

/// Positioning details recorded with every capture set so sets can be compared on equal terms.
public struct Positioning: Codable, Hashable, Sendable {
    public var tableAngle: String
    public var armPosition: String
    public var lighting: String
    public var note: String

    public init(tableAngle: String = "", armPosition: String = "", lighting: String = "", note: String = "") {
        self.tableAngle = tableAngle
        self.armPosition = armPosition
        self.lighting = lighting
        self.note = note
    }

    public var summary: String {
        let parts = [
            tableAngle.isEmpty ? nil : "Table \(tableAngle)",
            armPosition.isEmpty ? nil : "Arms \(armPosition)",
            lighting.isEmpty ? nil : "Light \(lighting)",
            note.isEmpty ? nil : note,
        ].compactMap { $0 }
        return parts.isEmpty ? "Positioning not recorded" : parts.joined(separator: ", ")
    }
}
