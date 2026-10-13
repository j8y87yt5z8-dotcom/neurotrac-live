import Foundation

// Layout of PDF reports (session and period): titles, tables, curves, photos.

public enum Fmt {
    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: Lang.current == .en ? "en_GB" : "fr_FR")
        f.dateFormat = pattern
        return f
    }
    public static func day(_ d: Date) -> String { return formatter("dd/MM/yyyy").string(from: d) }
    public static func shortDay(_ d: Date) -> String { return formatter("dd/MM").string(from: d) }
    public static func dateTime(_ d: Date) -> String { return formatter(tr("d MMMM yyyy 'à' HH:mm")).string(from: d) }
    public static func minutesSeconds(_ sec: Double) -> String {
        let s = Int(sec.rounded())
        return String(format: trd("%d min %02d s"), s / 60, s % 60)
    }
    public static func num(_ v: Double, _ digits: Int = 1) -> String {
        return String(format: "%.\(digits)f", v)
    }
}

public struct ChartSeries {
    public var name: String
    public var color: PDFColor
    public var points: [(Double, Double)]
    public init(name: String, color: PDFColor, points: [(Double, Double)]) {
        self.name = name
        self.color = color
        self.points = points
    }
}

public final class ReportLayout {
    public let doc: PDFDoc
    public let margin = 42.0
    public var y = 0.0
    private let footerText: String
    private var contentWidth: Double { return doc.width - 2 * margin }
    private var bottomLimit: Double { return doc.height - 50 }

    public init(title: String, footer: String) {
        doc = PDFDoc(title: title)
        footerText = footer
        doc.newPage()
        y = margin
    }

    public func newPage() {
        doc.newPage()
        y = margin
    }

    public func ensure(_ h: Double) {
        if y + h > bottomLimit { newPage() }
    }

    public func space(_ h: Double) { y += h }

    public func title(_ s: String, subtitle: String? = nil) {
        doc.rect(x: 0, y: 0, w: doc.width, h: 70, fill: PDFColor(0.12, 0.30, 0.55))
        doc.text(s, x: margin, y: 36, size: 20, bold: true, color: .white)
        if let sub = subtitle { doc.text(sub, x: margin, y: 56, size: 10.5, color: PDFColor(0.88, 0.92, 1.0)) }
        y = 92
    }

    public func h1(_ s: String) {
        ensure(40)
        space(8)
        doc.text(s, x: margin, y: y + 12, size: 13.5, bold: true, color: PDFColor(0.12, 0.30, 0.55))
        doc.line(x1: margin, y1: y + 18, x2: doc.width - margin, y2: y + 18, width: 0.8, color: PDFColor(0.12, 0.30, 0.55))
        y += 28
    }

    public func h2(_ s: String) {
        ensure(26)
        space(4)
        doc.text(s, x: margin, y: y + 10, size: 11, bold: true)
        y += 18
    }

    public func paragraph(_ s: String, size: Double = 10, color: PDFColor = .black, bold: Bool = false) {
        let lines = doc.wrap(s, maxWidth: contentWidth, size: size, bold: bold)
        for l in lines {
            ensure(size + 5)
            doc.text(l, x: margin, y: y + size, size: size, bold: bold, color: color)
            y += size + 4
        }
        y += 2
    }

    /// “label: value” pairs on two columns.
    public func keyValues(_ pairs: [(String, String)]) {
        let colW = contentWidth / 2
        var i = 0
        while i < pairs.count {
            ensure(30)
            var rowH = 16.0
            for c in 0..<2 where i + c < pairs.count {
                let (k, v) = pairs[i + c]
                let x = margin + Double(c) * colW
                doc.text(k, x: x, y: y + 8, size: 8, color: .gray)
                let lines = doc.wrap(v.isEmpty ? "—" : v, maxWidth: colW - 12, size: 10)
                for (n, l) in lines.prefix(3).enumerated() {
                    doc.text(l, x: x, y: y + 20 + Double(n) * 12, size: 10)
                }
                rowH = max(rowH, 14 + Double(min(lines.count, 3)) * 12 + 6)
            }
            y += rowH
            i += 2
        }
        y += 4
    }

