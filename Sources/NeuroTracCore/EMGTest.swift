import Foundation

/// Standardized EMG test: rest, then several identical contractions separated by rest.
/// Same protocol every time = results comparable from one session to the next.
public struct EMGTestProtocol: Equatable {
    public var baselineSec = 10.0
    public var contractSec = 5.0
    public var restSec = 10.0
    public var cycles = 3

    public init() {}

    public var totalSec: Double { return baselineSec + Double(cycles) * (contractSec + restSec) }

    public enum Phase: Equatable {
        case baseline(remaining: Double)
        case contract(cycle: Int, remaining: Double)
        case rest(cycle: Int, remaining: Double)
        case finished
    }

    /// Phase at time t (seconds since the start of the test), to display the instruction.
    public func phase(at t: Double) -> Phase {
        if t < baselineSec { return .baseline(remaining: baselineSec - t) }
        let cycleLen = contractSec + restSec
        let u = t - baselineSec
        let i = Int(u / cycleLen)
        if i >= cycles { return .finished }
        let w = u - Double(i) * cycleLen
        if w < contractSec { return .contract(cycle: i + 1, remaining: contractSec - w) }
        return .rest(cycle: i + 1, remaining: cycleLen - w)
    }
}

public struct EMGCycleResult: Equatable {
    public var peak: Double
    public var mean: Double
    public var holdSec: Double
    public var sampleCount: Int
}

public struct EMGTestAnalysis: Equatable {
    public var baseline: Double
    public var peak: Double
    public var mean: Double
    public var holdSec: Double
    public var cycles: [EMGCycleResult]
    public var warnings: [String]
}

public enum EMGTestAnalyzer {
    private static func median(_ a: [Double]) -> Double {
        if a.isEmpty { return 0 }
        let s = a.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    /// Moving average over `window` seconds (smooths isolated spikes).
    private static func smooth(t: [Double], v: [Double], window: Double) -> [Double] {
        var out = [Double](repeating: 0, count: v.count)
        var lo = 0
        var sum = 0.0
        var hi = 0
        for i in 0..<v.count {
            while hi < v.count && t[hi] <= t[i] {
                sum += v[hi]
                hi += 1
            }
            while lo < i && t[lo] < t[i] - window {
                sum -= v[lo]
                lo += 1
            }
            out[i] = sum / Double(max(1, hi - lo))
        }
        return out
    }

    /// `t` = seconds since the start of the test, `v` = EMG of the tested channel (µV).
    public static func analyze(t: [Double], v: [Double], proto: EMGTestProtocol = EMGTestProtocol()) -> EMGTestAnalysis {
        var warnings: [String] = []
        let n = min(t.count, v.count)
        let tt = Array(t[0..<n])
        let vv = Array(v[0..<n])
        if n < 30 {
            warnings.append(tr("Très peu de mesures reçues (\(n)) : l'appareil était-il bien en mode EMG ?"))
            return EMGTestAnalysis(baseline: 0, peak: 0, mean: 0, holdSec: 0, cycles: [], warnings: warnings)
        }
        let sm = smooth(t: tt, v: vv, window: 0.5)

        var base: [Double] = []
        for i in 0..<n where tt[i] < proto.baselineSec { base.append(vv[i]) }
        if base.count < 5 { warnings.append(tr("Repos initial presque vide : le repos de départ n'est pas fiable.")) }
        let baseline = median(base)

        var results: [EMGCycleResult] = []
        for c in 0..<proto.cycles {
            let a = proto.baselineSec + Double(c) * (proto.contractSec + proto.restSec)
            let b = a + proto.contractSec
            var idx: [Int] = []
            for i in 0..<n where tt[i] >= a && tt[i] < b { idx.append(i) }
            if idx.count < 5 {
                warnings.append(tr("Contraction \(c + 1) : trop peu de mesures."))
                results.append(EMGCycleResult(peak: 0, mean: 0, holdSec: 0, sampleCount: idx.count))
                continue
            }
            var peak = 0.0
            var sum = 0.0
            for i in idx {
                peak = max(peak, sm[i] - baseline)
                sum += vv[i]
            }
            let mean = max(0, sum / Double(idx.count) - baseline)
            // time spent above half the peak: sum of the intervals between consecutive readings
            var hold = 0.0
            if peak > 0 {
                for k in 1..<idx.count {
                    let i = idx[k]
                    let j = idx[k - 1]
                    let gap = min(tt[i] - tt[j], 1.0)
                    if sm[i] - baseline >= 0.5 * peak { hold += gap }
                }
            }
            results.append(EMGCycleResult(peak: peak, mean: mean, holdSec: hold, sampleCount: idx.count))
        }

        let valid = results.filter { $0.sampleCount >= 5 }
        let peak = valid.map { $0.peak }.max() ?? 0
        let mean = valid.isEmpty ? 0 : valid.map { $0.mean }.reduce(0, +) / Double(valid.count)
        let hold = valid.isEmpty ? 0 : valid.map { $0.holdSec }.reduce(0, +) / Double(valid.count)
        if baseline > 0 && peak < baseline {
            warnings.append(tr("Le pic de contraction ne dépasse pas le niveau de repos : signal peu distinct (à titre indicatif)."))
        }
        return EMGTestAnalysis(baseline: baseline, peak: peak, mean: mean, holdSec: hold, cycles: results, warnings: warnings)
    }
}
