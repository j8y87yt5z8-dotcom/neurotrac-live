import Foundation

#if canImport(IOBluetooth)
import IOBluetooth
import NeuroTracCore

/// A Bluetooth device already paired with the Mac.
struct PairedDevice {
    let name: String
    let address: String

    static func list() -> [PairedDevice] {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return devices.compactMap { d in
            guard let addr = d.addressString else { return nil }
            return PairedDevice(name: d.name ?? addr, address: addr)
        }
    }
}

/// Direct Bluetooth Classic link (RFCOMM / SPP serial profile): the app opens the
/// connection itself, without going through System Settings or a /dev/cu.* port.
/// IOBluetooth calls happen on the main thread.
final class BluetoothTransport: NSObject, ByteTransport, IOBluetoothRFCOMMChannelDelegate {
    var onOpened: (() -> Void)?
    var onData: (([UInt8]) -> Void)?
    var onClosed: ((String) -> Void)?

    private let address: String
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var finished = false
    private var opened = false
    private var channelID: BluetoothRFCOMMChannelID = 0
    private var timeout: DispatchWorkItem?

    init(address: String) { self.address = address }

    func open() {
        DispatchQueue.main.async { self.openOnMain() }
    }

    private func openOnMain() {
        guard let dev = IOBluetoothDevice(addressString: address) else {
            fail(tr("Appareil Bluetooth introuvable (vérifie l'appairage dans Réglages Système > Bluetooth)."))
            return
        }
        device = dev

        // Maximum time for the whole procedure
        let w = DispatchWorkItem { [weak self] in
            guard let self = self, !self.opened else { return }
            self.fail(tr("L'appareil ne répond pas : allume-le, rapproche-le du Mac et vérifie qu'aucun autre logiciel ne l'utilise."))
        }
        timeout = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: w)

        // 1) base link with the device (blocking, a few seconds at most)
        if !dev.isConnected() {
            let r = dev.openConnection()
            if r != kIOReturnSuccess {
                fail(tr("Connexion Bluetooth refusée (code \(r)). Appareil éteint ou hors de portée ?"))
                return
            }
        }
        // 2) look for the device's serial channel (SPP)
        let r = dev.performSDPQuery(self)
        if r != kIOReturnSuccess {
            // no query possible: try with the already known services
            openChannelFromRecords()
        }
    }

    // End of the SDP query (informal delegate protocol method)
    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        DispatchQueue.main.async { self.openChannelFromRecords() }
    }

    private func openChannelFromRecords() {
        guard !finished, let dev = device else { return }
        var record: IOBluetoothSDPServiceRecord? = dev.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: 0x1101))
        var id: BluetoothRFCOMMChannelID = 0
        if record == nil || record!.getRFCOMMChannelID(&id) != kIOReturnSuccess {
            record = nil
            for s in (dev.services as? [IOBluetoothSDPServiceRecord]) ?? [] {
                if s.getRFCOMMChannelID(&id) == kIOReturnSuccess { record = s; break }
            }
        }
        guard record != nil else {
            fail(tr("Aucun service série trouvé sur l'appareil. Active l'option Bluetooth/PC de l'appareil puis réessaie."))
            return
        }
        channelID = id
        var ch: IOBluetoothRFCOMMChannel?
        let r = dev.openRFCOMMChannelAsync(&ch, withChannelID: id, delegate: self)
        if r != kIOReturnSuccess {
            fail(tr("Impossible d'ouvrir le canal série (code \(r))."))
            return
        }
        channel = ch
    }

    func write(_ bytes: [UInt8]) {
        DispatchQueue.main.async {
            guard let ch = self.channel, self.opened else { return }
            var copy = bytes
            copy.withUnsafeMutableBytes { p in
                if let base = p.baseAddress {
                    _ = ch.writeSync(base, length: UInt16(bytes.count))
                }
            }
        }
    }

    func close() {
        DispatchQueue.main.async {
            self.finished = true
            self.timeout?.cancel()
            self.channel?.setDelegate(nil)
            _ = self.channel?.close()
            self.channel = nil
            _ = self.device?.closeConnection()
            self.device = nil
        }
    }

    private func fail(_ why: String) {
        if finished { return }
        finished = true
        timeout?.cancel()
        channel?.setDelegate(nil)
        _ = channel?.close()
        channel = nil
        _ = device?.closeConnection()
        onClosed?(why)
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        if error == kIOReturnSuccess {
            opened = true
            timeout?.cancel()
            onOpened?()
        } else {
            fail(tr("Ouverture du canal série refusée (code \(error)). Un autre logiciel utilise peut-être l'appareil."))
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard dataLength > 0, let p = dataPointer else { return }
        let buf = UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: dataLength)
        onData?(Array(buf))
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        if finished { return }
        finished = true
        channel = nil
        onClosed?(tr("Liaison Bluetooth coupée par l'appareil."))
    }
}
#else
struct PairedDevice {
    let name: String
    let address: String
    static func list() -> [PairedDevice] { [] }
}
#endif
