import Foundation

// Protocol of the NeuroTrac MyoPlus 4 Pro (“V4” family), established by observing the
// device's own Bluetooth traffic. Read-only: the app only sends HELO, the PIN code and PING.

public enum NTProtocol {
    /// CRC-CCITT (polynomial 0x1021, initial value 0).
    public static func crc16(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for b in data {
            var t: UInt16 = ((crc >> 8) ^ UInt16(b)) & 0xFF
            t ^= t >> 4
            crc = (crc << 8) ^ (t << 12) ^ (t << 5) ^ t
        }
        return crc
    }

    /// Builds a frame: F8, length, identifier, data, zeros, CRC16 (low byte first).
    public static func makePacket(id: UInt8, data: [UInt8]) -> [UInt8] {
        let num = max(12, data.count + 1)
        var arr = [UInt8](repeating: 0, count: num + 4)
        arr[0] = 0xF8
        arr[1] = UInt8(num)
        arr[2] = id
        for (i, b) in data.enumerated() { arr[3 + i] = b }
        let crc = crc16(Array(arr[2..<(2 + num)]))
        arr[num + 2] = UInt8(crc & 0xFF)
        arr[num + 3] = UInt8(crc >> 8)
        return arr
    }

    /// Text message (HELO, PING, PIN code…) sent in a frame with identifier 100.
    public static func text(_ s: String) -> [UInt8] {
        return makePacket(id: 100, data: Array(s.utf8))
    }

    public static let pinRequest: [UInt8] = Array("PINREQ".utf8)
    public static let pinAccepted: [UInt8] = Array("PINACC".utf8)
}

public extension Array where Element == UInt8 {
    /// Position of the first occurrence of a byte sequence.
    func indexOfSequence(_ seq: [UInt8]) -> Int? {
        if seq.isEmpty || count < seq.count { return nil }
        var i = 0
        while i + seq.count <= count {
            if self[i] == seq[0] {
                var ok = true
                var j = 1
                while j < seq.count {
                    if self[i + j] != seq[j] { ok = false; break }
                    j += 1
                }
                if ok { return i }
            }
            i += 1
        }
        return nil
    }
}

/// Splits the byte stream into valid frames (F8 header + CRC).
/// A returned frame has the form [length, identifier, data…].
public struct FrameExtractor {
    private var buf: [UInt8] = []

    public init() {}

    public mutating func feed(_ data: [UInt8]) -> [[UInt8]] {
        buf.append(contentsOf: data)
        var frames: [[UInt8]] = []
        var i = 0
        while i < buf.count {
            if buf[i] != 0xF8 { i += 1; continue }
            if buf.count - i < 4 { break }
            let n = Int(buf[i + 1])
            if n == 0 || buf[i + 2] == 0 { i += 1; continue }
            if i + n + 4 > buf.count { break }  // incomplete frame: wait for the rest
            let crc = UInt16(buf[i + n + 2]) | (UInt16(buf[i + n + 3]) << 8)
            if NTProtocol.crc16(Array(buf[(i + 2)..<(i + 2 + n)])) == crc {
                frames.append(Array(buf[(i + 1)..<(i + n + 2)]))
                i += n + 4
            } else {
                i += 1
            }
        }
        if i > 0 { buf.removeFirst(min(i, buf.count)) }
        if buf.count > 4096 { buf.removeFirst(buf.count - 1024) }
        return frames
    }
}

public enum DeviceEvent: Equatable {
    /// EMG reading of both channels, in microvolts.
    case emg(id: UInt8, ch1: Double, ch2: Double)
    /// Stimulation values per channel (probably mA, to be confirmed) and ETS countdown.
    case stim(c1: Int, c2: Int, c3: Int, c4: Int, etsCountdown: Int)
    /// Program state: started, work/rest, EMG/stimulation mode, pause.
    case status(started: Bool, work: Bool, emgMode: Bool, paused: Bool)
    /// Other packet (identifier), counted for diagnostics.
    case other(id: UInt8)
}

public enum NTDecoder {
    /// EMG value decoding: two bytes, the second decreased by 1; bit 15 = 0.01 scale.
    public static func readEMG(_ f: [UInt8], _ off: Int) -> Double {
        let low = Int(f[off])
        let high = Int(f[off + 1]) - 1
        let num = UInt16(truncatingIfNeeded: low | (high << 8))
        if num & 0x8000 != 0 {
            return Double(num & 0x7FFF) * 0.01
        }
        return Double(num) * 0.1
    }

    /// Decodes a frame [length, identifier, data…].
    public static func decode(frame f: [UInt8]) -> [DeviceEvent] {
        guard f.count >= 3 else { return [] }
        let id = f[1]
        var out: [DeviceEvent] = []
        var handled = false

        if id <= 13 {
            let s = f[2]
            out.append(.status(started: s & 1 != 0,
                               work: s & 2 != 0,
                               emgMode: s & 4 != 0,
                               paused: s & 8 == 0))
        }
        if id >= 1 && id <= 7 && f.count >= 7 {
            out.append(.emg(id: id, ch1: readEMG(f, 3), ch2: readEMG(f, 5)))
            handled = true
        } else if id == 11 && f.count >= 10 {
            let countdown = f[4] == 255 ? 0 : Int(f[4])
            out.append(.stim(c1: Int(f[6]), c2: Int(f[7]), c3: Int(f[8]), c4: Int(f[9]),
                             etsCountdown: countdown))
            handled = true
        }
        if !handled { out.append(.other(id: id)) }
        return out
    }
}
