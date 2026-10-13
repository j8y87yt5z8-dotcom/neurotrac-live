import Foundation
import NeuroTracCore

enum LinkState { case idle, connecting, handshaking, connected }

/// Conversation with the NeuroTrac on top of a transport (direct Bluetooth or serial port).
/// Handshake: HELO → PINREQ → code → PINACC, then PING every second.
/// No setting or stimulation command is ever sent.
final class DeviceLink {
    private enum Phase { case idle, waitPinReq, waitPinAcc, streaming }

    // Called on the internal queue: the caller hops back to the main thread.
    var onEvent: ((DeviceEvent) -> Void)?
    var onFrame: (([UInt8]) -> Void)?
    var onStatus: ((String) -> Void)?
    var onState: ((LinkState) -> Void)?
    var onRaw: ((String) -> Void)?
    /// Link lost without the user asking for it.
    var onLost: (() -> Void)?

    private let queue = DispatchQueue(label: "neurotrac.link")
    private var transport: ByteTransport?
    private var timer: DispatchSourceTimer?
    private var phase: Phase = .idle
    private var pin = "1234"
    private var rawBuf: [UInt8] = []
    private var extractor = FrameExtractor()
    private var lastHelo = Date.distantPast
    private var lastPing = Date.distantPast
    private var t0 = Date()
    private var warned = false
    private var generation = 0

    func open(transport t: ByteTransport, pin: String) {
        queue.async {
            self.closeInternal(userRequested: true)
            self.generation += 1
            let gen = self.generation
            self.transport = t
            self.pin = pin
            self.rawBuf = []
            self.extractor = FrameExtractor()
            self.lastHelo = Date.distantPast
            self.lastPing = Date.distantPast
            self.t0 = Date()
            self.warned = false
            self.phase = .idle
            self.onState?(.connecting)
            self.onStatus?(tr("Connexion Bluetooth à l'appareil…"))

            t.onOpened = { [weak self] in
                self?.queue.async {
                    guard let self = self, gen == self.generation else { return }
                    self.phase = .waitPinReq
                    self.onState?(.handshaking)
                    self.onStatus?(tr("Liaison établie. Dialogue avec l'appareil…"))
                    self.startTimer()
                }
            }
            t.onData = { [weak self] bytes in
                self?.queue.async {
                    guard let self = self, gen == self.generation else { return }
                    self.handle(bytes)
                }
            }
            t.onClosed = { [weak self] why in
                self?.queue.async {
                    guard let self = self, gen == self.generation, self.transport != nil else { return }
                    self.onStatus?(why)
                    self.closeInternal(userRequested: false)
                }
            }
            t.open()
        }
    }

    func close() {
        queue.async { self.closeInternal(userRequested: true) }
    }

    // MARK: - Internal (always on the `queue` queue)

    private func startTimer() {
        timer?.cancel()
        let tm = DispatchSource.makeTimerSource(queue: queue)
        tm.schedule(deadline: .now() + 0.2, repeating: 0.5)
        tm.setEventHandler { [weak self] in self?.tick() }
        timer = tm
        tm.resume()
    }

    private func closeInternal(userRequested: Bool) {
        timer?.cancel()
        timer = nil
        let had = transport != nil
        let t = transport
        transport = nil
        phase = .idle
        t?.onOpened = nil
        t?.onData = nil
        t?.onClosed = nil
        t?.close()
        if had {
            onState?(.idle)
            if !userRequested { onLost?() }
        }
    }

    private func send(_ bytes: [UInt8]) {
        transport?.write(bytes)
    }

    private func log(_ s: String) {
        onRaw?(String(format: "%8.3f ", Date().timeIntervalSince(t0)) + s)
    }

    private func tick() {
        let now = Date()
        switch phase {
        case .waitPinReq:
            if now.timeIntervalSince(lastHelo) > 1.5 {
                send(NTProtocol.text("HELO"))
                lastHelo = now
                log("TX HELO")
            }
            if !warned && now.timeIntervalSince(t0) > 14 {
                warned = true
                onStatus?(tr("Liaison ouverte mais l'appareil ne répond pas au dialogue. Vérifie le Bluetooth de l'appareil, puis réessaie."))
            }
        case .streaming:
            if now.timeIntervalSince(lastPing) > 1.0 {
                send(NTProtocol.text("PING"))
                lastPing = now
            }
        case .waitPinAcc, .idle:
            break
        }
    }

    private func becomeConnected(_ message: String) {
        phase = .streaming
        lastPing = Date()
        onState?(.connected)
        onStatus?(message)
    }

    private func handle(_ bytes: [UInt8]) {
        log("RX " + bytes.map { String(format: "%02x", $0) }.joined())
        switch phase {
        case .waitPinReq, .waitPinAcc:
            rawBuf.append(contentsOf: bytes)
            if phase == .waitPinReq, let k = rawBuf.indexOfSequence(NTProtocol.pinRequest) {
                rawBuf.removeFirst(k + NTProtocol.pinRequest.count)
                send(NTProtocol.text(pin))
                phase = .waitPinAcc
                log("TX PIN")
                onStatus?(tr("Code PIN demandé : envoyé."))
            }
            if phase == .waitPinAcc, let k = rawBuf.indexOfSequence(NTProtocol.pinAccepted) {
                rawBuf.removeFirst(k + NTProtocol.pinAccepted.count)
                let rest = rawBuf
                rawBuf = []
                becomeConnected(tr("Connecté : lecture en cours."))
                process(rest)
            } else if phase == .waitPinReq && rawBuf.count > 24 {
                // no PINREQ but data is coming in: the device may already be authenticated
                let rest = rawBuf
                rawBuf = []
                becomeConnected(tr("Appareil déjà authentifié : lecture en cours."))
                process(rest)
            }
        case .streaming:
            process(bytes)
        case .idle:
            break
        }
    }

    private func process(_ bytes: [UInt8]) {
        if bytes.isEmpty { return }
        for frame in extractor.feed(bytes) {
            onFrame?(frame)
            for event in NTDecoder.decode(frame: frame) {
                onEvent?(event)
            }
        }
    }
}
