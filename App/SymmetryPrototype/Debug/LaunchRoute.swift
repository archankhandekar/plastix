#if DEBUG
import Foundation
import SwiftUI
import SymmetryCore

/// The DEBUG route harness's launch arguments, parsed from `-Key value` pairs.
///
/// A launch with no `-UIRoute` is a normal launch (`parse` returns nil). Every other key is
/// optional and has a default. The harness never reads or writes real study data; see
/// `RouteHarness.makeEnvironment(_:)`. This file is compiled into Debug builds only.
struct LaunchRoute: Equatable {
    /// The 18 screens the harness can open.
    enum Name: String, CaseIterable, Equatable {
        case notice, sessions, home, tour, symmetry, obliques, stages, compare, capture, photocheck
        case review, mark, export, settings, explainer, newSession, newSet, gallery
    }

    /// What `-UIState` does to the seeded session before the route opens.
    enum SeedState: String, CaseIterable, Equatable {
        /// Sets 1 to 4 taken and marked from the ground truth.
        case complete
        /// The target set's frontal points removed.
        case unmarked
        /// The target set's patient left fold removed.
        case missingFold
        /// The target set's outlines cleared.
        case noOutlines
        /// The target set's frontal replaced by the blurred render, kept anyway, points kept.
        case blurredKept
    }

    var route: Name = .sessions
    /// Seed the virtual patient. Default true, except `sessions` with `-UISeedStudy 1`.
    var demo: Bool = true
    /// The raw `-UIDemo` value, when it was given. Decides whether a seeded study session
    /// is the target (`targetsStudy`).
    var demoArgument: Bool?
    /// Also seed the study session S-HARNESS in the temporary study root.
    var seedStudy: Bool = false
    /// researchNoticeAccepted in the harness suite. Default true except for `notice`.
    var skipNotice: Bool = true
    /// Which set the route opens (1-based). Defaults: mark 3, capture 4, otherwise 1.
    var stage: Int?
    var focus: PlateLayer = .all
    var state: SeedState?
    var showTruth: Bool = false
    var obliqueMode: ObliqueMode = .sideBySide
    var captureAngle: ViewAngle?
    var practiceRetake: Bool = false
    var studyCode: String?
    var scheme: ColorScheme?
    var textSize: DynamicTypeSize?
    var staticMotion: Bool = false

    /// The set the route opens, with the per-route default applied.
    var resolvedStage: Int {
        if let stage { return stage }
        switch route {
        case .mark: return 3
        case .capture: return 4
        default: return 1
        }
    }

    /// True when routes open the seeded study session instead of the virtual patient:
    /// `-UISeedStudy 1` without an explicit `-UIDemo 1`.
    var targetsStudy: Bool {
        seedStudy && demoArgument != true
    }

    /// Parses `-Key value` pairs. Returns nil without `-UIRoute`. Unknown values fall back
    /// to the key's default; an unknown route falls back to `sessions`.
    static func parse(_ args: [String]) -> LaunchRoute? {
        var values: [String: String] = [:]
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("-UI"), i + 1 < args.count {
                values[String(arg.dropFirst())] = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }
        guard let routeValue = values["UIRoute"] else { return nil }

        func flag(_ key: String) -> Bool? {
            guard let v = values[key]?.lowercased() else { return nil }
            switch v {
            case "1", "true", "yes", "on": return true
            case "0", "false", "no", "off": return false
            default: return nil
            }
        }

        var r = LaunchRoute()
        r.route = Name(rawValue: routeValue) ?? .sessions
        r.seedStudy = flag("UISeedStudy") ?? false
        r.demoArgument = flag("UIDemo")
        r.demo = r.demoArgument ?? !(r.route == .sessions && r.seedStudy)
        r.skipNotice = flag("UISkipNotice") ?? (r.route != .notice)
        if let s = values["UIStage"].flatMap(Int.init), (1...4).contains(s) { r.stage = s }
        r.focus = values["UIFocus"].flatMap(PlateLayer.init(rawValue:)) ?? .all
        r.state = values["UIState"].flatMap(SeedState.init(rawValue:))
        r.showTruth = flag("UIShowTruth") ?? false
        r.obliqueMode = values["UIObliqueMode"].flatMap(ObliqueMode.init(rawValue:)) ?? .sideBySide
        r.captureAngle = values["UICaptureAngle"].flatMap(ViewAngle.init(rawValue:))
        r.practiceRetake = flag("UIPracticeRetake") ?? false
        if let code = values["UIStudyCode"], !code.isEmpty { r.studyCode = code }
        switch values["UIScheme"]?.lowercased() {
        case "light": r.scheme = .light
        case "dark": r.scheme = .dark
        default: r.scheme = nil
        }
        r.textSize = values["UITextSize"].flatMap(textSize(named:))
        r.staticMotion = flag("UIStatic") ?? false
        return r
    }

    /// The launch arguments of this process, parsed.
    static var current: LaunchRoute? {
        parse(ProcessInfo.processInfo.arguments)
    }

    /// `large`, `xxxLarge`, `accessibility1` ... `accessibility5`, and the other
    /// DynamicTypeSize case names.
    static func textSize(named name: String) -> DynamicTypeSize? {
        switch name {
        case "xSmall": return .xSmall
        case "small": return .small
        case "medium": return .medium
        case "large": return .large
        case "xLarge": return .xLarge
        case "xxLarge": return .xxLarge
        case "xxxLarge": return .xxxLarge
        case "accessibility1": return .accessibility1
        case "accessibility2": return .accessibility2
        case "accessibility3": return .accessibility3
        case "accessibility4": return .accessibility4
        case "accessibility5": return .accessibility5
        default: return nil
        }
    }
}
#endif
