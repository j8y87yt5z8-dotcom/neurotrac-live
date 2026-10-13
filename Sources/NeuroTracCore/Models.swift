import Foundation

// Follow-up data models (patient sheet, sessions, thresholds, observations, EMG tests).
// Everything is Codable (readable JSON, open format for a future merge with a web app).
// Every decoder tolerates a missing field: new ones can be added later without breaking old files.

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        return (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

public let defaultDeviceName = "NeuroTrac MyoPlus Pro 4"

// MARK: - Patient sheet

public struct PatientProfile: Codable, Equatable {
    public var firstName = ""
    public var lastName = ""
    /// Format “yyyy-mm-dd” (empty if unknown)
    public var birthDate = ""
    public var sex = ""
    public var address = ""
    public var phone = ""
    public var heightCm = ""
    public var weightKg = ""
    public var diagnosis = ""
    public var lesionLevel = ""
    public var referents = ""
    public var notes = ""

    public init() {}

    /// Starting sheet (fictional, to be replaced in the Patient tab).
    public static var exemple: PatientProfile {
        var p = PatientProfile()
        p.firstName = "Jane"
        p.lastName = "DOE"
        p.birthDate = "2020-01-15"
        return p
    }

    enum CodingKeys: String, CodingKey {
        case firstName, lastName, birthDate, sex, address, phone, heightCm, weightKg, diagnosis, lesionLevel, referents, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstName = c.value(.firstName, "")
        lastName = c.value(.lastName, "")
        birthDate = c.value(.birthDate, "")
        sex = c.value(.sex, "")
        address = c.value(.address, "")
        phone = c.value(.phone, "")
        heightCm = c.value(.heightCm, "")
        weightKg = c.value(.weightKg, "")
        diagnosis = c.value(.diagnosis, "")
        lesionLevel = c.value(.lesionLevel, "")
        referents = c.value(.referents, "")
        notes = c.value(.notes, "")
    }

    public var fullName: String {
        let n = (firstName + " " + lastName).trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Patient" : n
    }

    /// Age as text (“4 years 4 months”) at a given date, or an empty string if the birth date is unknown.
    public func ageDescription(on date: Date = Date()) -> String {
        let parts = birthDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let b = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return "" }
        let c = cal.dateComponents([.year, .month], from: b, to: date)
        let y = c.year ?? 0
        let m = c.month ?? 0
        if y < 0 { return "" }
        if y == 0 { return tr("\(m) mois") }
        let years = y > 1 ? tr("\(y) ans") : tr("\(y) an")
        if m == 0 { return years }
        return years + " " + tr("\(m) mois")
    }
}

// MARK: - Session

