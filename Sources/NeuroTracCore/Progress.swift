import Foundation

public enum Stat {
    /// Percentile (0 to 1) of a list of values, by interpolation; 0 if the list is empty.
    public static func percentile(_ values: [Double], _ p: Double) -> Double {
        if values.isEmpty { return 0 }
        let s = values.sorted()
        let pos = min(max(p, 0), 1) * Double(s.count - 1)
        let lo = Int(pos.rounded(.down))
        let hi = min(s.count - 1, lo + 1)
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }
}

public struct SeriesPoint: Equatable {
    public var date: Date
    public var value: Double
}

public struct ProgressMetric: Identifiable, Hashable {
    public let id: String
    public let label: String
    public let unit: String
    /// True if the chosen muscle applies to this indicator (false for observations)
    public let usesMuscle: Bool
}

public struct Trend: Equatable {
    public var count: Int
    public var first: Double
    public var last: Double
    public var days: Double
    public var slopePerWeek: Double
    public var changePercent: Double?
}

/// Progression curve computation. No clinical interpretation here: only numbers and their evolution.
public enum ProgressStats {
    public static var metrics: [ProgressMetric] {
        var m: [ProgressMetric] = [
            ProgressMetric(id: "threshold", label: tr("Seuil de stimulation"), unit: "mA", usesMuscle: true),
            ProgressMetric(id: "stim_max", label: tr("Intensité maximale en séance"), unit: "mA", usesMuscle: true),
            ProgressMetric(id: "emg_median", label: tr("EMG médian en séance"), unit: "µV", usesMuscle: true),
            ProgressMetric(id: "emg_p95", label: tr("EMG 95e centile en séance"), unit: "µV", usesMuscle: true),
            ProgressMetric(id: "emg_mean", label: tr("EMG moyen en séance (sensible aux parasites)"), unit: "µV", usesMuscle: true),
            ProgressMetric(id: "emg_max", label: tr("EMG maximum en séance (sensible aux parasites)"), unit: "µV", usesMuscle: true),
            ProgressMetric(id: "test_peak", label: tr("Test EMG — pic"), unit: "µV", usesMuscle: true),
            ProgressMetric(id: "test_mean", label: tr("Test EMG — moyenne"), unit: "µV", usesMuscle: true),
            ProgressMetric(id: "test_hold", label: tr("Test EMG — tenue"), unit: "s", usesMuscle: true),
            ProgressMetric(id: "stim_bursts", label: tr("Salves de stimulation par séance"), unit: "", usesMuscle: true),
            ProgressMetric(id: "assess_total", label: tr("Évaluation — score global"), unit: "", usesMuscle: true),
            ProgressMetric(id: "assess_fast", label: tr("Évaluation — contractions rapides"), unit: "", usesMuscle: true),
            ProgressMetric(id: "assess_tonic", label: tr("Évaluation — contractions tenues (tonique)"), unit: "", usesMuscle: true),
            ProgressMetric(id: "assess_endurance", label: tr("Évaluation — endurance"), unit: "", usesMuscle: true),
            ProgressMetric(id: "assess_base_before", label: tr("Évaluation — repos avant"), unit: "", usesMuscle: true),
            ProgressMetric(id: "assess_base_after", label: tr("Évaluation — repos après"), unit: "", usesMuscle: true),
        ]
        for s in Catalog.sidedScales {
            m.append(ProgressMetric(id: "obs:" + s.key, label: tr("Observation — ") + trd(s.label), unit: "/5", usesMuscle: false))
        }
        return m
    }

    public static func metric(id: String) -> ProgressMetric? {
        return metrics.first { $0.id == id }
    }