    public func table(headers: [String], rows: [[String]], widths: [Double]) {
        let total = widths.reduce(0, +)
        let scale = contentWidth / total
        let w = widths.map { $0 * scale }
        func drawHeader() {
            doc.rect(x: margin, y: y, w: contentWidth, h: 16, fill: PDFColor.lightGray)
            var x = margin
            for (i, h) in headers.enumerated() {
                doc.text(doc.fit(h, maxWidth: w[i] - 6, size: 8.5, bold: true), x: x + 3, y: y + 11.5, size: 8.5, bold: true)
                x += w[i]
            }
            y += 16
        }
        ensure(48)
        drawHeader()
        for (n, r) in rows.enumerated() {
            if y + 15 > bottomLimit {
                newPage()
                drawHeader()
            }
            if n % 2 == 1 { doc.rect(x: margin, y: y, w: contentWidth, h: 15, fill: PDFColor.veryLight) }
            var x = margin
            for (i, cell) in r.enumerated() where i < w.count {
                doc.text(doc.fit(cell, maxWidth: w[i] - 6, size: 8.5), x: x + 3, y: y + 10.5, size: 8.5)
                x += w[i]
            }
            y += 15
        }
        y += 6
    }

    private static func niceStep(_ range: Double, ticks: Int) -> Double {
        let raw = range / Double(max(1, ticks))
        let mag = pow(10, floor(log10(raw)))
        let norm = raw / mag
        let step: Double = norm < 1.5 ? 1 : (norm < 3 ? 2 : (norm < 7 ? 5 : 10))
        return step * mag
    }

    /// Curve(s) with axes. `xLabel` converts an X-axis value to text (date, seconds…).
    public func lineChart(title: String, unit: String, series: [ChartSeries], height: Double = 150, xLabel: (Double) -> String) {
        ensure(height + 36)
        doc.text(title, x: margin, y: y + 10, size: 10, bold: true)
        // legend
        var lx = margin + doc.textWidth(title, size: 10, bold: true) + 16
        for s in series {
            doc.rect(x: lx, y: y + 3, w: 8, h: 8, fill: s.color)
            doc.text(s.name, x: lx + 12, y: y + 10, size: 8.5)
            lx += 12 + doc.textWidth(s.name, size: 8.5) + 14
        }
        y += 16

        let left = margin + 34
        let right = doc.width - margin - 8
        let top = y + 4
        let bottom = y + height - 18
        let all = series.flatMap { $0.points }
        doc.rect(x: left, y: top, w: right - left, h: bottom - top, stroke: PDFColor.lightGray, lineWidth: 0.6)
        if all.isEmpty {
            doc.text(tr("Aucune mesure"), x: left + 10, y: (top + bottom) / 2, size: 9, color: .gray)
            y += height + 6
            return
        }
        var xmin = all.map { $0.0 }.min() ?? 0
        var xmax = all.map { $0.0 }.max() ?? 1
        var ymin = min(0, all.map { $0.1 }.min() ?? 0)
        var ymax = all.map { $0.1 }.max() ?? 1
        if xmax - xmin < 1e-9 { xmin -= 0.5; xmax += 0.5 }
        if ymax - ymin < 1e-9 { ymax = ymin + 1 }
        let step = ReportLayout.niceStep(ymax - ymin, ticks: 4)
        ymax = ceil(ymax / step) * step
        ymin = floor(ymin / step) * step
        func px(_ x: Double) -> Double { return left + (x - xmin) / (xmax - xmin) * (right - left) }
        func py(_ v: Double) -> Double { return bottom - (v - ymin) / (ymax - ymin) * (bottom - top) }

        var tick = ymin
        while tick <= ymax + step * 0.001 {
            let yy = py(tick)
            doc.line(x1: left, y1: yy, x2: right, y2: yy, width: 0.3, color: PDFColor.lightGray)
            let lab = step >= 1 ? String(format: "%.0f", tick) : String(format: "%.1f", tick)
            doc.text(lab, x: left - 4 - doc.textWidth(lab, size: 7.5), y: yy + 2.5, size: 7.5, color: .gray)
            tick += step
        }
        doc.text(unit, x: margin, y: top + 8, size: 7.5, color: .gray)
        for k in 0...4 {
            let xv = xmin + (xmax - xmin) * Double(k) / 4
            let lab = xLabel(xv)
            let xx = px(xv)
            doc.text(lab, x: min(max(left, xx - doc.textWidth(lab, size: 7.5) / 2), right - doc.textWidth(lab, size: 7.5)), y: bottom + 11, size: 7.5, color: .gray)
        }
        for s in series {
            let pts = s.points.sorted { $0.0 < $1.0 }.map { (px($0.0), py($0.1)) }
            doc.polyline(pts, width: 1.2, color: s.color)
            if pts.count <= 60 { for p in pts { doc.circle(cx: p.0, cy: p.1, r: 2.2, fill: s.color) } }
        }
        y += height + 6
    }