public struct SessionRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var start: Date
    public var durationSec: Double
    public var muscle: String
    public var side: String
    public var channel: String
    public var programKind: String
    public var programName: String
    public var frequency: String
    public var width: String
    public var rhythm: String
    public var ramps: String
    public var programDuration: String
    public var setIntensity: String
    public var device: String
    public var maxStim: [Int]
    /// Time during which the device sent current; -1 if unknown (imported sessions).
    public var stimActiveSec: Double
    public var emgMean1: Double
    public var emgMax1: Double
    public var emgMean2: Double
    public var emgMax2: Double
    /// Median and 95th percentile: far more stable than the maximum, which depends on a few noisy values
    public var emgMedian1: Double
    public var emgMedian2: Double
    public var emgP95_1: Double
    public var emgP95_2: Double
    public var emgCount: Int
    public var alertCount: Int
    public var note: String
    /// CSV file name (in the NeuroTracLive folder)
    public var csvFile: String
    /// Photo names (in the photos folder)
    public var photos: [String]
    /// “app” (recorded live), “auto” (automatic recording) or “import”
    public var source: String
    /// Probe or electrodes used (e.g. type and size of the anal probe)
    public var probe: String
    /// Position of the reference electrode
    public var reference: String
    /// Number of stimulation bursts seen during the session; -1 if unknown (older sessions)
    public var stimBursts: Int

    public init(id: String, start: Date) {
        self.id = id
        self.start = start
        durationSec = 0
        muscle = ""
        side = ""
        channel = ""
        programKind = ""
        programName = ""
        frequency = ""
        width = ""
        rhythm = ""
        ramps = ""
        programDuration = ""
        setIntensity = ""
        device = defaultDeviceName
        maxStim = [0, 0, 0, 0]
        stimActiveSec = -1
        emgMean1 = 0
        emgMax1 = 0
        emgMean2 = 0
        emgMax2 = 0
        emgMedian1 = 0
        emgMedian2 = 0
        emgP95_1 = 0
        emgP95_2 = 0
        emgCount = 0
        alertCount = 0
        note = ""
        csvFile = ""
        photos = []
        source = "app"
        probe = ""
        reference = ""
        stimBursts = -1
    }

    enum CodingKeys: String, CodingKey {
        case id, start, durationSec, muscle, side, channel, programKind, programName, frequency, width, rhythm, ramps
        case programDuration, setIntensity, device, maxStim, stimActiveSec, emgMean1, emgMax1, emgMean2, emgMax2
        case emgMedian1, emgMedian2, emgP95_1, emgP95_2
        case emgCount, alertCount, note, csvFile, photos, source
        case probe, reference, stimBursts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID().uuidString)
        start = c.value(.start, Date(timeIntervalSince1970: 0))
        durationSec = c.value(.durationSec, 0)
        muscle = c.value(.muscle, "")
        side = c.value(.side, "")
        channel = c.value(.channel, "")
        programKind = c.value(.programKind, "")
        programName = c.value(.programName, "")
        frequency = c.value(.frequency, "")
        width = c.value(.width, "")
        rhythm = c.value(.rhythm, "")
        ramps = c.value(.ramps, "")
        programDuration = c.value(.programDuration, "")
        setIntensity = c.value(.setIntensity, "")
        device = c.value(.device, defaultDeviceName)
        maxStim = c.value(.maxStim, [0, 0, 0, 0])
        stimActiveSec = c.value(.stimActiveSec, -1)
        emgMean1 = c.value(.emgMean1, 0)
        emgMax1 = c.value(.emgMax1, 0)
        emgMean2 = c.value(.emgMean2, 0)
        emgMax2 = c.value(.emgMax2, 0)
        emgMedian1 = c.value(.emgMedian1, 0)
        emgMedian2 = c.value(.emgMedian2, 0)
        emgP95_1 = c.value(.emgP95_1, 0)
        emgP95_2 = c.value(.emgP95_2, 0)
        emgCount = c.value(.emgCount, 0)
        alertCount = c.value(.alertCount, 0)
        note = c.value(.note, "")
        csvFile = c.value(.csvFile, "")
        photos = c.value(.photos, [])
        source = c.value(.source, "app")
        probe = c.value(.probe, "")
        reference = c.value(.reference, "")
        stimBursts = c.value(.stimBursts, -1)
    }

    public var maxStimOverall: Int { return maxStim.max() ?? 0 }

    /// EMG channel used for the indicators: the channel chosen for the session (channel 1 by default).
    public var primaryEMG: (mean: Double, max: Double, median: Double, p95: Double) {
        if channel.contains("2") && !channel.contains("1") {
            return (emgMean2, emgMax2, emgMedian2, emgP95_2)
        }
        if channel.contains("1") && channel.contains("2") {
            return (max(emgMean1, emgMean2), max(emgMax1, emgMax2), max(emgMedian1, emgMedian2), max(emgP95_1, emgP95_2))
        }
        return (emgMean1, emgMax1, emgMedian1, emgP95_1)
    }
}

// MARK: - Electrostimulation threshold

public struct ThresholdRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var date: Date
    public var muscle: String
    public var side: String
    public var mA: Double
    public var kind: String
    public var note: String
    public var device: String
    public var program: String
    public var electrodes: String
    public var sessionId: String

    public init(date: Date = Date(), muscle: String, side: String, mA: Double, kind: String) {
        id = UUID().uuidString
        self.date = date
        self.muscle = muscle
        self.side = side
        self.mA = mA
        self.kind = kind
        note = ""
        device = defaultDeviceName
        program = ""
        electrodes = ""
        sessionId = ""
    }

    enum CodingKeys: String, CodingKey {
        case id, date, muscle, side, mA, kind, note, device, program, electrodes, sessionId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID().uuidString)
        date = c.value(.date, Date(timeIntervalSince1970: 0))
        muscle = c.value(.muscle, "")
        side = c.value(.side, "")
        mA = c.value(.mA, 0)
        kind = c.value(.kind, "")
        note = c.value(.note, "")
        device = c.value(.device, defaultDeviceName)
        program = c.value(.program, "")
        electrodes = c.value(.electrodes, "")
        sessionId = c.value(.sessionId, "")
    }
}

