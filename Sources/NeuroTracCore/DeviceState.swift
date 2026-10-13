import Foundation

/// A program from the device library (packet #197, sent at synchronization).
public struct LibraryProgram: Equatable, Codable {
    public let slot: Int
    public let name: String
    public let group: String
    public let hz: Int
    public let widthUs: Int
    /// 0 = continuous stimulation
    public let workSec: Int

    public init(slot: Int, name: String, group: String, hz: Int, widthUs: Int, workSec: Int) {
        self.slot = slot
        self.name = name
        self.group = group
        self.hz = hz
        self.widthUs = widthUs
        self.workSec = workSec
    }
}

/// Parameters of the current program, read from packets 5, 8, 10 and 12.
public struct ProgramParams: Equatable {
    public var hz: Int?
    public var widthUs: Int?
    /// 255 = continuous (no rest)
    public var workSec: Int?
    public var restSec: Int?
    public var rampUp: Double?
    public var rampDown: Double?
    public var programMinutes: Int?
    public var remainingSeconds: Int?
    public var clinicalMode: Int?
    public var programNumber: Int?
    public var phaseType: Int?

    public init() {}

    public var isContinuous: Bool { workSec == 255 }
}

/// Warning sent by the device (packet #8, byte 3, bits 5 to 7).
public enum DeviceWarning: Int {
    case neverOccurs = 0, none = 1, stimF = 2, output = 3
}

/// Tracks the program state (parameters, warnings, status, library) from the received frames.
public struct DeviceStateTracker {
    public private(set) var params = ProgramParams()
    public private(set) var warningCode = 1
    public private(set) var warningDetail = 0
    /// Status byte (bit 0 started, bit 1 work, bit 2 EMG, bit 3 running)
    public private(set) var statusByte: UInt8?
    public private(set) var library: [Int: LibraryProgram] = [:]
    /// Name of the “current” program sent at connection (packet 197, slot 0)
    public private(set) var slot0Name: String?
    public private(set) var stim: [Int] = [0, 0, 0, 0]

    public init() {}

    /// Reloads a library saved during a previous session.
    public mutating func setLibrary(_ programs: [LibraryProgram]) {
        for p in programs where library[p.slot] == nil { library[p.slot] = p }
    }

    public var libraryList: [LibraryProgram] {
        return library.values.sorted { $0.slot < $1.slot }
    }

    public var warning: DeviceWarning { DeviceWarning(rawValue: warningCode) ?? .none }
    public var isPaused: Bool? { statusByte.map { $0 & 8 == 0 } }
    public var isStarted: Bool? { statusByte.map { $0 & 1 != 0 } }
    public var isWork: Bool? { statusByte.map { $0 & 2 != 0 } }

    private static func cString(_ f: [UInt8], _ from: Int, _ to: Int) -> String {
        guard from < f.count else { return "" }
        var bytes: [UInt8] = []
        for i in from..<min(to, f.count) {
            if f[i] == 0 { break }
            if f[i] < 32 || f[i] > 126 { return "" }
            bytes.append(f[i])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    public mutating func feed(frame f: [UInt8]) {
        guard f.count >= 3 else { return }
        let id = Int(f[1])
        if id <= 13 { statusByte = f[2] }
        switch id {
        case 5 where f.count >= 11:
            params.clinicalMode = Int(f[8])
            params.phaseType = Int(f[9])
            params.programNumber = Int(f[10])
        case 8 where f.count >= 11:
            warningCode = Int(f[3] >> 5)
            warningDetail = Int(f[3] & 0x1F)
            params.hz = Int(f[6])
            params.workSec = Int(f[8])
            params.restSec = Int(f[9])
            params.remainingSeconds = max(0, Int(f[10]) - 1) * 60 + max(0, Int(f[7]) - 1)
        case 10 where f.count >= 11:
            params.widthUs = Int(f[3]) | (max(0, Int(f[4]) - 1) << 8)
            params.programMinutes = max(0, Int(f[8]) - 1)
        case 12 where f.count >= 11:
            if params.widthUs == nil { params.widthUs = Int(f[3]) | (max(0, Int(f[4]) - 1) << 8) }
            params.rampUp = Double(f[5] == 255 ? 0 : Int(f[5])) * 0.1
            params.rampDown = Double(f[6] == 255 ? 0 : Int(f[6])) * 0.1
        case 11 where f.count >= 10:
            stim = [Int(f[6]), Int(f[7]), Int(f[8]), Int(f[9])]
        case 197 where f.count >= 111:
            let slot = Int(f[3])
            let name = DeviceStateTracker.cString(f, 95, 110)
            if slot == 0 {
                if !name.isEmpty { slot0Name = name }
            } else if !name.isEmpty {
                library[slot] = LibraryProgram(slot: slot, name: name,
                                               group: DeviceStateTracker.cString(f, 41, 45),
                                               hz: Int(f[7]),
                                               widthUs: Int(f[9]) | (Int(f[10]) << 8),
                                               workSec: Int(f[11]))
            }
        default:
            break
        }
    }

    /// Library names whose frequency, width and work time match the current program.
    public func matchingNames() -> [String] {
        guard let hz = params.hz, let w = params.widthUs, let work = params.workSec else { return [] }
        var names: [String] = []
        for p in library.values.sorted(by: { $0.slot < $1.slot }) {
            let workMatch = (p.workSec == work) || (work == 255 && p.workSec == 0)
            if p.hz == hz && p.widthUs == w && workMatch && !names.contains(p.name) { names.append(p.name) }
        }
        return names
    }

    /// Displayed name: match with the library, otherwise the device's “current” name, otherwise the number.
    public func displayName() -> String {
        let m = matchingNames()
        if !m.isEmpty { return m.joined(separator: " ou ") }
        if let n = slot0Name { return n + tr(" (non listé)") }
        if let p = params.programNumber { return tr("programme n°\(p)") }
        return "—"
    }
}
