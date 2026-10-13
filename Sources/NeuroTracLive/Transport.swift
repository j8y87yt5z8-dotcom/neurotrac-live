import Foundation
import Darwin
import NeuroTracCore

/// Byte transport between the app and the NeuroTrac: direct Bluetooth link (primary)
/// or serial port created by macOS (fallback). Callbacks may arrive on any queue.
protocol ByteTransport: AnyObject {
    var onOpened: (() -> Void)? { get set }
    var onData: (([UInt8]) -> Void)? { get set }
    /// Link closed or impossible to open; the text gives the reason.
    var onClosed: ((String) -> Void)? { get set }
    func open()
    func write(_ bytes: [UInt8])
    func close()
}

// MARK: - Serial port (/dev/cu.Myo4Pro…)

final class SerialTransport: ByteTransport {
    var onOpened: (() -> Void)?
    var onData: (([UInt8]) -> Void)?
    var onClosed: ((String) -> Void)?

    private let path: String
    private let queue = DispatchQueue(label: "neurotrac.serial")
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var zeroReads = 0
    private var finished = false

    init(path: String) { self.path = path }

    func open() {
        queue.async {
            let d = Darwin.open(self.path, O_RDWR | O_NOCTTY | O_NONBLOCK)
            if d < 0 {
                self.fail(tr("Impossible d'ouvrir le port : \(String(cString: strerror(errno)))"))
                return
            }
            var tio = termios()
            if tcgetattr(d, &tio) != 0 {
                Darwin.close(d)
                self.fail(tr("Impossible de configurer le port série."))
                return
            }
            cfmakeraw(&tio)
            cfsetspeed(&tio, speed_t(115200))
            tio.c_cflag |= tcflag_t(CLOCAL | CREAD)
            if tcsetattr(d, TCSANOW, &tio) != 0 {
                Darwin.close(d)
                self.fail(tr("Impossible de configurer le port série."))
                return
            }
            self.fd = d
            let src = DispatchSource.makeReadSource(fileDescriptor: d, queue: self.queue)
            src.setEventHandler { [weak self] in self?.readAvailable() }
            src.setCancelHandler { Darwin.close(d) }
            self.source = src
            src.resume()
            self.onOpened?()
        }
    }

    func write(_ bytes: [UInt8]) {
        queue.async {
            if self.fd < 0 { return }
            bytes.withUnsafeBufferPointer { p in
                _ = Darwin.write(self.fd, p.baseAddress, bytes.count)
            }
        }
    }

    func close() {
        queue.async {
            self.finished = true
            self.source?.cancel()
            self.source = nil
            self.fd = -1
        }
    }

    private func fail(_ why: String) {
        if finished { return }
        finished = true
        onClosed?(why)
    }

    private func readAvailable() {
        if fd < 0 { return }
        var tmp = [UInt8](repeating: 0, count: 1024)
        let n = Darwin.read(fd, &tmp, tmp.count)
        if n > 0 {
            zeroReads = 0
            onData?(Array(tmp[0..<n]))
        } else if n == 0 {
            zeroReads += 1
            if zeroReads > 50 {
                source?.cancel()
                source = nil
                fd = -1
                fail(tr("Liaison coupée par l'appareil."))
            }
        } else if errno != EAGAIN && errno != EINTR {
            let why = tr("Erreur de lecture : \(String(cString: strerror(errno)))")
            source?.cancel()
            source = nil
            fd = -1
            fail(why)
        }
    }
}
