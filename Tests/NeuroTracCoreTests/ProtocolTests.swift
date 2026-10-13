import XCTest
@testable import NeuroTracCore

final class ProtocolTests: XCTestCase {
    override func setUp() { Lang.override = .fr }
    private func hex(_ b: [UInt8]) -> String {
        return b.map { String(format: "%02X", $0) }.joined()
    }

    // Reference values for the frame builder and CRC.
    func testPacketsMatchOriginalSoftware() {
        XCTAssertEqual(hex(NTProtocol.text("HELO")), "F80C6448454C4F00000000000000DE2D")
        XCTAssertEqual(hex(NTProtocol.text("1234")), "F80C643132333400000000000000DC7A")
        XCTAssertEqual(hex(NTProtocol.text("PING")), "F80C6450494E4700000000000000AEE5")
        XCTAssertEqual(hex(NTProtocol.text("NAME")), "F80C644E414D4500000000000000400B")
    }

    private func enc(_ v: Int) -> [UInt8] {
        return [UInt8(v & 0xFF), UInt8(((v >> 8) + 1) & 0xFF)]
    }

    func testEMGFrameRoundTrip() {
        let data: [UInt8] = [0x00] + enc(300) + enc(150) + [UInt8](repeating: 0, count: 6)
        let packet = NTProtocol.makePacket(id: 1, data: data)
        var ex = FrameExtractor()
        // the packet is cut into two pieces to test reassembly
        XCTAssertTrue(ex.feed(Array(packet[0..<7])).isEmpty)
        let frames = ex.feed(Array(packet[7...]))
        XCTAssertEqual(frames.count, 1)
        let events = NTDecoder.decode(frame: frames[0])
        var found = false
        for e in events {
            if case let .emg(id, ch1, ch2) = e {
                XCTAssertEqual(id, 1)
                XCTAssertEqual(ch1, 30.0, accuracy: 1e-9)
                XCTAssertEqual(ch2, 15.0, accuracy: 1e-9)
                found = true
            }
        }
        XCTAssertTrue(found)
    }

    func testStimFrame() {
        // data bytes: [status, ?, countdown, ?, s1, s2, s3, s4, …]
        let data: [UInt8] = [0x03, 0, 5, 0, 12, 0, 0, 20, 0, 0, 0]
        let packet = NTProtocol.makePacket(id: 11, data: data)
        var ex = FrameExtractor()
        let frames = ex.feed(packet)
        XCTAssertEqual(frames.count, 1)
        let events = NTDecoder.decode(frame: frames[0])
        XCTAssertTrue(events.contains(.stim(c1: 12, c2: 0, c3: 0, c4: 20, etsCountdown: 5)))
    }

    func testBadCRCIsIgnored() {
        var packet = NTProtocol.text("PING")
        packet[packet.count - 1] ^= 0xFF
        var ex = FrameExtractor()
        XCTAssertTrue(ex.feed(packet).isEmpty)
    }

    func testIndexOfSequence() {
        let a: [UInt8] = [1, 2, 80, 73, 78, 82, 69, 81, 9]
        XCTAssertEqual(a.indexOfSequence(NTProtocol.pinRequest), 2)
        XCTAssertNil(a.indexOfSequence(NTProtocol.pinAccepted))
    }
}

final class DebugTrackerTests: XCTestCase {
    override func setUp() { Lang.override = .fr }
    func testTracksChangedBytesAndRate() {
        var tr = DebugTracker()
        tr.record(frame: [6, 202, 1, 2, 3, 4, 5], t: 0.0)
        tr.record(frame: [6, 202, 1, 9, 3, 4, 5], t: 0.5)
        tr.record(frame: [6, 202, 1, 9, 3, 7, 5], t: 1.0)
        let s = tr.stats[202]!
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.changed, [3, 5])
        XCTAssertEqual(s.lastChangeT[3], 0.5)
        XCTAssertEqual(s.lastChangeT[5], 1.0)
        XCTAssertEqual(s.rate, 2.0, accuracy: 1e-9)
        XCTAssertFalse(DebugTracker.isKnown(id: 202))
        XCTAssertTrue(DebugTracker.isKnown(id: 11))
        XCTAssertTrue(tr.summary().contains("inconnu"))
    }

    func testDifferentLengthDoesNotCrash() {
        var tr = DebugTracker()
        tr.record(frame: [4, 9, 1, 2], t: 0)
        tr.record(frame: [6, 9, 1, 2, 3, 4], t: 1)
        XCTAssertEqual(tr.stats[9]?.count, 2)
        XCTAssertTrue(tr.stats[9]!.changed.isEmpty)
    }
}