    /// Series of an indicator for a muscle and a side (“Droite” or “Gauche”), sorted by date.
    public static func series(metric: String, muscle: String, side: String,
                              sessions: [SessionRecord], thresholds: [ThresholdRecord],
                              tests: [EMGTestResult], observations: [ObservationRecord],
                              assessments: [AssessmentRecord] = [],
                              thresholdKind: String? = nil) -> [SeriesPoint] {
        var pts: [SeriesPoint] = []
        switch metric {
        case "threshold":
            for t in thresholds where t.muscle == muscle && t.side == side && (thresholdKind == nil || t.kind == thresholdKind) {
                pts.append(SeriesPoint(date: t.date, value: t.mA))
            }
        case "stim_max":
            for s in sessions where s.muscle == muscle && s.side == side && s.maxStimOverall > 0 {
                pts.append(SeriesPoint(date: s.start, value: Double(s.maxStimOverall)))
            }
        case "emg_median":
            for s in sessions where s.muscle == muscle && s.side == side && s.emgCount > 0 {
                pts.append(SeriesPoint(date: s.start, value: s.primaryEMG.median))
            }
        case "emg_p95":
            for s in sessions where s.muscle == muscle && s.side == side && s.emgCount > 0 {
                pts.append(SeriesPoint(date: s.start, value: s.primaryEMG.p95))
            }
        case "emg_mean":
            for s in sessions where s.muscle == muscle && s.side == side && s.emgCount > 0 {
                pts.append(SeriesPoint(date: s.start, value: s.primaryEMG.mean))
            }
        case "emg_max":
            for s in sessions where s.muscle == muscle && s.side == side && s.emgCount > 0 {
                pts.append(SeriesPoint(date: s.start, value: s.primaryEMG.max))
            }
        case "test_peak":
            for t in tests where t.muscle == muscle && t.side == side { pts.append(SeriesPoint(date: t.date, value: t.peak)) }
        case "test_mean":
            for t in tests where t.muscle == muscle && t.side == side { pts.append(SeriesPoint(date: t.date, value: t.mean)) }
        case "test_hold":
            for t in tests where t.muscle == muscle && t.side == side { pts.append(SeriesPoint(date: t.date, value: t.holdSec)) }
        case "stim_bursts":
            for s in sessions where s.muscle == muscle && s.side == side && s.stimBursts >= 0 {
                pts.append(SeriesPoint(date: s.start, value: Double(s.stimBursts)))
            }
        case "assess_total", "assess_fast", "assess_tonic", "assess_endurance", "assess_base_before", "assess_base_after":
            for a in assessments where a.muscle == muscle && a.side == side {
                let v: Double
                switch metric {
                case "assess_total": v = a.total
                case "assess_fast": v = a.fast
                case "assess_tonic": v = a.tonic
                case "assess_endurance": v = a.endurance
                case "assess_base_before": v = a.baselineBefore
                default: v = a.baselineAfter
                }
                pts.append(SeriesPoint(date: a.date, value: v))
            }
        default:
            if metric.hasPrefix("obs:") {
                let key = Catalog.sidedKey(String(metric.dropFirst(4)), side: side)
                for o in observations {
                    if let v = o.scales[key] { pts.append(SeriesPoint(date: o.date, value: Double(v))) }
                }
            }
        }
        return pts.sorted { $0.date < $1.date }
    }

    public static func trend(_ pts: [SeriesPoint]) -> Trend? {
        guard pts.count >= 2, let f = pts.first, let l = pts.last else { return nil }
        let day = 86400.0
        let xs = pts.map { $0.date.timeIntervalSince(f.date) / day }
        let ys = pts.map { $0.value }
        let n = Double(pts.count)
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for i in 0..<pts.count {
            num += (xs[i] - mx) * (ys[i] - my)
            den += (xs[i] - mx) * (xs[i] - mx)
        }
        let slopeDay = den > 0 ? num / den : 0
        let pct: Double? = f.value != 0 ? (l.value - f.value) / abs(f.value) * 100 : nil
        return Trend(count: pts.count, first: f.value, last: l.value, days: xs.last ?? 0,
                     slopePerWeek: slopeDay * 7, changePercent: pct)
    }

    public static func describe(_ t: Trend?, unit: String) -> String {
        guard let t = t else { return tr("Pas assez de mesures pour une tendance (il en faut au moins 2).") }
        let u = unit.isEmpty ? "" : " " + unit
        var s = String(format: trd("%d mesures sur %.0f jours : de %.1f%@ à %.1f%@"), t.count, t.days, t.first, u, t.last, u)
        if let p = t.changePercent { s += String(format: " (%+.0f %%)", p) }
        s += String(format: trd(". Tendance : %+.2f%@ par semaine."), t.slopePerWeek, u)
        return s
    }
}
