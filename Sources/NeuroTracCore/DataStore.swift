import Foundation

/// Local storage of the follow-up: readable JSON files in a folder.
///   patient.json, seances.json, seuils.json, observations.json, tests_emg.json, evaluations.json, seances_ignorees.json
/// photos/  (placement photos, JPEG)
/// Every write is atomic and keeps the previous version as “.bak”.
public final class DataStore {
    public let root: URL
    public private(set) var patient: PatientProfile
    public private(set) var sessions: [SessionRecord] = []
    public private(set) var thresholds: [ThresholdRecord] = []
    public private(set) var observations: [ObservationRecord] = []
    public private(set) var tests: [EMGTestResult] = []
    public private(set) var assessments: [AssessmentRecord] = []
    public private(set) var ignoredSessionIds: Set<String> = []
    /// Messages to show to the user (unreadable file set aside, write failure…)
    public private(set) var warnings: [String] = []

    private let fm = FileManager.default

    public var photosDir: URL { return root.appendingPathComponent("photos", isDirectory: true) }

    public init(root: URL) {
        self.root = root
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        patient = PatientProfile.exemple
        if let p: PatientProfile = load("patient.json") { patient = p } else { save(patient, "patient.json") }
        sessions = load("seances.json") ?? []
        thresholds = load("seuils.json") ?? []
        observations = load("observations.json") ?? []
        tests = load("tests_emg.json") ?? []
        assessments = load("evaluations.json") ?? []
        ignoredSessionIds = Set((load("seances_ignorees.json") as [String]?) ?? [])
        sessions.sort { $0.start > $1.start }
    }

    // MARK: - JSON files

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func load<T: Decodable>(_ name: String) -> T? {
        let url = root.appendingPathComponent(name)
        guard fm.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try DataStore.makeDecoder().decode(T.self, from: data)
        } catch {
            // damaged file: set aside instead of being overwritten
            let stamp = Int(Date().timeIntervalSince1970)
            let side = root.appendingPathComponent(name + ".illisible-\(stamp)")
            try? fm.moveItem(at: url, to: side)
            warnings.append(tr("Le fichier \(name) était illisible ; il a été mis de côté (\(side.lastPathComponent))."))
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        let url = root.appendingPathComponent(name)
        do {
            let data = try DataStore.makeEncoder().encode(value)
            if fm.fileExists(atPath: url.path) {
                let bak = root.appendingPathComponent(name + ".bak")
                try? fm.removeItem(at: bak)
                try? fm.copyItem(at: url, to: bak)
            }
            try data.write(to: url, options: .atomic)
        } catch {
            warnings.append(tr("Impossible d'écrire \(name) : \(error.localizedDescription)"))
        }
    }

    public func clearWarnings() { warnings = [] }

    // MARK: - Patient

    public func setPatient(_ p: PatientProfile) {
        patient = p
        save(p, "patient.json")
    }

    // MARK: - Sessions

    /// Adds or replaces a session (same identifier). Returns false if it had been deliberately deleted.
    @discardableResult
    public func upsertSession(_ s: SessionRecord, force: Bool = false) -> Bool {
        if !force && ignoredSessionIds.contains(s.id) { return false }
        if let i = sessions.firstIndex(where: { $0.id == s.id }) {
            sessions[i] = s
        } else {
            sessions.append(s)
        }
        sessions.sort { $0.start > $1.start }
        save(sessions, "seances.json")
        return true
    }

    public func session(id: String) -> SessionRecord? {
        return sessions.first { $0.id == id }
    }

    public func deleteSession(id: String) {
        sessions.removeAll { $0.id == id }
        ignoredSessionIds.insert(id)
        save(sessions, "seances.json")
        save(Array(ignoredSessionIds).sorted(), "seances_ignorees.json")
    }

    /// Imports all session CSVs from a folder (except marker files). Returns the number added.
    @discardableResult
    public func importCSVs(from folder: URL) -> Int {
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return 0 }
        var added = 0
        var changed = false
        for n in names.sorted() where n.hasSuffix(".csv") && !n.hasSuffix("_reperes.csv") {
            let id = "csv:" + n
            if ignoredSessionIds.contains(id) || sessions.contains(where: { $0.id == id || $0.csvFile == n }) { continue }
            let url = folder.appendingPathComponent(n)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var mod = Date()
            if let attrs = try? fm.attributesOfItem(atPath: url.path), let d = attrs[.modificationDate] as? Date { mod = d }
            if let rec = SessionCSV.record(fileName: n, text: text, fallbackDate: mod) {
                sessions.append(rec)
                added += 1
                changed = true
            }
        }
        if changed {
            sessions.sort { $0.start > $1.start }
            save(sessions, "seances.json")
        }
        return added
    }

    // MARK: - Photos

    /// Saves a photo (JPEG) and attaches it to the session. Returns the file name.
    public func addPhoto(jpeg: Data, sessionId: String) -> String? {
        guard var s = session(id: sessionId) else { return nil }
        try? fm.createDirectory(at: photosDir, withIntermediateDirectories: true)
        let safe = String(sessionId.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" })
        let name = "\(safe)_\(Int(Date().timeIntervalSince1970))_\(s.photos.count + 1).jpg"
        do {
            try jpeg.write(to: photosDir.appendingPathComponent(name), options: .atomic)
        } catch {
            warnings.append(tr("Photo non enregistrée : \(error.localizedDescription)"))
            return nil
        }
        s.photos.append(name)
        upsertSession(s, force: true)
        return name
    }

    public func removePhoto(name: String, sessionId: String) {
        guard var s = session(id: sessionId) else { return }
        s.photos.removeAll { $0 == name }
        try? fm.removeItem(at: photosDir.appendingPathComponent(name))
        upsertSession(s, force: true)
    }

    public func photoURL(_ name: String) -> URL {
        return photosDir.appendingPathComponent(name)
    }

    // MARK: - Thresholds, observations, tests

    public func addThreshold(_ t: ThresholdRecord) {
        thresholds.append(t)
        thresholds.sort { $0.date > $1.date }
        save(thresholds, "seuils.json")
    }

    public func deleteThreshold(id: String) {
        thresholds.removeAll { $0.id == id }
        save(thresholds, "seuils.json")
    }

    public func upsertObservation(_ o: ObservationRecord) {
        if let i = observations.firstIndex(where: { $0.id == o.id }) {
            observations[i] = o
        } else {
            observations.append(o)
        }
        observations.sort { $0.date > $1.date }
        save(observations, "observations.json")
    }

    public func deleteObservation(id: String) {
        observations.removeAll { $0.id == id }
        save(observations, "observations.json")
    }

    public func addTest(_ t: EMGTestResult) {
        tests.append(t)
        tests.sort { $0.date > $1.date }
        save(tests, "tests_emg.json")
    }

    public func deleteTest(id: String) {
        tests.removeAll { $0.id == id }
        save(tests, "tests_emg.json")
    }

    public func upsertAssessment(_ a: AssessmentRecord) {
        if let i = assessments.firstIndex(where: { $0.id == a.id }) {
            assessments[i] = a
        } else {
            assessments.append(a)
        }
        assessments.sort { $0.date > $1.date }
        save(assessments, "evaluations.json")
    }

    public func deleteAssessment(id: String) {
        assessments.removeAll { $0.id == id }
        save(assessments, "evaluations.json")
    }
}