final class DeviceStateTests: XCTestCase {
    override func setUp() { Lang.override = .fr }
    private func b(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            out.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    // Real frames recorded on the MyoPlus 4 Pro (program SCTS1)
    func testProgramParametersFromRealFrames() {
        var st = DeviceStateTracker()
        st.feed(frame: b("0A050D7381590A1131F307"))
        st.feed(frame: b("0A080B20B82C23310C081D"))
        st.feed(frame: b("0A0A0B2C023D2C021FFFFF"))
        st.feed(frame: b("0A0C0B2C02140CFF01521F"))
        st.feed(frame: b("0A0B0BFFFF1D00040000FF"))
        XCTAssertEqual(st.params.hz, 35)
        XCTAssertEqual(st.params.widthUs, 300)
        XCTAssertEqual(st.params.workSec, 12)
        XCTAssertEqual(st.params.restSec, 8)
        XCTAssertEqual(st.params.programMinutes, 30)
        XCTAssertEqual(st.params.rampUp ?? 0, 2.0, accuracy: 1e-9)
        XCTAssertEqual(st.params.rampDown ?? 0, 1.2, accuracy: 1e-9)
        XCTAssertEqual(st.params.programNumber, 7)
        XCTAssertEqual(st.params.clinicalMode, 49)
        XCTAssertEqual(st.params.remainingSeconds, 28 * 60 + 48)
        XCTAssertEqual(st.stim, [0, 4, 0, 0])
        XCTAssertEqual(st.warning, .none)
    }

    func testLibraryNameMatching() {
        var st = DeviceStateTracker()
        st.feed(frame: b("B2C500010103001900E1000000000058020A5AC800AF0020D0CF0120B0CE012018CE01200000000000435453330009311FCE012001000000FA0000000802FFFFB0CE0120FF0000005505000000010000F2410020F1FFFFFF80CE01200000004375697373657300000000000000000000000000000000000000000000000000003C75FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF3636363636023238010808FFFFFFFFFF0F4D796F506C7573203450726F00000000"))
        st.feed(frame: b("B2C5000A01040023002C010C08140C08070003FA00C80020D0CF0120B0CE012018CE01200000000000435453330009311FCE012001000000FA0000000802FFFFB0CE0120FF0000005505000000010000F2410020F1FFFFFF80CE01200000005343545331000000000000000000000000000000000000000000000000000000003C75FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF3636363636023238010808FFFFFFFFFF0F4D796F506C7573203450726F00000000"))
        st.feed(frame: b("B2C500000203001400960000000000B004020AFA00C800060000000000050608085802020AFA00C8000000000000000000000000000000000000000000000000000000001400000000E40040F9FFFFFFD8A90000C80000000A00000009000054544E5300000000000000000000000000000000000000000000000000000000003C75FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF3636363636023238010808FFFFFFFFFF0F4D796F506C7573203450726F00000000"))
        XCTAssertEqual(st.library[10]?.name, "SCTS1")
        XCTAssertEqual(st.library[10]?.hz, 35)
        XCTAssertEqual(st.library[10]?.widthUs, 300)
        XCTAssertEqual(st.library[10]?.workSec, 12)
        XCTAssertEqual(st.library[1]?.name, "Cuisses")
        XCTAssertEqual(st.slot0Name, "TTNS")
        st.feed(frame: b("0A080B20B82C23310C081D"))
        st.feed(frame: b("0A0A0B2C023D2C021FFFFF"))
        XCTAssertEqual(st.matchingNames(), ["SCTS1"])
        XCTAssertEqual(st.displayName(), "SCTS1")
        // second program (3 Hz, 150 µs, continuous): absent from the library
        st.feed(frame: b("0A080B20B8960337FF0014"))
        st.feed(frame: b("0A0A0B96013D960115FFFF"))
        st.feed(frame: b("0A0C0B96010101FFFF521F"))
        XCTAssertEqual(st.params.hz, 3)
        XCTAssertEqual(st.params.widthUs, 150)
        XCTAssertTrue(st.params.isContinuous)
        XCTAssertEqual(st.displayName(), "TTNS (non listé)")
    }

    func testWarningAndPause() {
        var st = DeviceStateTracker()
        st.feed(frame: b("0A080372B896032DFF0012"))
        XCTAssertEqual(st.warning, .output)
        XCTAssertEqual(st.isPaused, true)
    }

    func testShortFramesDoNotCrash() {
        var st = DeviceStateTracker()
        st.feed(frame: [])
        st.feed(frame: [3, 8, 1])
        st.feed(frame: [3, 197, 1])
        XCTAssertNil(st.params.hz)
    }
}
