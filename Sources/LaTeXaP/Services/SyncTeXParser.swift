import Foundation
import zlib

public struct SyncTeXBox: Sendable, Equatable {
    public let page: Int        // 1-indexed page number
    public let inputID: Int
    public let line: Int        // 1-indexed source line
    public let xPt: Double      // PDF points from left
    public let yTopPt: Double   // SyncTeX points from TOP of page
    public let widthPt: Double
    public let heightPt: Double
    public let depthPt: Double
}

public struct SyncTeXData: Sendable {
    public let inputs: [Int: String]
    public let boxes: [SyncTeXBox]

    public init(inputs: [Int: String] = [:], boxes: [SyncTeXBox] = []) {
        self.inputs = inputs
        self.boxes = boxes
    }

    /// Forward search: given a 1-based source line, find the best matching PDF box.
    public func forwardSearch(line: Int) -> SyncTeXBox? {
        guard !boxes.isEmpty else { return nil }
        // Prefer exact line match with positive width, otherwise closest line
        let exact = boxes.filter { $0.line == line && $0.widthPt > 0 }
        if let firstExact = exact.first {
            return firstExact
        }
        return boxes.min { a, b in
            let distA = abs(a.line - line)
            let distB = abs(b.line - line)
            if distA != distB { return distA < distB }
            return a.widthPt > b.widthPt
        }
    }

    /// Backward search: given a 1-based page number and point in SyncTeX top-left coordinates (xPt, yTopPt),
    /// find the closest source line.
    public func backwardSearch(page: Int, xPt: Double, yTopPt: Double) -> Int? {
        let pageBoxes = boxes.filter { $0.page == page && $0.line > 0 }
        guard !pageBoxes.isEmpty else { return nil }

        var bestLine: Int?
        var bestScore = Double.greatestFiniteMagnitude

        for box in pageBoxes {
            let minX = box.xPt
            let maxX = box.xPt + max(box.widthPt, 8.0)
            let minY = box.yTopPt - max(box.heightPt, 10.0)
            let maxY = box.yTopPt + max(box.depthPt, 4.0)

            let dx: Double
            if xPt < minX { dx = minX - xPt }
            else if xPt > maxX { dx = xPt - maxX }
            else { dx = 0 }

            let dy: Double
            if yTopPt < minY { dy = minY - yTopPt }
            else if yTopPt > maxY { dy = yTopPt - maxY }
            else { dy = 0 }

            // Vertical distance matters much more than horizontal distance in lines of text
            let score = (dy * 4.0) * (dy * 4.0) + dx * dx
            if score < bestScore {
                bestScore = score
                bestLine = box.line
            }
        }
        return bestLine
    }
}

public enum SyncTeXParser {
    private static let spToPt: Double = 65536.0 * 72.27 / 72.0 // ~65781.76

    public static func parse(synctexGzURL: URL) -> SyncTeXData? {
        guard let compressed = try? Data(contentsOf: synctexGzURL),
              let decompressed = gunzip(data: compressed),
              let text = String(data: decompressed, encoding: .utf8) ?? String(data: decompressed, encoding: .isoLatin1)
        else {
            return nil
        }
        return parse(text: text)
    }

    public static func parse(text: String) -> SyncTeXData {
        var inputs: [Int: String] = [:]
        var boxes: [SyncTeXBox] = []
        var currentPage: Int = 1

        let lines = text.components(separatedBy: .newlines)
        for raw in lines {
            if raw.isEmpty { continue }

            if raw.hasPrefix("Input:") {
                // Format: Input:1:/path/to/doc.tex
                let rest = raw.dropFirst("Input:".count)
                if let colonIdx = rest.firstIndex(of: ":") {
                    let idStr = String(rest[..<colonIdx])
                    let pathStr = String(rest[rest.index(after: colonIdx)...])
                    if let id = Int(idStr), !pathStr.isEmpty {
                        inputs[id] = pathStr
                    }
                }
                continue
            }

            guard let firstChar = raw.first else { continue }

            if firstChar == "{" {
                if let p = Int(raw.dropFirst()) {
                    currentPage = p
                }
                continue
            }

            // Record types carrying coordinates:
            // h, v, ( -> tag,line:x,y:w,h,d
            // g, $, x -> tag,line:x,y
            // k       -> tag,line:x,y:w
            if firstChar == "h" || firstChar == "v" || firstChar == "(" || firstChar == "g" || firstChar == "x" || firstChar == "$" || firstChar == "k" {
                let body = raw.dropFirst()
                let sections = body.split(separator: ":", omittingEmptySubsequences: false)
                guard sections.count >= 2 else { continue }

                let tagLine = sections[0].split(separator: ",")
                guard tagLine.count >= 2,
                      let inputID = Int(tagLine[0]),
                      let lineNum = Int(tagLine[1]),
                      lineNum > 0
                else { continue }

                let xy = sections[1].split(separator: ",")
                guard xy.count >= 2,
                      let xSp = Double(xy[0]),
                      let ySp = Double(xy[1])
                else { continue }

                var wSp: Double = 0
                var hSp: Double = 0
                var dSp: Double = 0

                if sections.count >= 3 {
                    let whd = sections[2].split(separator: ",")
                    if whd.count >= 1, let w = Double(whd[0]) { wSp = w }
                    if whd.count >= 2, let h = Double(whd[1]) { hSp = h }
                    if whd.count >= 3, let d = Double(whd[2]) { dSp = d }
                }

                let box = SyncTeXBox(
                    page: currentPage,
                    inputID: inputID,
                    line: lineNum,
                    xPt: xSp / spToPt,
                    yTopPt: ySp / spToPt,
                    widthPt: max(0, wSp / spToPt),
                    heightPt: max(8, hSp / spToPt),
                    depthPt: max(2, dSp / spToPt)
                )
                boxes.append(box)
            }
        }

        return SyncTeXData(inputs: inputs, boxes: boxes)
    }

    public static func gunzip(data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        var stream = z_stream()
        var status: Int32 = data.withUnsafeBytes { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.bindMemory(to: Bytef.self).baseAddress else {
                return Z_DATA_ERROR
            }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress)
            stream.avail_in = uInt(data.count)
            // 15 + 32 enables automatic gzip/zlib header detection
            return inflateInit2_(&stream, MAX_WBITS + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }

        guard status == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var decompressed = Data(capacity: data.count * 4)
        let chunkSize = 32_768
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        repeat {
            let count = buffer.count
            status = buffer.withUnsafeMutableBytes { outBuffer in
                stream.next_out = outBuffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(count)
                return inflate(&stream, Z_SYNC_FLUSH)
            }
            let have = chunkSize - Int(stream.avail_out)
            if have > 0 {
                decompressed.append(buffer, count: have)
            }
        } while status == Z_OK

        return status == Z_STREAM_END ? decompressed : nil
    }
}
