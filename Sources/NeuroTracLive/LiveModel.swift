import Foundation
import SwiftUI
import AppKit
import NeuroTracCore

struct DeviceChoice: Identifiable, Hashable {
    let id: String
    let label: String
    let isMyo: Bool
}

struct AppEvent: Identifiable {
    let id: Int
    let t: Double
    let text: String
    let alert: Bool
}

/// Ready-to-display text for the “Current program” panel.
struct ProgramSnapshot: Equatable {
    var name = "—"
    var status = "—"
    var frequency = "—"
    var width = "—"
    var rhythm = "—"
    var ramps = "—"
    var duration = "—"
    var remaining = "—"
}

struct DebugRow: Identifiable {
    let id: Int
    let t: Double
    /// -1 for a note
    let packetId: Int
    let hex: String
    let known: Bool
    let note: String?
}

struct EMGPoint: Identifiable {
    let id: Int
    let t: Double
    let ch1: Double
    let ch2: Double
}

struct StimPoint: Identifiable {
    let id: Int
    let t: Double
    let c1: Double
    let c2: Double
    let c3: Double
    let c4: Double
}

struct Mark: Identifiable {
    let id = UUID()
    let t: Double
    let tag: String
    let note: String
}

enum Side: String, CaseIterable, Identifiable {
    case droite = "Droite"
    case gauche = "Gauche"
    case deux = "Les deux"
    case aucun = "Sans côté"
    var id: String { rawValue }
}

enum ChannelUse: String, CaseIterable, Identifiable {
    case c1 = "Canal 1"
    case c2 = "Canal 2"
    case c12 = "Canaux 1 et 2"
    var id: String { rawValue }
}

enum ProgramKind: String, CaseIterable, Identifiable {
    case emg = "EMG seul"
    case ets = "EMG déclenche la stimulation (ETS)"
    case stim = "Stimulation seule"
    var id: String { rawValue }
}

let muscleList: [String] = Catalog.muscles

/// Statistics accumulated during a recording, for the end-of-session summary.
struct RecStats {
    var startT = 0.0
    var n = 0
    var max1 = 0.0
    var max2 = 0.0
    var sum1 = 0.0
    var sum2 = 0.0
    var stimMax = [0, 0, 0, 0]
    var stimActiveSeconds = 0.0
    var prevStimT: Double? = nil
    var prevStimActive = false
    var lastActiveT = -100.0
    var bursts = 0
    var alertCount = 0
    var v1: [Double] = []
    var v2: [Double] = []
}

/// All changes happen on the main thread (link callbacks are dispatched there).
final class LiveModel: ObservableObject {
    // Connection
    @Published var devices: [DeviceChoice] = []
    @Published var selectedDevice = ""
    @Published var pin = "1234"
    @Published var statusText = tr("Non connecté")
    @Published var linkState = LinkState.idle
    @Published var autoReconnect = true

    /// True only once the device has answered (PIN accepted): this is what the indicator shows.
    var isConnected: Bool { linkState == .connected }
    /// True during the whole procedure (connection, handshake, reading): the button becomes “Disconnect”.
    var isBusy: Bool { linkState != .idle || reconnectPending }

    // Live values
    @Published var emg1 = 0.0
    @Published var emg2 = 0.0
    @Published var stim = [0, 0, 0, 0]
    @Published var etsCountdown = 0
    @Published var started = false
    @Published var workPhase = "—"
    @Published var modeText = "—"
    @Published var emgPoints: [EMGPoint] = []
    @Published var stimPoints: [StimPoint] = []
    @Published var packetSummary = ""
    @Published var latestT = 0.0

    // Session sheet
    @Published var muscle = muscleList[0] {
        didSet {
            UserDefaults.standard.set(muscle, forKey: "ntl.muscle")
            // the anal probe has no side; a lateral muscle cannot stay “no side”
            if Catalog.midlineMuscles.contains(muscle) {
                if side != .aucun { side = .aucun }
            } else if side == .aucun {
                side = .droite
            }
        }
    }
    @Published var langChoice: String = UserDefaults.standard.string(forKey: Lang.defaultsKey) ?? "auto" {
        didSet {
            if langChoice == "auto" { UserDefaults.standard.removeObject(forKey: Lang.defaultsKey) }
            else { UserDefaults.standard.set(langChoice, forKey: Lang.defaultsKey) }
        }
    }
    @Published var side = Side.droite {
        didSet { UserDefaults.standard.set(side.rawValue, forKey: "ntl.side") }
    }
    @Published var channelUse = ChannelUse.c1 {
        didSet { UserDefaults.standard.set(channelUse.rawValue, forKey: "ntl.channel") }
    }
    @Published var program = ProgramKind.ets {
        didSet { UserDefaults.standard.set(program.rawValue, forKey: "ntl.program") }
    }
    @Published var setIntensity = ""
    @Published var note = ""
    /// Probe / electrodes used (e.g. anal probe, size) and position of the reference electrode
    @Published var probe = "" {
        didSet { UserDefaults.standard.set(probe, forKey: "ntl.probe") }
    }
    @Published var reference = "" {
        didSet { UserDefaults.standard.set(reference, forKey: "ntl.reference") }
    }

