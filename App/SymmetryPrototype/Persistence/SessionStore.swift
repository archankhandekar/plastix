import Foundation
import SwiftUI
import SymmetryCore
import SymmetryModels

/// Observable front for `SessionRepository`, with an in-memory image cache.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [StudySession] = []
    @Published var lastError: String?

    private let repository: SessionRepository
    private let imageCache = NSCache<NSString, UIImage>()

    init(repository: SessionRepository) {
        self.repository = repository
        self.sessions = repository.loadAll()
        imageCache.countLimit = 24
    }

    convenience init() {
        let repo: SessionRepository
        do {
            repo = try SessionRepository(root: try SessionRepository.defaultRoot())
        } catch {
            // Fall back to a temporary directory rather than crash; surfaced in the UI.
            repo = try! SessionRepository(root: FileManager.default.temporaryDirectory.appendingPathComponent("Sessions"))
        }
        self.init(repository: repo)
    }

    func session(id: UUID) -> StudySession? { sessions.first { $0.id == id } }

    @discardableResult
    func create(studyID: String) throws -> StudySession {
        let session = StudySession(studyID: studyID)
        try repository.save(session)
        sessions.insert(session, at: 0)
        return session
    }

    /// Saves and returns false (with `lastError` set) when the write fails.
    @discardableResult
    func save(_ session: StudySession) -> Bool {
        do {
            try repository.save(session)
            if let i = sessions.firstIndex(where: { $0.id == session.id }) { sessions[i] = session } else { sessions.insert(session, at: 0) }
            return true
        } catch {
            lastError = "Could not save the session: \(error.localizedDescription)"
            return false
        }
    }

    func deleteImage(for capture: Capture, in session: StudySession) {
        do {
            try repository.deleteImage(for: capture, in: session)
        } catch {
            lastError = "Could not delete an image: \(error.localizedDescription)"
        }
        imageCache.removeObject(forKey: capture.imageFilename as NSString)
    }

    func delete(_ session: StudySession) {
        do {
            try repository.delete(session)
            sessions.removeAll { $0.id == session.id }
        } catch {
            lastError = "Could not delete the session: \(error.localizedDescription)"
        }
    }

    func deleteAll() {
        do {
            try repository.deleteAll()
            sessions.removeAll()
            imageCache.removeAllObjects()
        } catch {
            lastError = "Could not delete all sessions: \(error.localizedDescription)"
        }
    }

    func writeImage(_ data: Data, for capture: Capture, in session: StudySession) throws {
        try repository.writeImage(data, for: capture, in: session)
        imageCache.removeObject(forKey: capture.imageFilename as NSString)
    }

    func image(for capture: Capture, in session: StudySession) -> UIImage? {
        let key = capture.imageFilename as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let data = repository.readImage(for: capture, in: session), let image = UIImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    func imageURL(for capture: Capture, in session: StudySession) -> URL {
        repository.imageURL(for: capture, in: session)
    }
}
