import XCTest
@testable import NeuroTracCore

final class DataTests: XCTestCase {
    override func setUp() { Lang.override = .fr }
    func tmp() -> URL {
        let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ntl-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testPatientAge() {
        var p = PatientProfile.exemple
        XCTAssertEqual(p.fullName, "Jane DOE")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 13))!
        XCTAssertEqual(p.ageDescription(on: d), "6 ans 8 mois")
        p.birthDate = ""
        XCTAssertEqual(p.ageDescription(on: d), "")
    }

    func testOldJSONWithMissingFieldsStillLoads() throws {
        let json = #"{"id":"x","start":"2026-10-13T10:00:00Z","muscle":"Mollet"}"#
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let s = try d.decode(SessionRecord.self, from: Data(json.utf8))
        XCTAssertEqual(s.muscle, "Mollet")
        XCTAssertEqual(s.maxStim, [0, 0, 0, 0])
        XCTAssertEqual(s.stimActiveSec, -1)
    }

    func testStoreRoundTripAndBackup() {
        let root = tmp()
        let st = DataStore(root: root)
        XCTAssertEqual(st.patient.firstName, "Jane")
        var p = st.patient
        p.heightCm = "105"
        st.setPatient(p)
        var s = SessionRecord(id: "a", start: Date(timeIntervalSince1970: 1_790_000_000))
        s.muscle = "Mollet"
        s.side = "Droite"
        st.upsertSession(s)
        s.note = "test"
        st.upsertSession(s)
        st.addThreshold(ThresholdRecord(date: Date(), muscle: "Mollet", side: "Droite", mA: 19, kind: "Premier mouvement"))
        let st2 = DataStore(root: root)
        XCTAssertEqual(st2.patient.heightCm, "105")
        XCTAssertEqual(st2.sessions.count, 1)
        XCTAssertEqual(st2.sessions[0].note, "test")
        XCTAssertEqual(st2.thresholds.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("seances.json.bak").path))
    }

    func testCorruptFileIsSetAsideNotOverwritten() {
        let root = tmp()
        try? "pas du json".write(to: root.appendingPathComponent("seances.json"), atomically: true, encoding: .utf8)
        let st = DataStore(root: root)
        XCTAssertEqual(st.sessions.count, 0)
        XCTAssertEqual(st.warnings.count, 1)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        XCTAssertTrue(names.contains { $0.hasPrefix("seances.json.illisible") })
    }

    let csvV3 = """
    # date=2026-10-13T13:41:27Z
    # muscle=Mollet
    # cote=Droite
    # canal=Canal 2
    # programme=SCTS1
    # type_programme_saisi=Stimulation seule
    # frequence=35 Hz
    # largeur_impulsion=300 µs
    # rythme=12 s travail / 8 s repos
    # intensite_reglee_mA=6
    # note=test, avec virgule
    t_s,emg1_uV,emg2_uV,stim1_mA,stim2_mA,stim3_mA,stim4_mA,phase,mode,restant_s,avertissement
    0.100,2.00,3.00,0,0,0,0,Repos,EMG,1800,1
    0.600,,,0,6,0,0,Travail,Stimulation,1799,1
    1.100,4.00,9.00,0,0,0,0,Repos,EMG,1799,1

    """

    func testCSVParseAndRecord() {
        let r = SessionCSV.record(fileName: "20261013_154127_Mollet_Droite.csv", text: csvV3, fallbackDate: Date())!
        XCTAssertEqual(r.id, "csv:20261013_154127_Mollet_Droite.csv")
        XCTAssertEqual(r.muscle, "Mollet")
        XCTAssertEqual(r.side, "Droite")
        XCTAssertEqual(r.programName, "SCTS1")
        XCTAssertEqual(r.maxStim, [0, 6, 0, 0])
        XCTAssertEqual(r.emgCount, 2)
        XCTAssertEqual(r.emgMean2, 6.0, accuracy: 0.001)
        XCTAssertEqual(r.emgMax2, 9.0, accuracy: 0.001)
        XCTAssertEqual(r.durationSec, 1.0, accuracy: 0.001)
        XCTAssertEqual(r.channel, "Canal 2")
        XCTAssertEqual(r.primaryEMG.max, 9.0, accuracy: 0.001)
        XCTAssertEqual(r.note, "test, avec virgule")
    }

    func testCSVOldFormatWithoutHeaderNames() {
        let old = "t_s,emg1_uV,emg2_uV\n0.1,1,2\n0.2,3,4\n"
        let r = SessionCSV.record(fileName: "20260101_101010_Quadriceps_Gauche.csv", text: old, fallbackDate: Date())
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.maxStim, [0, 0, 0, 0])
    }

    func testImportNoDuplicatesAndIgnoreAfterDelete() {
        let root = tmp()
        let data = tmp()
        try? csvV3.write(to: data.appendingPathComponent("20261013_154127_Mollet_Droite.csv"), atomically: true, encoding: .utf8)
        try? "t_s,repere,note\n0.1,Mouvement,x\n".write(to: data.appendingPathComponent("20261013_154127_Mollet_Droite_reperes.csv"), atomically: true, encoding: .utf8)
        let st = DataStore(root: root)
        XCTAssertEqual(st.importCSVs(from: data), 1)
        XCTAssertEqual(st.importCSVs(from: data), 0)
        XCTAssertEqual(st.sessions.count, 1)
        st.deleteSession(id: st.sessions[0].id)
        XCTAssertEqual(st.importCSVs(from: data), 0)
        XCTAssertEqual(DataStore(root: root).sessions.count, 0)
    }

    func testPhotosAttachAndRemove() {
        let root = tmp()
        let st = DataStore(root: root)
        st.upsertSession(SessionRecord(id: "s1", start: Date()))
        let n = st.addPhoto(jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]), sessionId: "s1")
        XCTAssertNotNil(n)
        XCTAssertEqual(st.session(id: "s1")?.photos.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: st.photoURL(n!).path))
        st.removePhoto(name: n!, sessionId: "s1")
        XCTAssertEqual(st.session(id: "s1")?.photos.count, 0)
        XCTAssertNil(st.addPhoto(jpeg: Data(), sessionId: "inconnue"))
    }

    // MARK: - Test EMG

    /// Synthetic signal: rest at 2 µV, three 5 s contractions at 20 µV (4 s of them at full level)
    func synth(peak: Double, rate: Double = 20) -> ([Double], [Double]) {
        let proto = EMGTestProtocol()
        var t: [Double] = []
        var v: [Double] = []
        var x = 0.0
        while x < proto.totalSec {
            var val = 2.0
            if case .contract(_, let rem) = proto.phase(at: x) {
                let elapsed = proto.contractSec - rem
                val = elapsed < 4 ? peak : 2.0
            }
            t.append(x)
            v.append(val)
            x += 1 / rate
        }
        return (t, v)
    }

    func testProtocolPhases() {
        let p = EMGTestProtocol()
        XCTAssertEqual(p.totalSec, 55)
        XCTAssertEqual(p.phase(at: 3), .baseline(remaining: 7))
        XCTAssertEqual(p.phase(at: 11), .contract(cycle: 1, remaining: 4))
        XCTAssertEqual(p.phase(at: 16), .rest(cycle: 1, remaining: 9))
        XCTAssertEqual(p.phase(at: 26), .contract(cycle: 2, remaining: 4))
        XCTAssertEqual(p.phase(at: 55.5), .finished)
    }

    func testEMGAnalysis() {
        let (t, v) = synth(peak: 20)
        let a = EMGTestAnalyzer.analyze(t: t, v: v)
        XCTAssertEqual(a.baseline, 2.0, accuracy: 0.01)
        XCTAssertEqual(a.peak, 18.0, accuracy: 0.5)
        XCTAssertEqual(a.cycles.count, 3)
        XCTAssertEqual(a.holdSec, 4.0, accuracy: 0.6)
        XCTAssertEqual(a.mean, 18.0 * 0.8, accuracy: 1.0)
        XCTAssertTrue(a.warnings.isEmpty)
        let (t2, v2) = synth(peak: 40)
        let b = EMGTestAnalyzer.analyze(t: t2, v: v2)
        XCTAssertGreaterThan(b.peak, a.peak * 1.8)
    }

    func testEMGAnalysisWithNoData() {
        let a = EMGTestAnalyzer.analyze(t: [0, 1], v: [1, 1])
        XCTAssertEqual(a.peak, 0)
        XCTAssertFalse(a.warnings.isEmpty)
    }

    // MARK: - Progression

    func testSeriesAndTrend() {
        let day = 86400.0
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        var th: [ThresholdRecord] = []
        for (i, ma) in [28.0, 24.0, 19.0].enumerated() {
            th.append(ThresholdRecord(date: t0.addingTimeInterval(Double(i) * 7 * day), muscle: "Mollet", side: "Droite", mA: ma, kind: "Premier mouvement"))
        }
        th.append(ThresholdRecord(date: t0, muscle: "Mollet", side: "Gauche", mA: 21, kind: "Premier mouvement"))
        let right = ProgressStats.series(metric: "threshold", muscle: "Mollet", side: "Droite", sessions: [], thresholds: th, tests: [], observations: [])
        XCTAssertEqual(right.map { $0.value }, [28, 24, 19])
        let left = ProgressStats.series(metric: "threshold", muscle: "Mollet", side: "Gauche", sessions: [], thresholds: th, tests: [], observations: [])
        XCTAssertEqual(left.count, 1)
        XCTAssertNil(ProgressStats.trend(left))
        let tr = ProgressStats.trend(right)!
        XCTAssertEqual(tr.count, 3)
        XCTAssertEqual(tr.days, 14, accuracy: 0.001)
        XCTAssertEqual(tr.slopePerWeek, -4.5, accuracy: 0.001)
        XCTAssertEqual(tr.changePercent!, (19.0 - 28.0) / 28.0 * 100, accuracy: 0.01)
        XCTAssertTrue(ProgressStats.describe(tr, unit: "mA").contains("3 mesures"))
        XCTAssertTrue(ProgressStats.describe(nil, unit: "mA").contains("au moins 2"))
    }

    func testObservationSeriesUseSide() {
        var o = ObservationRecord(date: Date())
        o.scales[Catalog.sidedKey("pied_dorsal", side: "Droite")] = 3
        o.scales[Catalog.sidedKey("pied_dorsal", side: "Gauche")] = 4
        let r = ProgressStats.series(metric: "obs:pied_dorsal", muscle: "", side: "Droite", sessions: [], thresholds: [], tests: [], observations: [o])
        XCTAssertEqual(r.map { $0.value }, [3])
        XCTAssertEqual(Catalog.label(forScaleKey: "pied_dorsal_G"), "Relevé du pied (flexion dorsale) (gauche)")
    }

    func testSessionMetricsUseChosenChannel() {
        var s = SessionRecord(id: "z", start: Date())
        s.muscle = "Mollet"
        s.side = "Droite"
        s.channel = "Canal 2"
        s.emgCount = 5
        s.emgMean1 = 1
        s.emgMean2 = 7
        s.emgMax2 = 12
        let r = ProgressStats.series(metric: "emg_mean", muscle: "Mollet", side: "Droite", sessions: [s], thresholds: [], tests: [], observations: [])
        XCTAssertEqual(r.first?.value, 7)
    }

    func testDownsampleKeepsPeaks() {
        let t = (0..<1000).map { Double($0) }
        var v = [Double](repeating: 1, count: 1000)
        v[500] = 50
        let d = SessionCSV.downsample(t: t, v: v, maxPoints: 100)
        XCTAssertLessThanOrEqual(d.count, 101)
        XCTAssertTrue(d.contains { $0.1 == 50 })
    }
}