    public func photos(_ list: [JPEGInfo], captions: [String]) {
        let boxW = (contentWidth - 12) / 2
        let boxH = 190.0
        var i = 0
        while i < list.count {
            ensure(boxH + 24)
            for c in 0..<2 where i + c < list.count {
                let img = list[i + c]
                let ratio = Double(img.width) / Double(img.height)
                var w = boxW
                var h = w / ratio
                if h > boxH { h = boxH; w = h * ratio }
                let x = margin + Double(c) * (boxW + 12) + (boxW - w) / 2
                doc.image(img, x: x, y: y, w: w, h: h)
                if i + c < captions.count {
                    doc.text(doc.fit(captions[i + c], maxWidth: boxW, size: 8), x: margin + Double(c) * (boxW + 12), y: y + boxH + 12, size: 8, color: .gray)
                }
            }
            y += boxH + 20
            i += 2
        }
    }

    /// Adds “Page i / n” and the footer notice on every page. Call last.
    public func finish() -> Data {
        let n = doc.pageCount
        for i in 0..<n {
            doc.withPage(i) {
                doc.line(x1: margin, y1: doc.height - 36, x2: doc.width - margin, y2: doc.height - 36, width: 0.4, color: PDFColor.lightGray)
                doc.text(doc.fit(footerText, maxWidth: contentWidth - 70, size: 7.5), x: margin, y: doc.height - 24, size: 7.5, color: .gray)
                let p = tr("Page \(i + 1) / \(n)")
                doc.text(p, x: doc.width - margin - doc.textWidth(p, size: 7.5), y: doc.height - 24, size: 7.5, color: .gray)
            }
        }
        return doc.data()
    }
}

public enum Reports {
    static var disclaimer: String { return tr("NeuroTrac Live — mesures de suivi, à interpréter avec l'équipe soignante ; pas un diagnostic.") }

    private static func patientBlock(_ l: ReportLayout, _ p: PatientProfile, at date: Date) {
        var pairs: [(String, String)] = [(tr("Patient"), p.fullName)]
        let age = p.ageDescription(on: date)
        if !p.birthDate.isEmpty { pairs.append((tr("Né(e) le / âge"), p.birthDate.split(separator: "-").reversed().joined(separator: "/") + (age.isEmpty ? "" : " — " + age))) }
        if !p.diagnosis.isEmpty { pairs.append((tr("Atteinte"), p.diagnosis + (p.lesionLevel.isEmpty ? "" : tr(", niveau ") + p.lesionLevel))) }
        if !p.heightCm.isEmpty || !p.weightKg.isEmpty {
            pairs.append((tr("Taille / poids"), [p.heightCm.isEmpty ? "" : p.heightCm + " cm", p.weightKg.isEmpty ? "" : p.weightKg + " kg"].filter { !$0.isEmpty }.joined(separator: " — ")))
        }
        if !p.referents.isEmpty { pairs.append((tr("Soignants"), p.referents)) }
        l.keyValues(pairs)
    }

    // MARK: - Session report

