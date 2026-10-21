import Foundation

/// SRT 字幕文件读写。
public enum SRT {
    public static func encode(_ subtitles: [Subtitle]) -> String {
        subtitles.sorted { $0.start < $1.start }.enumerated().map { i, sub -> String in
            // 正文里的空行会被当成条目结束，压成单个换行
            let text = sub.text.replacingOccurrences(of: "\n(?:[ \t]*\n)+", with: "\n", options: .regularExpression)
            return "\(i + 1)\n\(timestamp(sub.start)) --> \(timestamp(sub.end))\n\(text)\n"
        }.joined(separator: "\n")
    }

    /// 从文件内容解析：有 BOM 按 BOM 取编码，否则先试 UTF-8，再试 GB18030（Windows 中文记事本常见）。
    /// 不能无 BOM 地试 UTF-16：几乎任何偶数长度的字节都能“解码”成乱码。
    public static func decode(data: Data) -> [Subtitle] {
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data, encoding: .utf16)
        } else if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else {
            let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            text = String(data: data, encoding: String.Encoding(rawValue: gb))
        }
        return text.map(decode) ?? []
    }

    /// 宽松解析：兼容 CRLF、BOM、毫秒用点号、多行文字、时间行后的坐标，去掉 <i> 等标签。
    public static func decode(_ text: String) -> [Subtitle] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        var result: [Subtitle] = []
        let lines = normalized.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            guard let (start, end) = parseTiming(lines[i]) else { i += 1; continue }
            i += 1
            var body: [String] = []
            while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty, parseTiming(lines[i]) == nil {
                body.append(lines[i])
                i += 1
            }
            // 下一条的序号行被当成正文时去掉
            if i < lines.count, parseTiming(lines[i]) != nil, let last = body.last, Int(last.trimmingCharacters(in: .whitespaces)) != nil {
                body.removeLast()
            }
            let text = body.joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if end > start, !text.isEmpty { result.append(Subtitle(start: start, end: end, text: text)) }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// 视频旁边同名的 .srt；已有同名文件时用「名称 2.srt」「名称 3.srt」…，不覆盖。
    public static func sidecarURL(for video: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let dir = video.deletingLastPathComponent()
        let name = video.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent(name + ".srt")
        var n = 2
        while exists(candidate) {
            candidate = dir.appendingPathComponent("\(name) \(n).srt")
            n += 1
        }
        return candidate
    }

    static func timestamp(_ t: Time) -> String {
        let ms = max(0, Int((t.seconds * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    private static let timing = try! NSRegularExpression(
        pattern: #"^\s*(\d+):(\d{1,2}):(\d{1,2})(?:[,.](\d{1,3}))?\s*-->\s*(\d+):(\d{1,2}):(\d{1,2})(?:[,.](\d{1,3}))?"#)

    private static func parseTiming(_ line: String) -> (Time, Time)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = timing.firstMatch(in: line, range: range) else { return nil }
        func group(_ i: Int) -> String? {
            Range(m.range(at: i), in: line).map { String(line[$0]) }
        }
        func time(_ base: Int) -> Time {
            let h = Double(group(base) ?? "0") ?? 0
            let mnt = Double(group(base + 1) ?? "0") ?? 0
            let s = Double(group(base + 2) ?? "0") ?? 0
            let fraction = group(base + 3).map { Double("0." + $0) ?? 0 } ?? 0
            return Time(seconds: h * 3600 + mnt * 60 + s + fraction)
        }
        return (time(1), time(5))
    }
}
