import Foundation

// PDF writer with no system dependency (works everywhere, testable on Linux).
// Standard Helvetica font (WinAnsi: Western accents OK), text, lines, shapes, JPEG images.

public struct PDFColor {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
    public static let black = PDFColor(0, 0, 0)
    public static let gray = PDFColor(0.42, 0.44, 0.48)
    public static let lightGray = PDFColor(0.90, 0.91, 0.93)
    public static let veryLight = PDFColor(0.96, 0.96, 0.97)
    public static let white = PDFColor(1, 1, 1)
    public static let red = PDFColor(0.78, 0.12, 0.12)
    public static let blue = PDFColor(0.12, 0.38, 0.78)
    public static let orange = PDFColor(0.90, 0.48, 0.08)
    public static let teal = PDFColor(0.08, 0.55, 0.50)
    public static let purple = PDFColor(0.50, 0.28, 0.72)
    public static let palette: [PDFColor] = [.blue, .orange, .teal, .purple]
}

public struct JPEGInfo {
    public var data: Data
    public var width: Int
    public var height: Int
    public var components: Int

    /// Reads the dimensions from the JPEG header (SOF marker). Returns nil if it is not a usable JPEG.
    public static func parse(_ data: Data) -> JPEGInfo? {
        let b = [UInt8](data)
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var i = 2
        while i + 9 < b.count {
            if b[i] != 0xFF { i += 1; continue }
            var m = b[i + 1]
            while m == 0xFF && i + 2 < b.count { i += 1; m = b[i + 1] }
            if m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7) { i += 2; continue }
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            let isSOF = (m >= 0xC0 && m <= 0xCF) && m != 0xC4 && m != 0xC8 && m != 0xCC
            if isSOF {
                let h = Int(b[i + 5]) << 8 | Int(b[i + 6])
                let w = Int(b[i + 7]) << 8 | Int(b[i + 8])
                let comps = Int(b[i + 9])
                if w > 0 && h > 0 && (comps == 1 || comps == 3) {
                    return JPEGInfo(data: data, width: w, height: h, components: comps)
                }
                return nil
            }
            i += 2 + len
        }
        return nil
    }
}

public final class PDFDoc {
    public let width = 595.28
    public let height = 841.89
    public var title: String

    private var pages: [String] = []
    private var cur = ""
    private var images: [JPEGInfo] = []
    private var imagesOnPage: [Set<Int>] = []
    private var curImages = Set<Int>()
    private var started = false

    public init(title: String) {
        self.title = title
    }

    // MARK: - Pages

    public var pageCount: Int { return pages.count + (started ? 1 : 0) }

    public func newPage() {
        if started {
            pages.append(cur)
            imagesOnPage.append(curImages)
        }
        started = true
        cur = ""
        curImages = []
    }

    /// Draws on an already finished page (for the “Page i / n” footers).
    public func withPage(_ index: Int, _ body: () -> Void) {
        if index == pages.count && started {
            body()
            return
        }
        guard index >= 0 && index < pages.count else { return }
        let savedCur = cur
        let savedImages = curImages
        cur = pages[index]
        curImages = imagesOnPage[index]
        body()
        pages[index] = cur
        imagesOnPage[index] = curImages
        cur = savedCur
        curImages = savedImages
    }

    // MARK: - Text

    private static let helvetica: [Int] = [
        278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
        556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
        1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
        667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
        333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
        556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
    ]

    /// Unicode → WinAnsi bytes (unavailable characters replaced).
    public static func winAnsi(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        for u in s.unicodeScalars {
            let v = u.value
            switch v {
            case 0x20...0x7E: out.append(UInt8(v))
            case 0xA0...0xFF: out.append(UInt8(v))
            case 0x20AC: out.append(0x80)
            case 0x2026: out.append(0x85)
            case 0x2018: out.append(0x91)
            case 0x2019: out.append(0x92)
            case 0x201C: out.append(0x93)
            case 0x201D: out.append(0x94)
            case 0x2022: out.append(0x95)
            case 0x2013: out.append(0x96)
            case 0x2014: out.append(0x97)
            case 0x0153: out.append(0x9C)
            case 0x0152: out.append(0x8C)
            case 0x2192, 0x2197: out.append(0x3E)
            case 0x2198: out.append(0x3E)
            case 0x0A, 0x09: out.append(0x20)
            default: out.append(0x3F)
            }
        }
        return out
    }

    private static func glyphWidth(_ b: UInt8) -> Double {
        if b >= 32 && b <= 126 { return Double(helvetica[Int(b) - 32]) }
        switch b {
        case 0xB0: return 400
        case 0xB5: return 576
        case 0xD7, 0xF7: return 584
        case 0x95: return 350
        case 0x85, 0x97: return 1000
        case 0x96: return 556
        case 0x91, 0x92: return 222
        case 0x93, 0x94: return 333
        case 0xC0...0xDE: return 690
        case 0x9C: return 889
        case 0x8C: return 1000
        default: return 556
        }
    }

