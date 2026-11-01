#if DEBUG
import Foundation
import SymmetryModels

/// DEBUG only: `-UITestReset 1` makes a normal launch start clean for UI tests.
///
/// Unlike the route harness, this keeps the real environment (the real stores, settings and
/// navigation). Before anything is built it wipes this app's standard UserDefaults (the
/// settings, the research notice and the UI flags) and empties both real store roots,
/// Application Support/Sessions and Application Support/Practice. A launch without the
/// argument is untouched. This file is compiled into Debug builds only.
@MainActor
enum UITestReset {
    static let argument = "-UITestReset"

    /// True when the process was launched with `-UITestReset 1` (or true/yes/on).
    static func isRequested(_ args: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        guard let i = args.firstIndex(of: argument), i + 1 < args.count else { return false }
        return ["1", "true", "yes", "on"].contains(args[i + 1].lowercased())
    }

    /// Wipes the defaults and both store roots when requested. Call before the stores exist.
    static func performIfRequested() {
        guard isRequested() else { return }
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        let fm = FileManager.default
        var roots: [URL] = []
        if let study = try? SessionRepository.defaultRoot() { roots.append(study) }
        if let practice = try? PracticeStore.defaultRoot() { roots.append(practice) }
        // The stores' fallbacks, in case an earlier launch could not reach Application Support.
        roots.append(fm.temporaryDirectory.appendingPathComponent("Sessions", isDirectory: true))
        roots.append(fm.temporaryDirectory.appendingPathComponent("Practice", isDirectory: true))
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for item in items { try? fm.removeItem(at: item) }
        }
    }
}
#endif
