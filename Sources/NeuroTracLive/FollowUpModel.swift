import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NeuroTracCore

/// Working folder: Documents/NeuroTracLive (CSV, logs); the follow-up data is in the “Suivi” subfolder.
enum AppFolders {
    static var data: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("NeuroTracLive", isDirectory: true)
    }
    static var follow: URL { return data.appendingPathComponent("Suivi", isDirectory: true) }
    static var reports: URL { return data.appendingPathComponent("Rapports", isDirectory: true) }
}

/// A chart point for Swift Charts.
struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let side: String
}

/// A point of a session's curves (EMG or stimulation), in minutes since the start.
struct PreviewPoint: Identifiable {
    let id: Int
    let minutes: Double
    let name: String
    let value: Double
}

/// Patient sheet, history, thresholds, observations, EMG tests, progression and PDF reports.
final class FollowUpModel: ObservableObject {
    private let store: DataStore

    @Published var patient: PatientProfile {
        didSet { store.setPatient(patient) }
    }
    @Published var sessions: [SessionRecord]
    @Published var thresholds: [ThresholdRecord]
    @Published var observations: [ObservationRecord]
    @Published var tests: [EMGTestResult]
    @Published var assessments: [AssessmentRecord]
    @Published var assessDraft = AssessmentRecord()
    @Published var assessMessage = ""
    @Published var warnings: [String] = []
    @Published var info = ""

    // UI state
    @Published var selectedSessionId: String? {
        didSet { loadPreview() }
    }
    @Published var emgPreview: [PreviewPoint] = []
    @Published var stimPreview: [PreviewPoint] = []
    @Published var askDelete = false
    @Published var progressMetric = "threshold"
    @Published var progressMuscle = Catalog.muscles[5]
    @Published var periodChoice = 1
    @Published var draft = ObservationRecord()
    @Published var draftSaved = ""

    static let periodLabels = [tr("30 derniers jours"), tr("90 derniers jours"), tr("6 derniers mois"), tr("Tout l'historique")]

    init() {
        store = DataStore(root: AppFolders.follow)
        patient = store.patient
        sessions = store.sessions
        thresholds = store.thresholds
        observations = store.observations
        tests = store.tests
        assessments = store.assessments
        warnings = store.warnings
        // CSVs already recorded by previous versions enter the history (once each)
        let added = store.importCSVs(from: AppFolders.data)
        if added > 0 {
            sessions = store.sessions
            info = tr("\(added) ancienne(s) séance(s) importée(s) depuis les fichiers CSV.")
        }
        selectedSessionId = sessions.first?.id
        loadPreview()
    }

    /// Curves of the selected session, read from its CSV file (reduced to ~300 points per curve).
    private func loadPreview() {
        emgPreview = []
        stimPreview = []
        guard let s = selectedSession, let d = csvData(for: s), d.rowCount > 1 else { return }
        var id = 0
        var emg: [PreviewPoint] = []
        var stim: [PreviewPoint] = []
        for (name, series) in [(tr("EMG 1"), d.emg1), (tr("EMG 2"), d.emg2)] {
            let pts = SessionCSV.downsample(t: d.t, v: series, maxPoints: 300)
            if pts.contains(where: { $0.1 > 0 }) {
                for p in pts {
                    id += 1
                    emg.append(PreviewPoint(id: id, minutes: p.0 / 60, name: name, value: p.1))
                }
            }
        }
        for k in 0..<4 where (d.stim[k].max() ?? 0) > 0 {
            let pts = SessionCSV.downsample(t: d.t, v: d.stim[k].map { Double($0) }, maxPoints: 300)
            for p in pts {
                id += 1
                stim.append(PreviewPoint(id: id, minutes: p.0 / 60, name: tr("Canal \(k + 1)"), value: p.1))
            }
        }
        emgPreview = emg
        stimPreview = stim
    }

    private func refresh() {
        sessions = store.sessions
        thresholds = store.thresholds
        observations = store.observations
        tests = store.tests
        assessments = store.assessments
        warnings = store.warnings
    }

