import Foundation
import SymmetryCore

/// File-based storage for sessions. Foundation only, so it can be unit tested anywhere.
///
/// Layout: `<root>/Sessions/<session-uuid>/session.json` plus one JPEG per capture.
/// On iOS every file is written with complete file protection and the `Sessions`
/// directory is excluded from backups. Deletion removes the whole session directory.
public final class SessionRepository {
    public enum RepositoryError: Error { case missingDirectory }

    public let root: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Default location: Application Support/Sessions.
    public static func defaultRoot() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appendingPathComponent("Sessions", isDirectory: true)
    }

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try SessionRepository.excludeFromBackup(root)
    }

    public func sessionDirectory(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func imageURL(for capture: Capture, in session: StudySession) -> URL {
        sessionDirectory(session.id).appendingPathComponent(capture.imageFilename)
    }

    public func loadAll() -> [StudySession] {
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return dirs.compactMap { dir in
            let file = dir.appendingPathComponent("session.json")
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? decoder.decode(StudySession.self, from: data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    public func save(_ session: StudySession) throws {
        let dir = sessionDirectory(session.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(session)
        try SessionRepository.writeProtected(data, to: dir.appendingPathComponent("session.json"))
    }

    public func writeImage(_ data: Data, for capture: Capture, in session: StudySession) throws {
        let dir = sessionDirectory(session.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try SessionRepository.writeProtected(data, to: dir.appendingPathComponent(capture.imageFilename))
    }

    public func readImage(for capture: Capture, in session: StudySession) -> Data? {
        try? Data(contentsOf: imageURL(for: capture, in: session))
    }

    public func delete(_ session: StudySession) throws {
        let dir = sessionDirectory(session.id)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    /// Removes one capture's image file. Missing files are not an error.
    public func deleteImage(for capture: Capture, in session: StudySession) throws {
        let url = imageURL(for: capture, in: session)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Removes every entry under the root, including directories whose session file no
    /// longer decodes, so nothing survives "delete all".
    public func deleteAll() throws {
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for entry in entries { try FileManager.default.removeItem(at: entry) }
    }

    // MARK: - Protection

    static func writeProtected(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    static func excludeFromBackup(_ url: URL) throws {
        #if os(iOS)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
        #endif
    }
}