    public static func sessionReport(patient: PatientProfile, session s: SessionRecord, csv: CSVSessionData?,
                                     thresholds: [ThresholdRecord], photos: [JPEGInfo], generated: Date = Date()) -> Data {
        let l = ReportLayout(title: tr("Rapport de séance — \(patient.fullName)"), footer: disclaimer)
        l.title(tr("Rapport de séance"), subtitle: "\(patient.fullName) — \(Fmt.dateTime(s.start))")
        patientBlock(l, patient, at: s.start)

        l.h1(tr("Séance"))
        let place = [trd(s.muscle), trd(s.side)].filter { !$0.isEmpty }.joined(separator: " — ")
        var pairs: [(String, String)] = [
            (tr("Zone"), place),
            (tr("Canal(aux) utilisé(s)"), trd(s.channel)),
            (tr("Sonde / électrodes"), s.probe),
            (tr("Électrode de référence"), s.reference),
            (tr("Durée enregistrée"), Fmt.minutesSeconds(s.durationSec)),
            (tr("Appareil"), s.device),
            (tr("Programme (lu sur l'appareil)"), s.programName),
            (tr("Fréquence / largeur d'impulsion"), [s.frequency, s.width].filter { !$0.isEmpty }.joined(separator: " — ")),
            (tr("Rythme"), s.rhythm),
            (tr("Rampes montée / descente"), s.ramps),
            (tr("Durée du programme"), s.programDuration),
            (tr("Type de séance (saisi)"), trd(s.programKind)),
            (tr("Intensité réglée (saisie)"), s.setIntensity.isEmpty ? "" : s.setIntensity + " mA"),
            (tr("Intensité maximale reçue de l'appareil"), s.maxStimOverall > 0 ? tr("\(s.maxStim.map { String($0) }.joined(separator: " / ")) mA (canaux 1 à 4)") : "—"),
        ]
        if s.stimActiveSec >= 0 { pairs.append((tr("Temps de stimulation"), Fmt.minutesSeconds(s.stimActiveSec))) }
        if s.stimBursts >= 0 { pairs.append((tr("Salves de stimulation"), "\(s.stimBursts)")) }
        if s.emgCount > 0 {
            pairs.append((tr("EMG canal 1 (médiane / 95e centile / max)"), "\(Fmt.num(s.emgMedian1)) / \(Fmt.num(s.emgP95_1)) / \(Fmt.num(s.emgMax1)) µV"))
            pairs.append((tr("EMG canal 2 (médiane / 95e centile / max)"), "\(Fmt.num(s.emgMedian2)) / \(Fmt.num(s.emgP95_2)) / \(Fmt.num(s.emgMax2)) µV"))
        }
        if s.alertCount > 0 { pairs.append((tr("Coupures signalées par l'appareil"), tr("\(s.alertCount) (électrodes déconnectées ?)"))) }
        l.keyValues(pairs)
        if !s.note.isEmpty {
            l.h2(tr("Note"))
            l.paragraph(s.note)
        }

        if let d = csv, d.rowCount > 1 {
            l.h1(tr("Courbes"))
            let c1 = SessionCSV.downsample(t: d.t, v: d.emg1, maxPoints: 400)
            let c2 = SessionCSV.downsample(t: d.t, v: d.emg2, maxPoints: 400)
            var ser: [ChartSeries] = []
            if c1.contains(where: { $0.1 > 0 }) { ser.append(ChartSeries(name: tr("EMG 1"), color: .blue, points: c1)) }
            if c2.contains(where: { $0.1 > 0 }) { ser.append(ChartSeries(name: tr("EMG 2"), color: .orange, points: c2)) }
            if !ser.isEmpty {
                l.lineChart(title: tr("EMG"), unit: "µV", series: ser) { Fmt.num($0 / 60, 1) + " min" }
            }
            var stimSer: [ChartSeries] = []
            for k in 0..<4 where (d.stim[k].max() ?? 0) > 0 {
                let pts = zip(d.t, d.stim[k]).map { ($0, Double($1)) }
                stimSer.append(ChartSeries(name: tr("Canal \(k + 1)"), color: PDFColor.palette[k], points: SessionCSV.downsample(t: pts.map { $0.0 }, v: pts.map { $0.1 }, maxPoints: 400)))
            }
            if !stimSer.isEmpty {
                l.lineChart(title: tr("Stimulation"), unit: "mA", series: stimSer) { Fmt.num($0 / 60, 1) + " min" }
            }
        }

        let sameDay = thresholds.filter { $0.muscle == s.muscle && $0.side == s.side && Calendar.current.isDate($0.date, inSameDayAs: s.start) }
        if !sameDay.isEmpty {
            l.h1(tr("Seuils notés ce jour-là"))
            l.table(headers: [tr("Heure"), tr("Seuil"), tr("Type"), tr("Note")],
                    rows: sameDay.sorted { $0.date < $1.date }.map { [Fmt.dateTime($0.date).components(separatedBy: trd(" à ")).last ?? "", Fmt.num($0.mA) + " mA", trd($0.kind), $0.note] },
                    widths: [50, 50, 130, 220])
        }

        if !photos.isEmpty {
            l.h1(tr("Photos de placement"))
            l.photos(photos, captions: s.photos)
        }
        l.space(8)
        l.paragraph(tr("Rapport généré le \(Fmt.dateTime(generated))."), size: 8, color: .gray)
        return l.finish()
    }

    // MARK: - Period report