    // MARK: - Patient

    var ageText: String { return patient.ageDescription() }

    // MARK: - Sessions

    func saveSession(_ s: SessionRecord) {
        store.upsertSession(s)
        refresh()
        selectedSessionId = s.id
    }

    func updateSession(_ id: String, _ change: (inout SessionRecord) -> Void) {
        guard var s = store.session(id: id) else { return }
        change(&s)
        store.upsertSession(s, force: true)
        refresh()
    }

    func deleteSession(_ id: String) {
        store.deleteSession(id: id)
        refresh()
        if selectedSessionId == id { selectedSessionId = sessions.first?.id }
    }

    var selectedSession: SessionRecord? {
        guard let id = selectedSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    func importCSVFolder() {
        let n = store.importCSVs(from: AppFolders.data)
        refresh()
        info = n > 0 ? tr("\(n) séance(s) importée(s).") : tr("Rien de nouveau à importer.")
    }

    // MARK: - Photos

    func photoImage(_ name: String) -> NSImage? {
        return NSImage(contentsOf: store.photoURL(name))
    }

    /// Shrinks the photo and converts it to JPEG (iPhones often send HEIC).
    private func jpegData(from url: URL, maxSide: CGFloat = 1600) -> Data? {
        guard let img = NSImage(contentsOf: url), let rep = img.representations.first else { return nil }
        let w = CGFloat(rep.pixelsWide)
        let h = CGFloat(rep.pixelsHigh)
        if w <= 0 || h <= 0 { return nil }
        let scale = min(1, maxSide / max(w, h))
        let newW = max(1, Int(w * scale))
        let newH = max(1, Int(h * scale))
        guard let bmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: newW, pixelsHigh: newH,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
        img.draw(in: NSRect(x: 0, y: 0, width: newW, height: newH), from: NSRect.zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return bmp.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    func addPhotos(sessionId: String) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.message = tr("Choisis les photos de placement (AirDrop, Photos, dossier…)")
        if panel.runModal() != .OK { return }
        var n = 0
        for url in panel.urls {
            if let d = jpegData(from: url), store.addPhoto(jpeg: d, sessionId: sessionId) != nil { n += 1 }
        }
        refresh()
        info = n > 0 ? tr("\(n) photo(s) ajoutée(s).") : tr("Aucune photo n'a pu être lue.")
    }

    func removePhoto(_ name: String, sessionId: String) {
        store.removePhoto(name: name, sessionId: sessionId)
        refresh()
    }

    // MARK: - Thresholds

    func addThreshold(_ t: ThresholdRecord) {
        store.addThreshold(t)
        refresh()
    }

    func deleteThreshold(_ id: String) {
        store.deleteThreshold(id: id)
        refresh()
    }

    // MARK: - Observations

    func saveDraftObservation() {
        var o = draft
        if o.scales.isEmpty && o.flags.isEmpty && o.numbers.isEmpty && o.text.trimmingCharacters(in: .whitespaces).isEmpty {
            draftSaved = tr("Rien à enregistrer : remplis au moins un élément.")
            return
        }
        o.date = Date()
        store.upsertObservation(o)
        refresh()
        draft = ObservationRecord()
        draftSaved = tr("Fiche enregistrée (\(Fmt.dateTime(o.date))).")
    }

    func deleteObservation(_ id: String) {
        store.deleteObservation(id: id)
        refresh()
    }

    func setScale(_ key: String, _ value: Int?) {
        if let v = value { draft.scales[key] = v } else { draft.scales.removeValue(forKey: key) }
    }

    // MARK: - EMG tests

    func addTest(_ t: EMGTestResult) {
        store.addTest(t)
        refresh()
    }

    func deleteTest(_ id: String) {
        store.deleteTest(id: id)
        refresh()
    }

    // MARK: - Pelvic floor assessments

    func saveAssessment() {
        var a = assessDraft
        if a.label.trimmingCharacters(in: .whitespaces).isEmpty {
            a.label = tr("Évaluation ") + String(assessments.count + 1)
        }
        if Catalog.midlineMuscles.contains(a.muscle) { a.side = Catalog.noSide }
        else if a.side != "Gauche" { a.side = "Droite" }
        store.upsertAssessment(a)
        refresh()
        assessMessage = tr("Évaluation « \(a.label) » enregistrée.")
        assessDraft = AssessmentRecord(date: Date(), label: "", muscle: a.muscle, side: a.side)
    }

    func deleteAssessment(_ id: String) {
        store.deleteAssessment(id: id)
        refresh()
    }

    // MARK: - Progression

    var currentMetric: ProgressMetric {
        return ProgressStats.metric(id: progressMetric) ?? ProgressStats.metrics[0]
    }

    func points(side: String) -> [SeriesPoint] {
        return ProgressStats.series(metric: progressMetric, muscle: progressMuscle, side: side,
                               sessions: sessions, thresholds: thresholds, tests: tests, observations: observations,
                               assessments: assessments)
    }

    /// Sides to plot for the chosen muscle (a single “No side” for the anal probe).
    var progressSides: [String] { return Catalog.sidesFor(muscle: progressMuscle) }

    var chartPoints: [ChartPoint] {
        var out: [ChartPoint] = []
        for side in progressSides {
            for p in points(side: side) { out.append(ChartPoint(date: p.date, value: p.value, side: trd(side))) }
        }
        return out
    }

    func trendText(side: String) -> String {
        let pts = points(side: side)
        if pts.isEmpty { return trd(side) + tr(" : aucune mesure.") }
        return trd(side) + " : " + ProgressStats.describe(ProgressStats.trend(pts), unit: currentMetric.unit)
    }

    // MARK: - PDF reports

    private func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func csvData(for s: SessionRecord) -> CSVSessionData? {
        if s.csvFile.isEmpty { return nil }
        let url = AppFolders.data.appendingPathComponent(s.csvFile)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return SessionCSV.parse(text)
    }

    private func fileStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    func makeSessionReport(_ id: String) {
        guard let s = store.session(id: id) else { return }
        var jpegs: [JPEGInfo] = []
        for name in s.photos {
            if let d = try? Data(contentsOf: store.photoURL(name)), let j = JPEGInfo.parse(d) { jpegs.append(j) }
        }
        let data = Reports.sessionReport(patient: patient, session: s, csv: csvData(for: s), thresholds: thresholds, photos: jpegs)
        write(data, name: "seance_\(fileStamp()).pdf")
    }

    func makePeriodReport() {
        let now = Date()
        var from = Date(timeIntervalSince1970: 0)
        switch periodChoice {
        case 0: from = now.addingTimeInterval(-30 * 86400)
        case 1: from = now.addingTimeInterval(-90 * 86400)
        case 2: from = now.addingTimeInterval(-183 * 86400)
        default: break
        }
        if periodChoice == 3, let first = sessions.map({ $0.start }).min() { from = first }
        let data = Reports.periodReport(patient: patient, from: from, to: now, sessions: sessions,
                                        thresholds: thresholds, tests: tests, observations: observations,
                                        assessments: assessments)
        write(data, name: "suivi_\(fileStamp()).pdf")
    }

    private func write(_ data: Data, name: String) {
        do {
            try FileManager.default.createDirectory(at: AppFolders.reports, withIntermediateDirectories: true)
            let url = AppFolders.reports.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            info = tr("Rapport PDF créé : Documents/NeuroTracLive/Rapports/") + name
            openFile(url)
        } catch {
            info = tr("Rapport impossible : \(error.localizedDescription)")
        }
    }

    func openCSV(_ s: SessionRecord) {
        if s.csvFile.isEmpty { return }
        NSWorkspace.shared.open(AppFolders.data.appendingPathComponent(s.csvFile))
    }

    func openFollowFolder() {
        try? FileManager.default.createDirectory(at: AppFolders.follow, withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppFolders.follow)
    }
}