    // Follow-up (patient sheet, history, thresholds, observations, EMG tests, reports)
    let follow = FollowUpModel()
    /// Automatically records each program started on the device
    @Published var autoRecord = true {
        didSet { UserDefaults.standard.set(autoRecord, forKey: "ntl.autoRecord") }
    }
    @Published var lastSavedText = ""
    /// Maximum intensity received from the device during the last 5 seconds (mA)
    @Published var recentStimMax = 0

    // Thresholds
    @Published var thresholdKind = Catalog.thresholdKinds[2]
    @Published var thresholdInput = ""
    @Published var thresholdNote = ""
    @Published var thresholdMessage = ""

    // Standardized EMG test
    @Published var testChannel = 1
    @Published var testRunning = false
    @Published var testCue = tr("Prêt")
    @Published var testRemaining = 0.0
    @Published var testElapsed = 0.0
    @Published var testResult: EMGTestAnalysis?
    @Published var testMessage = ""
    let testProtocol = EMGTestProtocol()

    // Recording
    @Published var isRecording = false
    @Published var recordingPath = ""
    @Published var summaryText = ""
    @Published var marks: [Mark] = []
    @Published var markNote = ""

    // Current program and events
    @Published var progInfo = ProgramSnapshot()
    @Published var alertText: String?
    @Published var events: [AppEvent] = []

    // Debug mode
    @Published var debugRows: [DebugRow] = []
    @Published var debugStats: [PacketStat] = []
    @Published var debugPaused = false
    @Published var debugFilter = ""
    @Published var debugNote = ""
    @Published var debugFolderPath = ""
    /// Displayed tab: 0 Live, 1 Sessions, 2 Progression, 3 Observations, 4 EMG test, 5 Patient, 6 Debug
    @Published var tab = 0

    let windowSeconds = 30.0
    /// Clock (replaceable, to replay a recording without waiting)
    var clock: () -> Date = { Date() }

    private let link = DeviceLink()
    private var userDisconnected = true
    private var reconnectPending = false
    private var reconnectWork: DispatchWorkItem?
    private var tracker = DebugTracker()
    private var debugBuf: [DebugRow] = []
    private var debugNextId = 0
    private var lastDebugPublish = Date.distantPast
    private var framesFile: FileHandle?
    private var dev = DeviceStateTracker()
    private var logsNeedNew = true
    private var pendingRaw: [String] = []
    private var lastWarningCode = 1
    private var lastPaused: Bool?
    private var lastStarted: Bool?
    private var progSig = ""
    private var progSigPending = ""
    private var progSigSince = Date()
    private var libSeen = 0
    private var libReported = 0
    private var libSince = Date()
    private var eventId = 0
    private var t0 = Date()
    private var nextId = 0
    private var emgBuf: [EMGPoint] = []
    private var stimBuf: [StimPoint] = []
    private var lastPublish = Date.distantPast
    private var counts: [UInt8: Int] = [:]
    // Current values (updated on every frame, published ~14 times per second)
    private var cEmg1 = 0.0
    private var cEmg2 = 0.0
    private var cStim = [0, 0, 0, 0]
    private var cCountdown = 0
    private var cStarted = false
    private var cPhase = "—"
    private var cMode = "—"
    private var cT = 0.0

    private var csv: FileHandle?
    private var marksFile: FileHandle?
    private var rawFile: FileHandle?
    private var stats = RecStats()
    private var recStartDate = Date()
    private var recBase = ""
    private var recCSVURL: URL?
    private var recMarksURL: URL?
    private var autoStarted = false
    /// Last known program state while it was running (for the session sheet, even if the program is changed right after stopping)
    private var runSnap: ProgramSnapshot?
    private var runSnapAt = Date.distantPast
    private var stoppedSince: Date?
    private var testT: [Double] = []
    private var testV: [Double] = []
    private var testStart = Date()
    private var testTimer: Timer?
    private var lastCue = ""

    /// Identifier of the session being recorded (same rule as the CSV import)
    var recordingSessionId: String { return recBase.isEmpty ? "" : "csv:" + recBase + ".csv" }

    init() {
        let d = UserDefaults.standard
        if let m = d.string(forKey: "ntl.muscle"), muscleList.contains(m) { muscle = m }
        if let v = d.string(forKey: "ntl.side"), let sd = Side(rawValue: v) { side = sd }
        probe = d.string(forKey: "ntl.probe") ?? ""
        reference = d.string(forKey: "ntl.reference") ?? ""
        if let v = d.string(forKey: "ntl.channel"), let c = ChannelUse(rawValue: v) { channelUse = c }
        if let v = d.string(forKey: "ntl.program"), let p = ProgramKind(rawValue: v) { program = p }
        if d.object(forKey: "ntl.autoRecord") != nil { autoRecord = d.bool(forKey: "ntl.autoRecord") }
        refreshDevices()
        loadLibrary()
    }

    var windowRange: ClosedRange<Double> {
        let hi = max(latestT, windowSeconds)
        return (hi - windowSeconds)...hi
    }