// MARK: - Observation sheet (walking, foot…)

public struct ObservationRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var date: Date
    /// 0 to 5 scales, catalog keys (e.g. “genou_ext_D”)
    public var scales: [String: Int]
    public var numbers: [String: Double]
    public var flags: [String: Bool]
    public var text: String

    public init(date: Date = Date()) {
        id = UUID().uuidString
        self.date = date
        scales = [:]
        numbers = [:]
        flags = [:]
        text = ""
    }

    enum CodingKeys: String, CodingKey { case id, date, scales, numbers, flags, text }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID().uuidString)
        date = c.value(.date, Date(timeIntervalSince1970: 0))
        scales = c.value(.scales, [:])
        numbers = c.value(.numbers, [:])
        flags = c.value(.flags, [:])
        text = c.value(.text, "")
    }
}

// MARK: - Standardized EMG test

public struct EMGTestResult: Codable, Identifiable, Equatable {
    public var id: String
    public var date: Date
    public var muscle: String
    public var side: String
    public var channel: Int
    /// Rest measured before the contractions (µV)
    public var baseline: Double
    /// Best contraction peak, above rest (µV)
    public var peak: Double
    /// Mean during the contractions, above rest (µV)
    public var mean: Double
    /// Mean time spent above half the peak (s)
    public var holdSec: Double
    public var cycles: Int
    public var note: String
    public var rawFile: String

    public init(date: Date = Date(), muscle: String, side: String, channel: Int) {
        id = UUID().uuidString
        self.date = date
        self.muscle = muscle
        self.side = side
        self.channel = channel
        baseline = 0
        peak = 0
        mean = 0
        holdSec = 0
        cycles = 0
        note = ""
        rawFile = ""
    }

    enum CodingKeys: String, CodingKey {
        case id, date, muscle, side, channel, baseline, peak, mean, holdSec, cycles, note, rawFile
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID().uuidString)
        date = c.value(.date, Date(timeIntervalSince1970: 0))
        muscle = c.value(.muscle, "")
        side = c.value(.side, "")
        channel = c.value(.channel, 1)
        baseline = c.value(.baseline, 0)
        peak = c.value(.peak, 0)
        mean = c.value(.mean, 0)
        holdSec = c.value(.holdSec, 0)
        cycles = c.value(.cycles, 0)
        note = c.value(.note, "")
        rawFile = c.value(.rawFile, "")
    }
}

// MARK: - Pelvic floor assessment (“test B1 / B2” type)

/// Scores of a hand-entered assessment (protocol of the software or the clinician):
/// rest before, fast contractions, held (“tonic”) contractions, endurance, rest after, overall score.
public struct AssessmentRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var date: Date
    /// Name given to the assessment (“B1”, “B2”…)
    public var label: String
    public var muscle: String
    public var side: String
    public var fast: Double
    public var endurance: Double
    public var tonic: Double
    public var baselineBefore: Double
    public var baselineAfter: Double
    public var total: Double
    public var note: String

    public init(date: Date = Date(), label: String = "", muscle: String = "Sphincter anal (sonde)", side: String = Catalog.noSide) {
        id = UUID().uuidString
        self.date = date
        self.label = label
        self.muscle = muscle
        self.side = side
        fast = 0
        endurance = 0
        tonic = 0
        baselineBefore = 0
        baselineAfter = 0
        total = 0
        note = ""
    }

    enum CodingKeys: String, CodingKey {
        case id, date, label, muscle, side, fast, endurance, tonic, baselineBefore, baselineAfter, total, note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID().uuidString)
        date = c.value(.date, Date(timeIntervalSince1970: 0))
        label = c.value(.label, "")
        muscle = c.value(.muscle, "Sphincter anal (sonde)")
        side = c.value(.side, Catalog.noSide)
        fast = c.value(.fast, 0)
        endurance = c.value(.endurance, 0)
        tonic = c.value(.tonic, 0)
        baselineBefore = c.value(.baselineBefore, 0)
        baselineAfter = c.value(.baselineAfter, 0)
        total = c.value(.total, 0)
        note = c.value(.note, "")
    }
}