    public func textWidth(_ s: String, size: Double, bold: Bool = false) -> Double {
        var w = 0.0
        for b in PDFDoc.winAnsi(s) { w += PDFDoc.glyphWidth(b) }
        return w / 1000 * size * (bold ? 1.06 : 1.0)
    }

    private func f(_ v: Double) -> String { return String(format: "%.2f", v) }

    private func col(_ c: PDFColor) -> String { return "\(f(c.r)) \(f(c.g)) \(f(c.b))" }

    private func hex(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789ABCDEF")
        var s = ""
        s.reserveCapacity(bytes.count * 2)
        for b in bytes {
            s.append(digits[Int(b >> 4)])
            s.append(digits[Int(b & 15)])
        }
        return s
    }

    /// (x, y): y is measured from the top of the page, at the text baseline.
    /// The “µ” is drawn with the Symbol font (all PDF readers display it, unlike some fallback fonts).
    public func text(_ s: String, x: Double, y: Double, size: Double, bold: Bool = false, color: PDFColor = .black) {
        if s.isEmpty { return }
        let isMu: (Unicode.Scalar) -> Bool = { $0.value == 0xB5 || $0.value == 0x3BC }
        if !s.unicodeScalars.contains(where: isMu) {
            cur += "BT /\(bold ? "F2" : "F1") \(f(size)) Tf \(col(color)) rg \(f(x)) \(f(height - y)) Td <\(hex(PDFDoc.winAnsi(s)))> Tj ET\n"
            return
        }
        var cx = x
        var run = ""
        func flush() {
            if run.isEmpty { return }
            cur += "BT /\(bold ? "F2" : "F1") \(f(size)) Tf \(col(color)) rg \(f(cx)) \(f(height - y)) Td <\(hex(PDFDoc.winAnsi(run)))> Tj ET\n"
            cx += textWidth(run, size: size, bold: bold)
            run = ""
        }
        for u in s.unicodeScalars {
            if isMu(u) {
                flush()
                cur += "BT /F3 \(f(size)) Tf \(col(color)) rg \(f(cx)) \(f(height - y)) Td <6D> Tj ET\n"
                cx += 576 / 1000 * size
            } else {
                run.unicodeScalars.append(u)
            }
        }
        flush()
    }