    // MARK: - Devices

    func refreshDevices() {
        var list: [DeviceChoice] = []
        for d in PairedDevice.list() {
            list.append(DeviceChoice(id: "bt:" + d.address, label: tr("Bluetooth — ") + d.name, isMyo: d.name.contains("Myo") || d.name.contains("BB9C")))
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        for n in names.filter({ $0.hasPrefix("cu.") }).sorted() {
            // the generic macOS ports are of no use here
            if n.contains("Bluetooth-Incoming") || n.contains("debug-console") { continue }
            list.append(DeviceChoice(id: "serial:/dev/" + n, label: tr("Port série — ") + n, isMyo: n.contains("Myo") || n.contains("BB9C")))
        }
        // the NeuroTrac over a direct link first, then the rest
        list.sort { ($0.isMyo ? 0 : 1, $0.id.hasPrefix("bt:") ? 0 : 1) < ($1.isMyo ? 0 : 1, $1.id.hasPrefix("bt:") ? 0 : 1) }
        devices = list
        if !list.contains(where: { $0.id == selectedDevice }) {
            selectedDevice = list.first?.id ?? ""
        }
    }

    func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Connection

    func connect() {
        userDisconnected = false
        startLink(isRetry: false)
    }

    private func makeTransport() -> ByteTransport? {
        if selectedDevice.hasPrefix("bt:") {
            return BluetoothTransport(address: String(selectedDevice.dropFirst(3)))
        }
        if selectedDevice.hasPrefix("serial:") {
            return SerialTransport(path: String(selectedDevice.dropFirst(7)))
        }
        return nil
    }

    private func startLink(isRetry: Bool) {
        reconnectWork?.cancel()
        reconnectPending = false
        guard let transport = makeTransport() else {
            statusText = tr("Aucun appareil trouvé. Appaire le NeuroTrac dans Réglages Système > Bluetooth (code 1234), puis clique sur Actualiser.")
            userDisconnected = true
            return
        }
        if !isRetry {
            resetData()
            logsNeedNew = true
            pendingRaw = []
        }

        link.onStatus = { [weak self] s in
            DispatchQueue.main.async { self?.statusText = s }
        }
        link.onState = { [weak self] st in
            DispatchQueue.main.async { self?.linkState = st }
        }
        link.onEvent = { [weak self] e in
            DispatchQueue.main.async { self?.handle(e) }
        }
        link.onFrame = { [weak self] f in
            DispatchQueue.main.async { self?.handleFrame(f) }
        }
        link.onRaw = { [weak self] line in
            DispatchQueue.main.async { self?.writeRaw(line) }
        }
        link.onLost = { [weak self] in
            DispatchQueue.main.async { self?.linkLost() }
        }
        statusText = tr("Connexion en cours…")
        linkState = .connecting
        link.open(transport: transport, pin: pin)
    }

    private func linkLost() {
        if testRunning { cancelEMGTest() }
        if isRecording { stopRecording() }
        linkState = .idle
        guard !userDisconnected, autoReconnect else { return }
        reconnectPending = true
        statusText += tr(" — nouvelle tentative dans 4 s…")
        let w = DispatchWorkItem { [weak self] in
            guard let self = self, !self.userDisconnected else { return }
            self.startLink(isRetry: true)
        }
        reconnectWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }

    func disconnect() {
        userDisconnected = true
        reconnectWork?.cancel()
        reconnectPending = false
        if testRunning { cancelEMGTest() }
        if isRecording { stopRecording() }
        link.close()
        linkState = .idle
        statusText = tr("Déconnecté")
        rawFile?.closeFile()
        rawFile = nil
        framesFile?.closeFile()
        framesFile = nil
        logsNeedNew = true
    }

    func resetData() {
        runSnap = nil
        dev = DeviceStateTracker()
        dev.setLibrary(savedLibrary)
        events = []
        alertText = nil
        progInfo = ProgramSnapshot()
        lastWarningCode = 1
        lastPaused = nil
        lastStarted = nil
        progSig = ""
        progSigPending = ""
        libSeen = dev.library.count
        libReported = libSeen
        eventId = 0
        t0 = clock()
        nextId = 0
        emgBuf = []
        stimBuf = []
        emgPoints = []
        stimPoints = []
        counts = [:]
        packetSummary = ""
        latestT = 0
        emg1 = 0
        emg2 = 0
        stim = [0, 0, 0, 0]
        etsCountdown = 0
        cEmg1 = 0
        cEmg2 = 0
        cStim = [0, 0, 0, 0]
        cCountdown = 0
        cT = 0
        marks = []
        tracker = DebugTracker()
        debugBuf = []
        debugRows = []
        debugStats = []
    }

    // MARK: - Device events

    func handle(_ event: DeviceEvent) {
        let t = clock().timeIntervalSince(t0)
        cT = t
        switch event {
        case let .emg(id, c1, c2):
            counts[id, default: 0] += 1
            cEmg1 = c1
            cEmg2 = c2
            if testRunning {
                testT.append(clock().timeIntervalSince(testStart))
                testV.append(testChannel == 2 ? c2 : c1)
            }
            nextId += 1
            emgBuf.append(EMGPoint(id: nextId, t: t, ch1: c1, ch2: c2))
            trim(t)
            if isRecording {
                writeCSVRow(t: t, c1: c1, c2: c2)
                stats.n += 1
                stats.sum1 += c1
                stats.sum2 += c2
                stats.max1 = max(stats.max1, c1)
                stats.max2 = max(stats.max2, c2)
                stats.v1.append(c1)
                stats.v2.append(c2)
            }
        case let .stim(a, b, c, d, countdown):
            counts[11, default: 0] += 1
            cStim = [a, b, c, d]
            cCountdown = countdown
            nextId += 1
            stimBuf.append(StimPoint(id: nextId, t: t, c1: Double(a), c2: Double(b), c3: Double(c), c4: Double(d)))
            trim(t)
            if isRecording {
                updateStimStats(t: t, values: [a, b, c, d])
                writeCSVStimRow(t: t)
            }
        case let .status(isStarted, work, emgMode, paused):
            cStarted = isStarted
            cPhase = paused ? "Pause" : (work ? "Travail" : "Repos")
            cMode = emgMode ? "EMG" : "Stimulation"
        case let .other(id):
            counts[id, default: 0] += 1
        }

        let now = clock()
        if now.timeIntervalSince(lastPublish) > 0.07 {
            lastPublish = now
            emg1 = cEmg1
            emg2 = cEmg2
            stim = cStim
            etsCountdown = cCountdown
            started = cStarted
            workPhase = cPhase
            modeText = cMode
            latestT = cT
            let recent = stimBuf.filter { $0.t > cT - 5 }
            recentStimMax = Int(recent.map { max($0.c1, $0.c2, $0.c3, $0.c4) }.max() ?? 0)
            emgPoints = emgBuf
            stimPoints = stimBuf
            packetSummary = counts.keys.sorted().map { "n°\($0) : \(counts[$0] ?? 0)" }.joined(separator: "   ")
        }
    }

    private func trim(_ t: Double) {
        let limit = t - windowSeconds - 2
        if let first = emgBuf.first, first.t < limit {
            emgBuf.removeAll { $0.t < limit }
        }
        if let first = stimBuf.first, first.t < limit {
            stimBuf.removeAll { $0.t < limit }
        }
    }

    private func updateStimStats(t: Double, values: [Int]) {
        for i in 0..<4 { stats.stimMax[i] = max(stats.stimMax[i], values[i]) }
        let active = values.contains { $0 > 0 }
        if let p = stats.prevStimT, stats.prevStimActive {
            stats.stimActiveSeconds += min(t - p, 1.5)
        }
        if active {
            // a burst = current resuming after at least 0.6 s without current (avoids counting isolated dips)
            if !stats.prevStimActive && t - stats.lastActiveT > 0.6 { stats.bursts += 1 }
            stats.lastActiveT = t
        }
        stats.prevStimT = t
        stats.prevStimActive = active
    }

    // MARK: - Recording

    private var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("NeuroTracLive", isDirectory: true)
    }

