import Foundation
import SymmetryCore

/// One study participant's session. The only identifier is the non-identifying study ID.
public struct StudySession: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var studyID: String
    public let createdAt: Date
    public var notes: String
    public var captureSets: [CaptureSet]

    public init(id: UUID = UUID(), studyID: String, createdAt: Date = Date(), notes: String = "", captureSets: [CaptureSet] = []) {
        self.id = id
        self.studyID = studyID
        self.createdAt = createdAt
        self.notes = notes
        self.captureSets = captureSets
    }

    public static let maxStudyIDLength = 16

    /// Letters, digits and dashes only, 1 to 16 characters. Keeps names, dates and record
    /// numbers out of the one free-text identifier.
    public static func validateStudyID(_ raw: String) -> Result<String, StudyIDError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.count <= maxStudyIDLength else { return .failure(.tooLong) }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return .failure(.invalidCharacters) }
        return .success(trimmed)
    }

    public enum StudyIDError: Error, Equatable {
        case empty, tooLong, invalidCharacters

        public var message: String {
            switch self {
            case .empty: return "Enter a study ID."
            case .tooLong: return "Use at most \(StudySession.maxStudyIDLength) characters."
            case .invalidCharacters: return "Use letters, digits and dashes only. No names or record numbers."
            }
        }
    }

    public var orderedCaptureSets: [CaptureSet] { captureSets.sorted { $0.createdAt < $1.createdAt } }

    public func captureSet(id: UUID) -> CaptureSet? { captureSets.first { $0.id == id } }

    public mutating func update(_ set: CaptureSet) {
        if let i = captureSets.firstIndex(where: { $0.id == set.id }) { captureSets[i] = set } else { captureSets.append(set) }
    }
}
