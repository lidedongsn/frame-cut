import FCCore
import Foundation

/// 把识别出的长句按标点（必要时按长度）拆成短字幕，时间按字数比例分配，去掉句末标点。
public enum SubtitleSplitter {
    public static let maxCharacters = 16
    static let punctuation = CharacterSet(charactersIn: ",.!?;:，。！？；：、…")

    public static func split(_ segment: TranscriptSegment) -> [TranscriptSegment] {
        var clauses: [String] = []
        var current = ""
        for ch in segment.text {
            if ch.unicodeScalars.allSatisfy({ punctuation.contains($0) }) {
                clauses.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        clauses.append(current)
        let pieces = clauses
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .flatMap(chunk)
        guard !pieces.isEmpty else { return [] }

        let total = pieces.reduce(0) { $0 + $1.count }
        let span = segment.end - segment.start
        var result: [TranscriptSegment] = []
        var cursor = segment.start
        var used = 0
        for (i, piece) in pieces.enumerated() {
            used += piece.count
            let end = i == pieces.count - 1 ? segment.end : segment.start + span * (Double(used) / Double(total))
            result.append(TranscriptSegment(start: cursor, end: end, text: piece))
            cursor = end
        }
        return result
    }

    /// 超长片段按长度均分。
    private static func chunk(_ s: String) -> [String] {
        guard s.count > maxCharacters else { return [s] }
        let parts = Int((Double(s.count) / Double(maxCharacters)).rounded(.up))
        let size = Int((Double(s.count) / Double(parts)).rounded(.up))
        var out: [String] = []
        var rest = Substring(s)
        while !rest.isEmpty {
            out.append(String(rest.prefix(size)))
            rest = rest.dropFirst(size)
        }
        return out
    }
}