    private func safe(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    private func openRawLog() {
        rawFile?.closeFile()
        rawFile = nil
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd_HHmmss"
            let url = folder.appendingPathComponent("brut_\(f.string(from: clock())).log")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            rawFile = try FileHandle(forWritingTo: url)
        } catch {
            rawFile = nil
        }
    }

    /// Log files are only created when the first data arrives:
    /// no more tiny empty files at every connection attempt.
    private func ensureLogs() {
        if !logsNeedNew { return }
        logsNeedNew = false
        openRawLog()
        openFramesLog()
        for l in pendingRaw { writeRawNow(l) }
        pendingRaw = []
    }

    private func writeRawNow(_ line: String) {
        if let h = rawFile, let d = (line + "\n").data(using: .utf8) { h.write(d) }
    }

    private func writeRaw(_ line: String) {
        if logsNeedNew {
            if line.contains("RX ") {
                ensureLogs()
            } else {
                pendingRaw.append(line)
                if pendingRaw.count > 40 { pendingRaw.removeFirst() }
                return
            }
        }
        writeRawNow(line)
    }

    func startRecording() {
        beginRecording(auto: false)
    }

    private func beginRecording(auto: Bool) {
        guard isConnected else {
            statusText = tr("Connecte d'abord l'appareil (attends « Connecté : lecture en cours »).")
            return
        }
        if isRecording { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd_HHmmss"
            let base = "\(f.string(from: clock()))_\(safe(muscle))_\(safe(side.rawValue))"
            let url = folder.appendingPathComponent(base + ".csv")
            let murl = folder.appendingPathComponent(base + "_reperes.csv")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            FileManager.default.createFile(atPath: murl.path, contents: nil)
            csv = try FileHandle(forWritingTo: url)
            marksFile = try FileHandle(forWritingTo: murl)
            recBase = base
            recCSVURL = url
            recMarksURL = murl
            recStartDate = clock()
            autoStarted = auto
            stoppedSince = nil

            let snap = makeSnapshot()
            let iso = ISO8601DateFormatter().string(from: clock())
            var head = "# date=\(iso)\n"
            head += "# muscle=\(muscle)\n"
            head += "# cote=\(side.rawValue)\n"
            head += "# canal=\(channelUse.rawValue)\n"
            head += "# sonde=\(probe.replacingOccurrences(of: "\n", with: " "))\n"
            head += "# reference=\(reference.replacingOccurrences(of: "\n", with: " "))\n"
            head += "# programme=\(snap.name)\n"
            head += "# type_programme_saisi=\(self.program.rawValue)\n"
            head += "# frequence=\(snap.frequency)\n"
            head += "# largeur_impulsion=\(snap.width)\n"
            head += "# rythme=\(snap.rhythm)\n"
            head += "# rampes=\(snap.ramps)\n"
            head += "# duree_programme=\(snap.duration)\n"
            head += "# intensite_reglee_mA=\(setIntensity)\n"
            head += "# enregistrement=\(auto ? "automatique" : "manuel")\n"
            head += "# note=\(note.replacingOccurrences(of: "\n", with: " "))\n"
            head += "t_s,emg1_uV,emg2_uV,stim1_mA,stim2_mA,stim3_mA,stim4_mA,phase,mode,restant_s,avertissement\n"
            csv?.write(head.data(using: .utf8)!)
            marksFile?.write("t_s,repere,note,emg1_uV,emg2_uV,stim1,stim2,stim3,stim4\n".data(using: .utf8)!)

            stats = RecStats()
            stats.startT = clock().timeIntervalSince(t0)
            marks = []
            summaryText = ""
            recordingPath = url.path
            isRecording = true
            if auto {
                addEvent(clock().timeIntervalSince(t0), tr("Enregistrement automatique démarré : \(muscle), \(side.rawValue.lowercased())."))
            }
        } catch {
            statusText = tr("Enregistrement impossible : \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        csv?.closeFile()
        marksFile?.closeFile()
        csv = nil
        marksFile = nil

        let dur = max(0, clock().timeIntervalSince(t0) - stats.startT)
        let m1 = stats.n > 0 ? stats.sum1 / Double(stats.n) : 0
        let m2 = stats.n > 0 ? stats.sum2 / Double(stats.n) : 0
        var s = tr("Séance : \(muscle), \(side.rawValue.lowercased()) — \(channelUse.rawValue), \(program.rawValue)\n")
        s += String(format: trd("Durée : %.0f s — %d mesures EMG\n"), dur, stats.n)
        s += String(format: trd("EMG canal 1 : moyenne %.1f µV, maximum %.1f µV\n"), m1, stats.max1)
        s += String(format: trd("EMG canal 2 : moyenne %.1f µV, maximum %.1f µV\n"), m2, stats.max2)
        s += tr("Stimulation (maximum par canal) : \(stats.stimMax[0]) / \(stats.stimMax[1]) / \(stats.stimMax[2]) / \(stats.stimMax[3])\n")
        s += String(format: trd("Temps de stimulation : %.0f s — %d salve(s)\n"), stats.stimActiveSeconds, stats.bursts)
        if !setIntensity.isEmpty { s += tr("Intensité réglée (saisie) : \(setIntensity) mA\n") }
        s += tr("Programme de l'appareil : \(progInfo.name) — \(progInfo.frequency), \(progInfo.width), \(progInfo.rhythm)\n")
        if stats.alertCount > 0 { s += tr("Coupures de stimulation signalées par l'appareil (électrodes ?) : \(stats.alertCount)\n") }
        s += tr("Repères : \(marks.count)\n")
        s += tr("Fichier : \(recordingPath)")
        summaryText = s

        // session sheet for the history
        let snap = runSnap ?? makeSnapshot()
        var rec = SessionRecord(id: recordingSessionId, start: recStartDate)
        rec.csvFile = recBase + ".csv"
        rec.source = autoStarted ? "auto" : "app"
        rec.durationSec = dur
        rec.muscle = muscle
        rec.side = side.rawValue
        rec.channel = channelUse.rawValue
        rec.programKind = program.rawValue
        rec.programName = snap.name == "—" ? "" : snap.name
        rec.frequency = snap.frequency == "—" ? "" : snap.frequency
        rec.width = snap.width == "—" ? "" : snap.width
        rec.rhythm = snap.rhythm == "—" ? "" : snap.rhythm
        rec.ramps = snap.ramps == "—" ? "" : snap.ramps
        rec.programDuration = snap.duration == "—" ? "" : snap.duration
        rec.setIntensity = setIntensity
        rec.maxStim = stats.stimMax
        rec.stimActiveSec = stats.stimActiveSeconds
        rec.stimBursts = stats.bursts
        rec.probe = probe
        rec.reference = reference
        rec.emgMean1 = m1
        rec.emgMean2 = m2
        rec.emgMax1 = stats.max1
        rec.emgMax2 = stats.max2
        rec.emgMedian1 = Stat.percentile(stats.v1, 0.5)
        rec.emgMedian2 = Stat.percentile(stats.v2, 0.5)
        rec.emgP95_1 = Stat.percentile(stats.v1, 0.95)
        rec.emgP95_2 = Stat.percentile(stats.v2, 0.95)
        rec.emgCount = stats.n
        rec.alertCount = stats.alertCount
        rec.note = note
        if autoStarted && dur < 20 {
            // attempt too short (trigger, immediate stop): not kept
            if let u = recCSVURL { try? FileManager.default.removeItem(at: u) }
            if let u = recMarksURL { try? FileManager.default.removeItem(at: u) }
            lastSavedText = String(format: trd("Enregistrement automatique de %.0f s ignoré (trop court)."), dur)
        } else {
            follow.saveSession(rec)
            lastSavedText = tr("Séance ajoutée à l'historique : \(muscle), \(side.rawValue.lowercased()) — \(Int(dur / 60)) min.")
        }
        autoStarted = false
        stoppedSince = nil
        runSnap = nil
    }

    private func writeCSVStimRow(t: Double) {
        let row = String(format: "%.3f,,,%d,%d,%d,%d,%@,%@,%d,%d\n",
                         t - stats.startT, cStim[0], cStim[1], cStim[2], cStim[3],
                         cPhase, cMode, dev.params.remainingSeconds ?? -1, dev.warningCode)
        if let d = row.data(using: .utf8) { csv?.write(d) }
    }

    private func writeCSVRow(t: Double, c1: Double, c2: Double) {
        let row = String(format: "%.3f,%.2f,%.2f,%d,%d,%d,%d,%@,%@,%d,%d\n",
                         t - stats.startT, c1, c2, cStim[0], cStim[1], cStim[2], cStim[3],
                         cPhase, cMode, dev.params.remainingSeconds ?? -1, dev.warningCode)
        if let d = row.data(using: .utf8) { csv?.write(d) }
    }

    func addMark(_ tag: String) {
        let t = clock().timeIntervalSince(t0)
        let m = Mark(t: t, tag: tag, note: markNote)
        marks.append(m)
        if isRecording {
            let row = String(format: "%.3f,%@,%@,%.2f,%.2f,%d,%d,%d,%d\n",
                             t - stats.startT, tag,
                             markNote.replacingOccurrences(of: ",", with: ";"),
                             cEmg1, cEmg2, cStim[0], cStim[1], cStim[2], cStim[3])
            if let d = row.data(using: .utf8) { marksFile?.write(d) }
        }
        markNote = ""
    }

    // MARK: - Thresholds

    /// Records a threshold for the chosen muscle and side. With no value entered, uses the intensity read from the device.
    func noteThreshold() {
        if side == .deux {
            thresholdMessage = tr("Choisis Droite ou Gauche (pas « Les deux ») pour noter un seuil.")
            return
        }
        let typed = thresholdInput.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        var value = 0.0
        if !typed.isEmpty {
            guard let v = Double(typed), v > 0 else {
                thresholdMessage = tr("Valeur illisible : écris un nombre en mA (ex. 19).")
                return
            }
            value = v
        } else if recentStimMax > 0 {
            value = Double(recentStimMax)
        } else {
            thresholdMessage = tr("Aucune stimulation lue ces 5 dernières secondes : écris la valeur en mA.")
            return
        }
        var t = ThresholdRecord(date: clock(), muscle: muscle, side: side.rawValue, mA: value, kind: thresholdKind)
        t.note = thresholdNote
        let ps = makeSnapshot()
        t.program = ps.name == "—" ? "" : ps.name
        t.sessionId = isRecording ? recordingSessionId : ""
        follow.addThreshold(t)
        if isRecording {
            markNote = "\(thresholdKind) \(String(format: "%.0f", value)) mA"
            addMark("Seuil")
        }
        thresholdMessage = String(format: trd("Seuil noté : %.0f mA — %@, %@ (%@)."), value, muscle, side.rawValue.lowercased(), thresholdKind)
        thresholdInput = ""
        thresholdNote = ""
    }

    // MARK: - Standardized EMG test

    func startEMGTest() {
        guard isConnected else {
            testMessage = tr("Connecte d'abord l'appareil (programme EMG seul lancé sur l'appareil).")
            return
        }
        if side == .deux {
            testMessage = tr("Choisis Droite ou Gauche dans la fiche de séance (pas « Les deux »).")
            return
        }
        testT = []
        testV = []
        testResult = nil
        testMessage = ""
        testStart = clock()
        testElapsed = 0
        testRunning = true
        lastCue = ""
        testTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tickEMGTest()
        }
        testTimer = timer
        tickEMGTest()
    }

    func cancelEMGTest() {
        testTimer?.invalidate()
        testTimer = nil
        testRunning = false
        testCue = tr("Test annulé")
    }

    private func tickEMGTest() {
        guard testRunning else { return }
        let el = clock().timeIntervalSince(testStart)
        testElapsed = el
        let cue: String
        switch testProtocol.phase(at: el) {
        case let .baseline(rem):
            cue = tr("REPOS — ne bouge pas")
            testRemaining = rem
        case let .contract(cycle, rem):
            cue = tr("CONTRACTE ! (\(cycle)/\(testProtocol.cycles))")
            testRemaining = rem
        case let .rest(cycle, rem):
            cue = tr("REPOS (\(cycle)/\(testProtocol.cycles))")
            testRemaining = rem
        case .finished:
            finishEMGTest()
            return
        }
        if cue.hasPrefix(trd("CONTRACTE")) != lastCue.hasPrefix(trd("CONTRACTE")) { NSSound.beep() }
        lastCue = cue
        testCue = cue
        // no EMG reading after 4 s: probably not in EMG mode
        if el > 4 && testT.isEmpty {
            cancelEMGTest()
            testMessage = tr("Aucune mesure EMG reçue : lance sur l'appareil un programme EMG (sans stimulation), puis recommence.")
        }
    }

    private func finishEMGTest() {
        testTimer?.invalidate()
        testTimer = nil
        testRunning = false
        testCue = tr("Test terminé")
        testRemaining = 0
        let a = EMGTestAnalyzer.analyze(t: testT, v: testV, proto: testProtocol)
        testResult = a
        var r = EMGTestResult(date: testStart, muscle: muscle, side: side.rawValue, channel: testChannel)
        r.baseline = a.baseline
        r.peak = a.peak
        r.mean = a.mean
        r.holdSec = a.holdSec
        r.cycles = a.cycles.count
        // raw readings kept alongside (so the analysis can be redone)
        let dir = folder.appendingPathComponent("Suivi/tests_bruts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        let name = "test_\(f.string(from: testStart))_\(safe(muscle))_\(safe(side.rawValue)).csv"
        var text = "t_s,emg_uV\n"
        for i in 0..<min(testT.count, testV.count) { text += String(format: "%.3f,%.2f\n", testT[i], testV[i]) }
        try? text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        r.rawFile = name
        if a.peak > 0 {
            follow.addTest(r)
            testMessage = tr("Test enregistré dans l'historique.")
        } else {
            testMessage = tr("Résultat nul (aucune contraction détectée) : non enregistré. ") + a.warnings.joined(separator: " ")
        }
    }

    // MARK: - Debug mode

    private func openFramesLog() {
        framesFile?.closeFile()
        framesFile = nil
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd_HHmmss"
            let url = folder.appendingPathComponent("trames_\(f.string(from: clock())).log")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            framesFile = try FileHandle(forWritingTo: url)
            debugFolderPath = folder.path
            writeFrames("# t_s  n°paquet  longueur  octets(hex) — [longueur, n°, données…]")
        } catch {
            framesFile = nil
        }
    }

    private func writeFrames(_ line: String) {
        if let h = framesFile, let d = (line + "\n").data(using: .utf8) { h.write(d) }
    }

    func handleFrame(_ frame: [UInt8]) {
        guard frame.count >= 2 else { return }
        ensureLogs()
        let t = clock().timeIntervalSince(t0)
        tracker.record(frame: frame, t: t)
        dev.feed(frame: frame)
        detectEvents(t: t)
        let hex = DebugTracker.hex(frame)
        writeFrames(String(format: "%.3f  n°%d  %d  %@", t, Int(frame[1]), frame.count, hex))
        if !debugPaused {
            debugNextId += 1
            debugBuf.append(DebugRow(id: debugNextId, t: t, packetId: Int(frame[1]), hex: hex,
                                     known: DebugTracker.isKnown(id: frame[1]), note: nil))
            if debugBuf.count > 400 { debugBuf.removeFirst(debugBuf.count - 400) }
        }
        publishDebug(force: false)
    }

    private func publishDebug(force: Bool) {
        let now = clock()
        if !force && now.timeIntervalSince(lastDebugPublish) < 0.2 { return }
        lastDebugPublish = now
        publishProgram()
        debugStats = tracker.sortedStats
        if !debugPaused { debugRows = debugBuf }
    }

    /// Timestamped marker (e.g. “NMES program started”) written to the stream and to the frames file.
    func addDebugNote() {
        let text = debugNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return }
        let t = clock().timeIntervalSince(t0)
        writeFrames(String(format: "%.3f  # NOTE : %@", t, text))
        debugNextId += 1
        debugBuf.append(DebugRow(id: debugNextId, t: t, packetId: -1, hex: text, known: true, note: text))
        debugNote = ""
        publishDebug(force: true)
    }