final class StatTests: XCTestCase {
    override func setUp() { Lang.override = .fr }
    func testPercentile() {
        XCTAssertEqual(Stat.percentile([], 0.5), 0)
        XCTAssertEqual(Stat.percentile([5], 0.95), 5)
        XCTAssertEqual(Stat.percentile([1, 2, 3, 4, 100], 0.5), 3)
        XCTAssertEqual(Stat.percentile([0, 10], 0.5), 5, accuracy: 0.0001)
        XCTAssertLessThan(Stat.percentile([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1000], 0.95), 60)
    }

    func testCSVImportComputesMedianAndP95() {
        var csv = "t_s,emg1_uV,emg2_uV,stim1_mA\n"
        for i in 0..<20 { csv += "\(Double(i)),1,\(i == 19 ? 1999 : 10),0\n" }
        let r = SessionCSV.record(fileName: "20261013_100000_Mollet_Droite.csv", text: csv, fallbackDate: Date())!
        XCTAssertEqual(r.emgMedian2, 10, accuracy: 0.001)
        XCTAssertEqual(r.emgMax2, 1999, accuracy: 0.001)
        XCTAssertLessThan(r.emgP95_2, 1000)
    }

    func testAnalProbeAssessmentsAndBursts() throws {
        XCTAssertEqual(Catalog.sidesFor(muscle: "Sphincter anal (sonde)"), ["Sans côté"])
        XCTAssertEqual(Catalog.sidesFor(muscle: "Mollet"), ["Droite", "Gauche"])
        XCTAssertEqual(Catalog.muscles[5], "Mollet")

        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ntl-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let st = DataStore(root: root)
        var b1 = AssessmentRecord(date: Date(timeIntervalSince1970: 1_790_000_000), label: "B1")
        b1.fast = 0; b1.endurance = 8; b1.tonic = 0; b1.baselineBefore = 88; b1.baselineAfter = 90; b1.total = 19.7
        var b2 = AssessmentRecord(date: Date(timeIntervalSince1970: 1_791_000_000), label: "B2")
        b2.fast = 6; b2.endurance = 13; b2.tonic = 0; b2.baselineBefore = 90; b2.baselineAfter = 90; b2.total = 22.5
        st.upsertAssessment(b1)
        st.upsertAssessment(b2)
        st.upsertAssessment(b2)
        XCTAssertEqual(st.assessments.count, 2)
        let again = DataStore(root: root)
        XCTAssertEqual(again.assessments.count, 2)
        XCTAssertEqual(again.assessments.first?.label, "B2")

        var s = SessionRecord(id: "p", start: Date(timeIntervalSince1970: 1_790_100_000))
        s.muscle = "Sphincter anal (sonde)"
        s.side = Catalog.noSide
        s.probe = "sonde pédiatrique"
        s.reference = "sacrum"
        s.stimBursts = 16
        again.upsertSession(s)
        let third = DataStore(root: root)
        XCTAssertEqual(third.sessions.first?.stimBursts, 16)
        XCTAssertEqual(third.sessions.first?.probe, "sonde pédiatrique")

        let mu = "Sphincter anal (sonde)"
        let tot = ProgressStats.series(metric: "assess_total", muscle: mu, side: Catalog.noSide, sessions: [], thresholds: [], tests: [], observations: [], assessments: again.assessments)
        XCTAssertEqual(tot.map { $0.value }, [19.7, 22.5])
        let fast = ProgressStats.series(metric: "assess_fast", muscle: mu, side: Catalog.noSide, sessions: [], thresholds: [], tests: [], observations: [], assessments: again.assessments)
        XCTAssertEqual(fast.map { $0.value }, [0, 6])
        // a “no side” assessment does not appear for a lateral muscle
        let none = ProgressStats.series(metric: "assess_total", muscle: "Mollet", side: "Droite", sessions: [], thresholds: [], tests: [], observations: [], assessments: again.assessments)
        XCTAssertTrue(none.isEmpty)
        let br = ProgressStats.series(metric: "stim_bursts", muscle: mu, side: Catalog.noSide, sessions: third.sessions, thresholds: [], tests: [], observations: [])
        XCTAssertEqual(br.map { $0.value }, [16])
        // old session without the field: “unknown”, hence excluded from the curve
        let json = #"{"id":"x","start":"2026-10-13T10:00:00Z","muscle":"Mollet","side":"Droite"}"#
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let old = try d.decode(SessionRecord.self, from: Data(json.utf8))
        XCTAssertEqual(old.stimBursts, -1)
        XCTAssertEqual(old.probe, "")
    }
}
