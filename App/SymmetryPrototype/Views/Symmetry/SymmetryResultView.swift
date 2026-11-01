import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// The left-right result of one photo set: the symmetry plate with its layers and gauges on
/// the Frontal tab, and the two obliques facing the patient on the Obliques tab.
///
/// It navigates only by appending `AppRoute` values to the `AppNavigator`.
struct SymmetryResultView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.sessionKind) private var kind
    @Environment(\.staticMotion) private var staticMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sessionID: UUID
    private let setID: UUID
    private let obliqueMode: ObliqueMode
    @State private var tab: SymmetryTab
    @State private var focus: PlateLayer

    private enum ScrollTarget: Hashable { case top, plate }

    init(sessionID: UUID, setID: UUID, tab: SymmetryTab = .frontal, focus: PlateLayer = .all,
         obliqueMode: ObliqueMode = .sideBySide) {
        self.sessionID = sessionID
        self.setID = setID
        self.obliqueMode = obliqueMode
        _tab = State(initialValue: tab)
        _focus = State(initialValue: focus)
    }

    private var ref: SessionRef { SessionRef(id: sessionID, kind: kind) }
    private var isPractice: Bool { kind == .practice }

    private var scrollAnimation: Animation? {
        staticMotion || reduceMotion ? nil : .easeInOut(duration: 0.3)
    }

    var body: some View {
        Group {
            if let session = store.session(id: sessionID), let set = session.captureSet(id: setID) {
                content(session: session, set: set)
            } else {
                ContentUnavailableView("Photo set not found", systemImage: "questionmark.folder")
            }
        }
        .background(Theme.Colors.tray)
        .practiceBand(isPractice)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UIFlags.markViewed(setID: setID)
            if tab == .obliques { UIFlags.markSeenObliques(sessionID: sessionID) }
        }
        .onChange(of: tab) { _, newTab in
            if newTab == .obliques { UIFlags.markSeenObliques(sessionID: sessionID) }
        }
    }

    // MARK: Screen

    private func content(session: StudySession, set: CaptureSet) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    SegmentedChoice([(value: SymmetryTab.frontal, title: "Frontal"),
                                     (value: SymmetryTab.obliques, title: "Obliques")],
                                    selection: $tab)
                        .id(ScrollTarget.top)

                    Text(SessionWizard.title(of: set, in: session))
                        .font(.screenTitle)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    switch tab {
                    case .frontal:
                        frontal(session: session, set: set, proxy: proxy)
                    case .obliques:
                        obliques(session: session, set: set)
                    }
                }
                .padding(.horizontal, Theme.Spacing.margin)
                .padding(.vertical, Theme.Spacing.m)
            }
            .safeAreaInset(edge: .bottom) {
                nextAction(session: session, proxy: proxy)
            }
            .onChange(of: tab) { _, _ in
                withAnimation(scrollAnimation) { proxy.scrollTo(ScrollTarget.top, anchor: .top) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Set photos") { navigator.push(.review(ref, setID: setID)) }
                    .font(.actionLabel)
                    .foregroundStyle(Theme.Colors.ink)
                    .frame(minWidth: Theme.tapTarget, minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private func nextAction(session: StudySession, proxy: ScrollViewProxy) -> some View {
        switch tab {
        case .frontal:
            NextActionBar(title: "Look at the obliques") { tab = .obliques }
        case .obliques:
            // This set is on screen, so it counts as viewed even before the flag is read back.
            let wizard = SessionWizard(session: session,
                                       settings: settings.reportSettings,
                                       kind: kind,
                                       viewedSetIDs: UIFlags.viewedSetIDs(in: session).union([setID]),
                                       hasOpenedStages: UIFlags.hasOpenedStages(sessionID: sessionID))
            let action = wizard.next
            NextActionBar(title: action.title) {
                if let route = action.route(ref) {
                    navigator.push(route)
                } else {
                    navigator.popToSession(ref, performNext: true)
                }
            }
        }
    }

    // MARK: Frontal tab

    @ViewBuilder
    private func frontal(session: StudySession, set: CaptureSet, proxy: ScrollViewProxy) -> some View {
        if let capture = set.frontal, let image = store.image(for: capture, in: session) {
            let reading = SetReading(landmarks: capture.landmarks, sigma: settings.landmarkSigmaRatio, frontal: capture)
            let markPoints = { navigator.push(.markPoints(ref, setID: setID, captureID: capture.id)) }

            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SymmetryPlate(image: image,
                                  landmarks: capture.landmarks ?? LandmarkSet(imageSize: capture.imageSize),
                                  reading: reading,
                                  focus: focus,
                                  practice: isPractice)
                        .id(ScrollTarget.plate)
                    supportText(reading.canTurn ? ReadingCopy.photoTurnedCaption : ReadingCopy.cannotTurnCaption)
                    SegmentedChoice(PlateLayer.allCases.map { (value: $0, title: $0.title) }, selection: $focus)
                    if let metric = BilateralMetric.allCases.first(where: { $0.layer == focus }) {
                        focusedReadout(reading.reading(metric))
                    }
                }

                gauges(reading: reading, proxy: proxy, markPoints: markPoints)

                if !reading.flagSentences.isEmpty {
                    flagStrip(reading.flagSentences)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    supportText(ReadingCopy.referenceCaption)
                    if isPractice {
                        supportText(ReadingCopy.practiceMidlineCaption)
                    }
                    supportText(MetricGlossary.provenanceLine)
                    supportText(MetricGlossary.sidesLine)
                }

                VStack(spacing: Theme.Spacing.s) {
                    Button("Mark points", action: markPoints)
                        .buttonStyle(SecondaryButtonStyle())
                    Button("What the numbers mean") { navigator.push(.explainer) }
                        .buttonStyle(SecondaryButtonStyle())
                }

                ResearchNoticeBanner(showsExplainerLink: false)
            }
        } else {
            ContentUnavailableView("Photo not available", systemImage: "photo")
                .frame(maxWidth: .infinity)
        }
    }

    /// The focused layer's title, its verbatim readout in the hero face, then its sentence or reason.
    private func focusedReadout(_ r: MetricReading) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(r.metric.title)
                .font(.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)
            Text(r.readout)
                .font(.readoutHero)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let sentence = r.sentence {
                Text(sentence)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let reason = r.notMeasuredReason {
                cautionLine(reason)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func gauges(reading: SetReading, proxy: ScrollViewProxy, markPoints: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gaugeGap) {
            ForEach([BilateralMetric.nippleHeight, .nippleMidline, .foldHeight]) { metric in
                let r = reading.reading(metric)
                LeanGauge(title: metric.title,
                          measurement: r.measurement,
                          patientRightEnd: metric.patientRightEnd ?? "",
                          patientLeftEnd: metric.patientLeftEnd ?? "",
                          sentence: r.sentence,
                          exportName: metric.exportName,
                          notMeasuredReason: r.notMeasuredReason,
                          isFocused: focus == metric.layer,
                          onSelect: { select(metric.layer, proxy: proxy) },
                          onMarkPoints: markPoints)
            }
            let overlap = reading.reading(.outlineOverlap)
            OverlapScale(measurement: overlap.measurement,
                         sentence: overlap.sentence,
                         exportName: BilateralMetric.outlineOverlap.exportName,
                         notMeasuredReason: overlap.notMeasuredReason,
                         isFocused: focus == .outlines,
                         onSelect: { select(.outlines, proxy: proxy) },
                         onMarkPoints: markPoints)
        }
    }

    /// Brings a layer forward and scrolls back up so its construction is in view.
    private func select(_ layer: PlateLayer, proxy: ScrollViewProxy) {
        focus = layer
        withAnimation(scrollAnimation) { proxy.scrollTo(ScrollTarget.plate, anchor: .top) }
    }

    private func flagStrip(_ sentences: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(sentences, id: \.self) { sentence in
                cautionLine(sentence)
            }
        }
    }

    private func cautionLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.body)
        .foregroundStyle(Theme.Colors.caution)
    }

    private func supportText(_ text: String) -> some View {
        Text(text)
            .font(.support)
            .foregroundStyle(Theme.Colors.graduation)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Obliques tab

    private func obliques(session: StudySession, set: CaptureSet) -> some View {
        ObliquePairView(rightOblique: set.captures[.rightOblique].flatMap { store.image(for: $0, in: session) },
                        leftOblique: set.captures[.leftOblique].flatMap { store.image(for: $0, in: session) },
                        mode: obliqueMode,
                        practice: isPractice)
    }
}