    /// Wraps a text into lines that fit in `maxWidth`.
    public func wrap(_ s: String, maxWidth: Double, size: Double, bold: Bool = false) -> [String] {
        var lines: [String] = []
        for para in s.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: true) {
                let w = String(word)
                let test = line.isEmpty ? w : line + " " + w
                if textWidth(test, size: size, bold: bold) <= maxWidth || line.isEmpty {
                    line = test
                } else {
                    lines.append(line)
                    line = w
                }
            }
            lines.append(line)
        }
        return lines
    }

    /// Shortens with “…” to fit the width.
    public func fit(_ s: String, maxWidth: Double, size: Double, bold: Bool = false) -> String {
        if textWidth(s, size: size, bold: bold) <= maxWidth { return s }
        var t = s
        while !t.isEmpty && textWidth(t + "…", size: size, bold: bold) > maxWidth { t.removeLast() }
        return t + "…"
    }

    // MARK: - Shapes

    public func line(x1: Double, y1: Double, x2: Double, y2: Double, width w: Double = 0.5, color: PDFColor = .black) {
        cur += "\(f(w)) w \(col(color)) RG \(f(x1)) \(f(height - y1)) m \(f(x2)) \(f(height - y2)) l S\n"
    }

    public func rect(x: Double, y: Double, w: Double, h: Double, fill: PDFColor? = nil, stroke: PDFColor? = nil, lineWidth: Double = 0.5) {
        var op = ""
        if let fc = fill { op += "\(col(fc)) rg " }
        if let sc = stroke { op += "\(col(sc)) RG \(f(lineWidth)) w " }
        let paint = (fill != nil && stroke != nil) ? "B" : (fill != nil ? "f" : "S")
        cur += "\(op)\(f(x)) \(f(height - y - h)) \(f(w)) \(f(h)) re \(paint)\n"
    }

    public func polyline(_ pts: [(Double, Double)], width w: Double = 1.2, color: PDFColor = .blue) {
        guard pts.count >= 2 else { return }
        var s = "\(f(w)) w \(col(color)) RG 1 j 1 J "
        s += "\(f(pts[0].0)) \(f(height - pts[0].1)) m "
        for p in pts.dropFirst() { s += "\(f(p.0)) \(f(height - p.1)) l " }
        cur += s + "S\n"
    }

    public func circle(cx: Double, cy: Double, r: Double, fill: PDFColor) {
        let k = 0.5523 * r
        let y = height - cy
        var s = "\(col(fill)) rg "
        s += "\(f(cx + r)) \(f(y)) m "
        s += "\(f(cx + r)) \(f(y + k)) \(f(cx + k)) \(f(y + r)) \(f(cx)) \(f(y + r)) c "
        s += "\(f(cx - k)) \(f(y + r)) \(f(cx - r)) \(f(y + k)) \(f(cx - r)) \(f(y)) c "
        s += "\(f(cx - r)) \(f(y - k)) \(f(cx - k)) \(f(y - r)) \(f(cx)) \(f(y - r)) c "
        s += "\(f(cx + k)) \(f(y - r)) \(f(cx + r)) \(f(y - k)) \(f(cx + r)) \(f(y)) c f\n"
        cur += s
    }

    public func image(_ jpeg: JPEGInfo, x: Double, y: Double, w: Double, h: Double) {
        images.append(jpeg)
        let idx = images.count - 1
        curImages.insert(idx)
        cur += "q \(f(w)) 0 0 \(f(h)) \(f(x)) \(f(height - y - h)) cm /Im\(idx) Do Q\n"
    }

    // MARK: - Output

    public func data() -> Data {
        var pgs = pages
        var pimgs = imagesOnPage
        if started {
            pgs.append(cur)
            pimgs.append(curImages)
        }
        if pgs.isEmpty {
            pgs = [""]
            pimgs = [[]]
        }

        var objects: [Data] = []
        func add(_ s: String) -> Int {
            objects.append(Data(s.utf8))
            return objects.count
        }
        func addRaw(_ d: Data) -> Int {
            objects.append(d)
            return objects.count
        }

        // fixed numbers: 1 catalog, 2 pages, 3-5 fonts (Helvetica, Helvetica-Bold, Symbol)
        _ = add("")  // 1 (filled in at the end)
        _ = add("")  // 2
        let fRegular = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        let fBold = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
        let fSymbol = add("<< /Type /Font /Subtype /Type1 /BaseFont /Symbol >>")

        var imageIds: [Int] = []
        for img in images {
            var d = Data()
            let cs = img.components == 1 ? "/DeviceGray" : "/DeviceRGB"
            d.append(Data("<< /Type /XObject /Subtype /Image /Width \(img.width) /Height \(img.height) /ColorSpace \(cs) /BitsPerComponent 8 /Filter /DCTDecode /Length \(img.data.count) >>\nstream\n".utf8))
            d.append(img.data)
            d.append(Data("\nendstream".utf8))
            imageIds.append(addRaw(d))
        }

        var pageIds: [Int] = []
        for (i, content) in pgs.enumerated() {
            let bytes = Data(content.utf8)
            var c = Data("<< /Length \(bytes.count) >>\nstream\n".utf8)
            c.append(bytes)
            c.append(Data("\nendstream".utf8))
            let cid = addRaw(c)
            var xo = ""
            for k in pimgs[i].sorted() { xo += "/Im\(k) \(imageIds[k]) 0 R " }
            let res = "<< /Font << /F1 \(fRegular) 0 R /F2 \(fBold) 0 R /F3 \(fSymbol) 0 R >>" + (xo.isEmpty ? "" : " /XObject << \(xo)>>") + " >>"
            let pid = add("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(f(width)) \(f(height))] /Resources \(res) /Contents \(cid) 0 R >>")
            pageIds.append(pid)
        }

        // metadata: title in UTF-16BE
        var tb: [UInt8] = [0xFE, 0xFF]
        for u in title.utf16 { tb.append(UInt8(u >> 8)); tb.append(UInt8(u & 0xFF)) }
        let infoId = add("<< /Title <\(hex(tb))> /Producer (NeuroTrac Live) >>")

        objects[0] = Data("<< /Type /Catalog /Pages 2 0 R >>".utf8)
        objects[1] = Data("<< /Type /Pages /Kids [\(pageIds.map { "\($0) 0 R" }.joined(separator: " "))] /Count \(pageIds.count) >>".utf8)

        var out = Data("%PDF-1.4\n%\u{00E2}\u{00E3}\u{00CF}\u{00D3}\n".utf8)
        var offsets: [Int] = []
        for (i, o) in objects.enumerated() {
            offsets.append(out.count)
            out.append(Data("\(i + 1) 0 obj\n".utf8))
            out.append(o)
            out.append(Data("\nendobj\n".utf8))
        }
        let xref = out.count
        var x = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { x += String(format: "%010d 00000 n \n", o) }
        x += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R /Info \(infoId) 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        out.append(Data(x.utf8))
        return out
    }
}
