import XCTest
@testable import NeuroTracCore

final class ReportTests: XCTestCase {
    override func setUp() { Lang.override = .fr }
    func testWinAnsiAndWidth() {
        XCTAssertEqual(PDFDoc.winAnsi("é°µ"), [0xE9, 0xB0, 0xB5])
        XCTAssertEqual(PDFDoc.winAnsi("a→b").count, 3)
        let d = PDFDoc(title: "t")
        XCTAssertEqual(d.textWidth("AAAA", size: 10), 4 * 667 / 100.0, accuracy: 0.01)
        XCTAssertEqual(d.wrap("un deux trois quatre", maxWidth: 40, size: 10).count > 1, true)
        XCTAssertTrue(d.fit("un texte vraiment très long", maxWidth: 50, size: 10).hasSuffix("…"))
    }

    func testJPEGInfo() {
        // Hard-coded minimal 2x3 JPEG (SOI, SOF0, EOI)
        let b: [UInt8] = [0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x03, 0x00, 0x02, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xD9]
        let i = JPEGInfo.parse(Data(b))
        XCTAssertEqual(i?.width, 2)
        XCTAssertEqual(i?.height, 3)
        XCTAssertNil(JPEGInfo.parse(Data([1, 2, 3, 4, 5])))
    }

    func testPDFStructureValid() {
        let d = PDFDoc(title: "Titre é")
        d.newPage()
        d.text("Bonjour (test) \\ é", x: 50, y: 50, size: 12)
        d.newPage()
        d.line(x1: 10, y1: 10, x2: 100, y2: 100)
        let data = d.data()
        let s = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(s.hasPrefix("%PDF-1.4"))
        XCTAssertTrue(s.contains("/Count 2"))
        XCTAssertTrue(s.hasSuffix("%%EOF\n"))
    }
}

/// Generates real sample PDFs when NTL_SAMPLE_DIR is set (visual check, not an automatic test).
final class ReportSampleTests: XCTestCase {
    override func setUp() { Lang.override = ProcessInfo.processInfo.environment["NTL_SAMPLE_LANG"] == "en" ? .en : .fr }
    func testWriteSamples() throws {
        guard let dir = ProcessInfo.processInfo.environment["NTL_SAMPLE_DIR"] else { return }
        let out = URL(fileURLWithPath: dir)
        let day = 86400.0
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        var sessions: [SessionRecord] = []
        var thr: [ThresholdRecord] = []
        var tests: [EMGTestResult] = []
        for i in 0..<6 {
            var s = SessionRecord(id: "s\(i)", start: t0.addingTimeInterval(Double(i) * 3 * day))
            s.muscle = i % 2 == 0 ? "Mollet" : "Quadriceps"
            s.side = i % 3 == 0 ? "Gauche" : "Droite"
            s.channel = "Canal 2"
            s.programName = "SCTS1"
            s.frequency = "35 Hz"
            s.width = "300 µs"
            s.rhythm = "12 s travail / 8 s repos"
            s.durationSec = 1800 - Double(i) * 30
            s.maxStim = [0, 6 + i, 0, 0]
            s.emgCount = 100
            s.emgMean2 = 4 + Double(i)
            s.emgMax2 = 20 + Double(i) * 3
            sessions.append(s)
            for (side, base) in [("Droite", 28.0), ("Gauche", 22.0)] {
                var t = ThresholdRecord(date: t0.addingTimeInterval(Double(i) * 3 * day), muscle: "Mollet", side: side, mA: base - Double(i) * 1.5, kind: "Premier mouvement")
                t.note = "Le pied monte, électrodes 5×5 cm"
                thr.append(t)
            }
            for side in ["Droite", "Gauche"] {
                var r = EMGTestResult(date: t0.addingTimeInterval(Double(i) * 3 * day), muscle: "Mollet", side: side, channel: 1)
                r.baseline = 2; r.peak = 10 + Double(i) * (side == "Droite" ? 2 : 1); r.mean = 6; r.holdSec = 3
                tests.append(r)
            }
        }
        var o = ObservationRecord(date: t0)
        o.scales["pied_dorsal_D"] = 3
        o.scales["pied_dorsal_G"] = 4
        o.flags["chair_poule"] = true
        o.text = "Chair de poule aux deux jambes pendant la stimulation."
        // Synthetic session CSV
        var csv = "# date=2026-10-13T13:41:27Z\nt_s,emg1_uV,emg2_uV,stim1_mA,stim2_mA,stim3_mA,stim4_mA,phase,mode,restant_s,avertissement\n"
        for k in 0..<600 {
            let t = Double(k) * 0.5
            let work = Int(t) % 20 < 12
            if work { csv += String(format: "%.3f,,,0,%d,0,0,Travail,Stimulation,1800,1\n", t, 6) }
            else { csv += String(format: "%.3f,%.2f,%.2f,0,0,0,0,Repos,EMG,1800,1\n", t, 3 + sin(t), 8 + 5 * sin(t / 3)) }
        }
        let data = SessionCSV.parse(csv)
        XCTAssertGreaterThan(data.rowCount, 500)
        let pdfA = Reports.sessionReport(patient: PatientProfile.exemple, session: sessions[1], csv: data, thresholds: thr, photos: [], generated: t0)
        try pdfA.write(to: out.appendingPathComponent("seance.pdf"))
        var photos: [JPEGInfo] = []
        if let jd = try? Data(contentsOf: out.appendingPathComponent("photo.jpg")), let j = JPEGInfo.parse(jd) { photos = [j, j, j] }
        var sp = sessions[1]; sp.photos = ["a.jpg", "b.jpg", "c.jpg"]
        let pdfB = Reports.sessionReport(patient: PatientProfile.exemple, session: sp, csv: data, thresholds: thr, photos: photos, generated: t0)
        try pdfB.write(to: out.appendingPathComponent("seance_photos.pdf"))
        var assess: [AssessmentRecord] = []
        for (i, v) in [(0, 19.7), (1, 22.5)] {
            var a = AssessmentRecord(date: t0.addingTimeInterval(Double(i) * 20 * day), label: "B\(i + 1)")
            a.fast = Double(i) * 6; a.endurance = 8 + Double(i) * 5; a.baselineBefore = 88 + Double(i) * 2; a.baselineAfter = 90; a.total = v
            assess.append(a)
        }
        sp.probe = "sonde pédiatrique"; sp.reference = "sacrum"; sp.stimBursts = 16
        let pdfC = Reports.periodReport(patient: PatientProfile.exemple, from: t0.addingTimeInterval(-day), to: t0.addingTimeInterval(40 * day), sessions: sessions, thresholds: thr, tests: tests, observations: [o], assessments: assess, generated: t0)
        try pdfC.write(to: out.appendingPathComponent("periode.pdf"))
    }
}
