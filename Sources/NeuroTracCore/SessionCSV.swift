import Foundation

/// Reading session CSV files (v0.1 to v0.4): “# key=value” header then measurement rows.
public struct CSVSessionData {
    public var meta: [String: String] = [:]
    public var t: [Double] = []
    /// NaN when the row has no EMG reading (stimulation-only row)
    public var emg1: [Double] = []
    public var emg2: [Double] = []
    public var stim: [[Int]] = [[], [], [], []]
    public var hasEMGColumns = false
    public var rowCount: Int { return t.count }
}

public enum SessionCSV {
    public static func parse(_ text: String) -> CSVSessionData {
        var d = CSVSessionData()
        var cols: [String: Int] = [:]
        for raw in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(raw)
            if line.hasPrefix("#") {
                let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if let eq = body.firstIndex(of: "=") {
                    let k = String(body[body.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
                    let v = String(body[body.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                    d.meta[k] = v
                }
                continue
            }
            let f = line.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
            if cols.isEmpty {
                // first non-comment line = column names
                if f.first?.hasPrefix("t_s") == true {
                    for (i, n) in f.enumerated() { cols[n.trimmingCharacters(in: .whitespaces)] = i }
                    d.hasEMGColumns = cols["emg1_uV"] != nil
                    continue
                } else {
                    return d
                }
            }
            guard let ti = cols["t_s"], ti < f.count, let tv = Double(f[ti]) else { continue }
            func num(_ name: String) -> Double {
                if let i = cols[name], i < f.count, let v = Double(f[i].trimmingCharacters(in: .whitespaces)) { return v }
                return Double.nan
            }
            d.t.append(tv)
            d.emg1.append(num("emg1_uV"))
            d.emg2.append(num("emg2_uV"))
            for k in 0..<4 {
                let v = num("stim\(k + 1)_mA")
                d.stim[k].append(v.isNaN ? 0 : Int(v))
            }
        }
        return d
    }

    private static func isoDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    /// Date read from the file name “yyyymmdd_hhmmss…”
    private static func dateFromName(_ name: String) -> Date? {
        guard name.count >= 15 else { return nil }
        let prefix = String(name.prefix(15))
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.date(from: prefix)
    }

    private static func mapSide(_ s: String) -> String {
        let l = s.lowercased()
        if l.hasPrefix("dro") || l == "d" { return "Droite" }
        if l.hasPrefix("gau") || l == "g" { return "Gauche" }
        if l.contains("deux") { return "Les deux" }
        if l.hasPrefix("sans") { return Catalog.noSide }
        return s
    }

    /// Builds the session sheet from the CSV. The identifier depends on the file name:
    /// importing the same file twice never creates a duplicate.
    public static func record(fileName: String, text: String, fallbackDate: Date) -> SessionRecord? {
        let d = parse(text)
        guard d.rowCount > 0 else { return nil }
        let start = d.meta["date"].flatMap(isoDate) ?? dateFromName(fileName) ?? fallbackDate
        var r = SessionRecord(id: "csv:" + fileName, start: start)
        r.csvFile = fileName
        r.source = "import"
        r.muscle = d.meta["muscle"] ?? ""
        r.side = mapSide(d.meta["cote"] ?? "")
        r.channel = d.meta["canal"] ?? ""
        r.programKind = d.meta["type_programme_saisi"] ?? d.meta["programme_saisi"] ?? ""
        r.programName = d.meta["programme"] ?? ""
        r.frequency = d.meta["frequence"] ?? ""
        r.width = d.meta["largeur_impulsion"] ?? ""
        r.rhythm = d.meta["rythme"] ?? ""
        r.ramps = d.meta["rampes"] ?? ""
        r.programDuration = d.meta["duree_programme"] ?? ""
        r.setIntensity = d.meta["intensite_reglee_mA"] ?? ""
        r.note = d.meta["note"] ?? ""
        r.probe = d.meta["sonde"] ?? ""
        r.reference = d.meta["reference"] ?? ""
        r.durationSec = max(0, (d.t.last ?? 0) - (d.t.first ?? 0))
        var n1 = 0, n2 = 0
        var s1 = 0.0, s2 = 0.0
        var m1 = 0.0, m2 = 0.0
        var v1: [Double] = []
        var v2: [Double] = []
        for i in 0..<d.rowCount {
            let a = d.emg1[i]
            let b = d.emg2[i]
            if !a.isNaN { n1 += 1; s1 += a; m1 = max(m1, a); v1.append(a) }
            if !b.isNaN { n2 += 1; s2 += b; m2 = max(m2, b); v2.append(b) }
        }
        r.emgMedian1 = Stat.percentile(v1, 0.5)
        r.emgMedian2 = Stat.percentile(v2, 0.5)
        r.emgP95_1 = Stat.percentile(v1, 0.95)
        r.emgP95_2 = Stat.percentile(v2, 0.95)
        r.emgCount = max(n1, n2)
        r.emgMean1 = n1 > 0 ? s1 / Double(n1) : 0
        r.emgMean2 = n2 > 0 ? s2 / Double(n2) : 0
        r.emgMax1 = m1
        r.emgMax2 = m2
        r.maxStim = (0..<4).map { d.stim[$0].max() ?? 0 }
        return r
    }

    /// Reduces a series to about `maxPoints` points (for charts), keeping the maximum of each bucket.
    public static func downsample(t: [Double], v: [Double], maxPoints: Int) -> [(Double, Double)] {
        var pts: [(Double, Double)] = []
        for i in 0..<min(t.count, v.count) where !v[i].isNaN { pts.append((t[i], v[i])) }
        if pts.count <= maxPoints || maxPoints < 2 { return pts }
        let step = Double(pts.count) / Double(maxPoints)
        var out: [(Double, Double)] = []
        var i = 0.0
        while Int(i) < pts.count {
            let a = Int(i)
            let b = min(pts.count, Int(i + step))
            let chunk = pts[a..<max(a + 1, b)]
            if let best = chunk.max(by: { $0.1 < $1.1 }) { out.append((chunk.first!.0, best.1)) }
            i += step
        }
        return out
    }
}