    public static func periodReport(patient: PatientProfile, from: Date, to: Date,
                                    sessions allSessions: [SessionRecord], thresholds allThr: [ThresholdRecord],
                                    tests allTests: [EMGTestResult], observations allObs: [ObservationRecord],
                                    assessments allAssess: [AssessmentRecord] = [],
                                    generated: Date = Date()) -> Data {
        let sessions = allSessions.filter { $0.start >= from && $0.start <= to }.sorted { $0.start < $1.start }
        let thr = allThr.filter { $0.date >= from && $0.date <= to }
        let tests = allTests.filter { $0.date >= from && $0.date <= to }
        let obs = allObs.filter { $0.date >= from && $0.date <= to }
        let assess = allAssess.filter { $0.date >= from && $0.date <= to }

        let l = ReportLayout(title: tr("Rapport de suivi — \(patient.fullName)"), footer: disclaimer)
        l.title(tr("Rapport de suivi"), subtitle: "\(patient.fullName) — " + tr("du \(Fmt.day(from)) au \(Fmt.day(to))"))
        patientBlock(l, patient, at: to)

        l.h1(tr("Résumé de la période"))
        let totalSec = sessions.reduce(0) { $0 + $1.durationSec }
        l.keyValues([
            (tr("Séances enregistrées"), "\(sessions.count)"),
            (tr("Durée totale"), Fmt.minutesSeconds(totalSec)),
            (tr("Seuils notés"), "\(thr.count)"),
            (tr("Tests EMG"), "\(tests.count)"),
            (tr("Fiches d'observations"), "\(obs.count)"),
            (tr("Évaluations plancher pelvien"), "\(assess.count)"),
        ])

        // summary by area
        var zones: [String: [SessionRecord]] = [:]
        for s in sessions { zones[(s.muscle.isEmpty ? "?" : s.muscle) + "|" + s.side, default: []].append(s) }
        if !zones.isEmpty {
            l.h2(tr("Par muscle et côté"))
            let rows: [[String]] = zones.keys.sorted().map { k in
                let list = zones[k] ?? []
                let parts = k.split(separator: "|", omittingEmptySubsequences: false).map { String($0) }
                let maxMA = list.map { $0.maxStimOverall }.max() ?? 0
                let emgMax = list.map { $0.primaryEMG.p95 }.max() ?? 0
                return [trd(parts[0]), parts.count > 1 ? trd(parts[1]) : "", "\(list.count)",
                        Fmt.minutesSeconds(list.reduce(0) { $0 + $1.durationSec }),
                        maxMA > 0 ? "\(maxMA) mA" : "—", emgMax > 0 ? Fmt.num(emgMax) + " µV" : "—"]
            }
            l.table(headers: [tr("Muscle"), tr("Côté"), tr("Séances"), tr("Durée"), tr("Intensité max"), tr("EMG 95e c.")], rows: rows, widths: [110, 60, 50, 90, 80, 80])
        }

        // progression curves: one per muscle that has measurements, right vs left
        var muscles = Set<String>()
        for t in thr { muscles.insert(t.muscle) }
        for t in tests { muscles.insert(t.muscle) }
        for a in assess { muscles.insert(a.muscle) }
        let xlab: (Double) -> String = { Fmt.shortDay(Date(timeIntervalSince1970: $0)) }
        func twoSides(_ metric: String, _ muscle: String) -> [ChartSeries] {
            var out: [ChartSeries] = []
            let colors: [PDFColor] = [PDFColor.blue, PDFColor.orange]
            for (i, side) in Catalog.sidesFor(muscle: muscle).enumerated() {
                let color = colors[i % 2]
                let pts = ProgressStats.series(metric: metric, muscle: muscle, side: side, sessions: sessions, thresholds: thr, tests: tests, observations: obs, assessments: assess)
                if !pts.isEmpty { out.append(ChartSeries(name: trd(side), color: color, points: pts.map { ($0.date.timeIntervalSince1970, $0.value) })) }
            }
            return out
        }
        func trendLines(_ metric: String, _ muscle: String, unit: String) {
            for side in Catalog.sidesFor(muscle: muscle) {
                let pts = ProgressStats.series(metric: metric, muscle: muscle, side: side, sessions: sessions, thresholds: thr, tests: tests, observations: obs, assessments: assess)
                if pts.count >= 1 {
                    l.paragraph(trd(side) + (Lang.current == .en ? ": " : " : ") + ProgressStats.describe(ProgressStats.trend(pts), unit: unit), size: 8.5, color: .gray)
                }
            }
        }
        if !muscles.isEmpty { l.h1(tr("Progression")) }
        for m in muscles.sorted() {
            let th = twoSides("threshold", m)
            if !th.isEmpty {
                l.lineChart(title: tr("\(m) — seuil de stimulation"), unit: "mA", series: th, xLabel: xlab)
                trendLines("threshold", m, unit: "mA")
            }
            let tp = twoSides("test_peak", m)
            if !tp.isEmpty {
                l.lineChart(title: tr("\(m) — test EMG, pic"), unit: "µV", series: tp, xLabel: xlab)
                trendLines("test_peak", m, unit: "µV")
            }
            let at = twoSides("assess_total", m)
            if !at.isEmpty {
                l.lineChart(title: tr("\(m) — évaluation, score global"), unit: "", series: at, xLabel: xlab)
            }
        }
        if !thr.isEmpty {
            l.paragraph(tr("Un seuil plus bas signifie qu'il faut moins de courant pour obtenir la même réponse ; la comparaison n'a de sens qu'avec les mêmes électrodes, le même programme et le même appareil."), size: 8.5, color: .gray)
        }

        if !tests.isEmpty {
            l.h1(tr("Tests EMG standardisés"))
            l.table(headers: [tr("Date"), tr("Muscle"), tr("Côté"), tr("Repos"), tr("Pic"), tr("Moyenne"), tr("Tenue")],
                    rows: tests.sorted { $0.date < $1.date }.map { [Fmt.day($0.date), trd($0.muscle), trd($0.side), Fmt.num($0.baseline) + " µV", Fmt.num($0.peak) + " µV", Fmt.num($0.mean) + " µV", Fmt.num($0.holdSec) + " s"] },
                    widths: [62, 100, 55, 62, 62, 66, 50])
        }

        if !assess.isEmpty {
            l.h1(tr("Évaluations du plancher pelvien"))
            l.table(headers: [tr("Date"), tr("Nom"), tr("Rapides"), tr("Tenues"), tr("Endurance"), tr("Repos av."), tr("Repos ap."), tr("Global")],
                    rows: assess.sorted { $0.date < $1.date }.map { [Fmt.day($0.date), $0.label, Fmt.num($0.fast), Fmt.num($0.tonic), Fmt.num($0.endurance), Fmt.num($0.baselineBefore), Fmt.num($0.baselineAfter), Fmt.num($0.total)] },
                    widths: [62, 50, 52, 52, 58, 56, 56, 48])
            l.paragraph(tr("Scores saisis à partir de l'évaluation faite avec l'appareil ou le soignant ; l'interprétation revient à l'équipe soignante."), size: 8.5, color: .gray)
        }

        if let last = obs.max(by: { $0.date < $1.date }) {
            l.h1(tr("Dernière fiche d'observations (\(Fmt.day(last.date)))"))
            var rows: [[String]] = []
            for it in Catalog.sidedScales {
                let d = last.scales[Catalog.sidedKey(it.key, side: "Droite")]
                let g = last.scales[Catalog.sidedKey(it.key, side: "Gauche")]
                if d != nil || g != nil { rows.append([trd(it.label), d.map { "\($0)/5" } ?? "—", g.map { "\($0)/5" } ?? "—"]) }
            }
            if !rows.isEmpty { l.table(headers: [tr("Élément"), tr("Droite"), tr("Gauche")], rows: rows, widths: [250, 70, 70]) }
            let yes = Catalog.flags.filter { last.flags[$0.key] == true }.map { trd($0.label) }
            if !yes.isEmpty { l.paragraph(tr("Observé : ") + yes.joined(separator: Lang.current == .en ? "; " : " ; ") + ".", size: 9) }
            if !last.text.isEmpty { l.paragraph(last.text, size: 9) }
        }

        if !sessions.isEmpty {
            l.h1(tr("Liste des séances"))
            l.table(headers: [tr("Date"), tr("Muscle"), tr("Côté"), tr("Programme"), tr("Durée"), tr("mA max"), tr("EMG méd.")],
                    rows: sessions.map { [Fmt.day($0.start), trd($0.muscle), trd($0.side), $0.programName, Fmt.minutesSeconds($0.durationSec), $0.maxStimOverall > 0 ? "\($0.maxStimOverall)" : "—", $0.emgCount > 0 ? Fmt.num($0.primaryEMG.median) : "—"] },
                    widths: [58, 92, 50, 90, 62, 44, 54])
        }
        l.space(8)
        l.paragraph(tr("Rapport généré le \(Fmt.dateTime(generated))."), size: 8, color: .gray)
        return l.finish()
    }
}
