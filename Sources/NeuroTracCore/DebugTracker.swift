import Foundation

/// Statistics of a packet type (same identifier), for debug mode.
public struct PacketStat {
    public let id: UInt8
    public var count = 0
    public var firstT = 0.0
    public var lastT = 0.0
    /// Last frame received: [length, identifier, data…]
    public var last: [UInt8] = []
    /// Byte positions that have already changed value since the start.
    public var changed: Set<Int> = []
    /// Last time (in seconds) each position changed.
    public var lastChangeT: [Int: Double] = [:]

    public init(id: UInt8) { self.id = id }

    /// Packets per second (0 until there are at least two).
    public var rate: Double {
        guard count > 1, lastT > firstT else { return 0 }
        return Double(count - 1) / (lastT - firstT)
    }
}

/// Tracks received frames to spot which bytes move: start a program or change
/// the intensity on the device, and see which packet / byte reacts.
public struct DebugTracker {
    public private(set) var stats: [UInt8: PacketStat] = [:]

    public init() {}

    /// Identifiers whose content is already decoded by the app (EMG 1–7, stimulation 11).
    public static func isKnown(id: UInt8) -> Bool {
        return (1...7).contains(id) || id == 11
    }

    public static func hex(_ bytes: [UInt8]) -> String {
        return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public mutating func record(frame: [UInt8], t: Double) {
        guard frame.count >= 2 else { return }
        let id = frame[1]
        var s = stats[id] ?? PacketStat(id: id)
        if s.count == 0 { s.firstT = t }
        if s.last.count == frame.count {
            // the first two bytes (length, identifier) are ignored
            var i = 2
            while i < frame.count {
                if s.last[i] != frame[i] {
                    s.changed.insert(i)
                    s.lastChangeT[i] = t
                }
                i += 1
            }
        }
        s.count += 1
        s.lastT = t
        s.last = frame
        stats[id] = s
    }

    public var sortedStats: [PacketStat] {
        return stats.values.sorted { $0.id < $1.id }
    }

    /// Text summary (to copy / send): one packet per line.
    public func summary() -> String {
        var lines: [String] = []
        for s in sortedStats {
            let pos = s.changed.sorted().map(String.init).joined(separator: ",")
            lines.append(String(format: trd("n°%d%@  reçus=%d  %.1f/s  octets_changeants=[%@]  dernier=%@"),
                                Int(s.id), DebugTracker.isKnown(id: s.id) ? "" : tr(" (inconnu)"),
                                s.count, s.rate, pos, DebugTracker.hex(s.last)))
        }
        return lines.joined(separator: "\n")
    }
}