    func debugSummary() -> String {
        return tracker.summary()
    }

    func openDataFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Current program, events, library

    private var libraryFile: URL { folder.appendingPathComponent("bibliotheque_programmes.json") }
    private var savedLibrary: [LibraryProgram] = []

    private func loadLibrary() {
        if let d = try? Data(contentsOf: libraryFile),
           let list = try? JSONDecoder().decode([LibraryProgram].self, from: d) {
            savedLibrary = list
            dev.setLibrary(list)
        }
    }

    private func saveLibrary() {
        let list = dev.libraryList
        guard !list.isEmpty else { return }
        savedLibrary = list
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: libraryFile) }
    }

    private func addEvent(_ t: Double, _ text: String, alert: Bool = false) {
        eventId += 1
        events.append(AppEvent(id: eventId, t: t, text: text, alert: alert))
        if events.count > 100 { events.removeFirst(events.count - 100) }
        writeFrames(String(format: "%.3f  # EVENEMENT : %@", t, text))
        if isRecording {
            let row = String(format: "%.3f,Evenement,%@,%.2f,%.2f,%d,%d,%d,%d\n",
                             t - stats.startT, text.replacingOccurrences(of: ",", with: ";"),
                             cEmg1, cEmg2, cStim[0], cStim[1], cStim[2], cStim[3])
            if let d = row.data(using: .utf8) { marksFile?.write(d) }
            if alert { stats.alertCount += 1 }
        }
    }

    private func describeProgram() -> String {
        let s = makeSnapshot()
        return tr("\(s.name) — \(s.frequency), \(s.width), \(s.rhythm), rampes \(s.ramps), durée \(s.duration)")
    }

    private func detectEvents(t: Double) {
        let now = clock()
        // “output” warning (electrodes disconnected, stimulation cut)
        let w = dev.warningCode
        if w != lastWarningCode {
            if w == DeviceWarning.output.rawValue {
                let msg = tr("Avertissement « sortie » : électrodes déconnectées ? La stimulation est coupée.")
                addEvent(t, msg, alert: true)
                alertText = msg
            } else if lastWarningCode == DeviceWarning.output.rawValue {
                addEvent(t, tr("Avertissement terminé."))
                alertText = nil
            }
            lastWarningCode = w
        }
        // pause / run (the first 3 seconds after connecting are used to read the initial state)
        let settled = t > 3
        if let p = dev.isPaused, p != lastPaused {
            if lastPaused != nil && settled { addEvent(t, p ? tr("Programme en pause (stimulation à 0).") : tr("Programme en marche.")) }
            lastPaused = p
        }
        if let st = dev.isStarted, st != lastStarted {
            if lastStarted != nil && settled { addEvent(t, st ? tr("Programme démarré.") : tr("Programme arrêté.")) }
            lastStarted = st
        }
        if dev.isStarted == true && settled && now.timeIntervalSince(runSnapAt) > 1 {
            runSnap = makeSnapshot()
            runSnapAt = now
        }
        // automatic recording: starts with the program, stops 8 s after it stops
        if autoRecord && isConnected && settled {
            if !isRecording {
                if dev.isStarted == true && !testRunning { beginRecording(auto: true) }
            } else if autoStarted {
                if dev.isStarted == false {
                    if stoppedSince == nil { stoppedSince = now }
                    if let st = stoppedSince, now.timeIntervalSince(st) > 8 { stopRecording() }
                } else {
                    stoppedSince = nil
                }
            }
        }
        // program change, once the values have been stable for 1.5 s
        let pr = dev.params
        if pr.hz != nil, pr.widthUs != nil, pr.workSec != nil {
            let sig = "\(pr.hz ?? 0)|\(pr.widthUs ?? 0)|\(pr.workSec ?? 0)|\(pr.restSec ?? 0)|\(pr.clinicalMode ?? 0)|\(pr.programNumber ?? 0)"
            if sig != progSigPending {
                progSigPending = sig
                progSigSince = now
            } else if sig != progSig && now.timeIntervalSince(progSigSince) > 1.5 {
                addEvent(t, (progSig.isEmpty ? tr("Programme en cours : ") : tr("Programme changé : ")) + describeProgram())
                progSig = sig
            }
        }
        // program library sent by the device (synchronization)
        let n = dev.library.count
        if n != libSeen {
            libSeen = n
            libSince = now
        } else if n > 0 && n != libReported && now.timeIntervalSince(libSince) > 2 {
            libReported = n
            addEvent(t, tr("Bibliothèque de programmes lue : \(n) programmes (noms enregistrés)."))
            saveLibrary()
        }
    }

    private func mmss(_ sec: Int) -> String {
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }

    private func makeSnapshot() -> ProgramSnapshot {
        let p = dev.params
        var s = ProgramSnapshot()
        s.name = dev.displayName()
        if dev.isPaused == true {
            s.status = "En pause"
        } else if dev.isStarted == false {
            s.status = "Arrêté"
        } else if dev.isStarted == true {
            s.status = (dev.isWork == true) ? "Stimulation" : "Repos (écoute EMG)"
        }
        if let hz = p.hz { s.frequency = "\(hz) Hz" }
        if let w = p.widthUs { s.width = "\(w) µs" }
        if let work = p.workSec {
            if p.isContinuous {
                s.rhythm = "continu"
            } else {
                s.rhythm = tr("\(work) s travail / \(p.restSec ?? 0) s repos")
            }
        }
        if let u = p.rampUp, let d = p.rampDown { s.ramps = String(format: "%.1f s / %.1f s", u, d) }
        if let m = p.programMinutes { s.duration = tr("\(m) min") }
        if let r = p.remainingSeconds { s.remaining = mmss(r) }
        return s
    }

    private func publishProgram() {
        let s = makeSnapshot()
        if s != progInfo { progInfo = s }
    }
}
