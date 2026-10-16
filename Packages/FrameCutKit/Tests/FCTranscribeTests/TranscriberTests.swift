import AVFoundation
import FCCore
@testable import FCTranscribe
import XCTest

final class TranscriberTests: XCTestCase {
    func testCleanRemovesTokensAndConvertsToSimplified() {
        XCTAssertEqual(WhisperKitTranscriber.clean(" <|zh|><|0.00|>今天天氣很好<|2.00|> "), "今天天气很好")
    }

    /// 真实识别：需联网下载模型，设置 FC_TRANSCRIBE=1 时运行。
    func testRealTranscription() async throws {
        guard ProcessInfo.processInfo.environment["FC_TRANSCRIBE"] == "1" else { throw XCTSkip("设置 FC_TRANSCRIBE=1 运行") }
        let dir = FileManager.default.temporaryDirectory
        let aiff = dir.appendingPathComponent("fc-speech.aiff")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", "Tingting", "-o", aiff.path, "大家好，今天我们去海边玩。天气非常好。"]
        try p.run()
        p.waitUntilExit()

        let file = try AVAudioFile(forReading: aiff)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: file.processingFormat, to: format)!
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: input)
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 1024)!
        var fed = false
        _ = converter.convert(to: output, error: nil) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return input
        }
        let samples = Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
        let segments = try await WhisperKitTranscriber.shared.transcribe(samples: samples) { print("progress", $0) }
        print("SEGMENTS", segments)
        let text = segments.map(\.text).joined()
        XCTAssertTrue(text.contains("海边"), text)
    }
}

final class SubtitleSplitTests: XCTestCase {
    func testSplitsAtPunctuationProportionally() {
        let seg = TranscriptSegment(start: .zero, end: Time(seconds: 5), text: "大家好,今天我们去海边玩,天气非常好。")
        let lines = SubtitleSplitter.split(seg)
        XCTAssertEqual(lines.map(\.text), ["大家好", "今天我们去海边玩", "天气非常好"])
        XCTAssertEqual(lines.first?.start, .zero)
        XCTAssertEqual(lines.last?.end, Time(seconds: 5))
        // 时间按字数分配：3 / 8 / 5 字
        XCTAssertEqual(lines[1].start.seconds, 5.0 * 3 / 16, accuracy: 0.01)
        for (a, b) in zip(lines, lines.dropFirst()) { XCTAssertEqual(a.end, b.start) }
    }

    func testShortSegmentKeptWhole() {
        let seg = TranscriptSegment(start: Time(seconds: 1), end: Time(seconds: 2), text: "你好。")
        XCTAssertEqual(SubtitleSplitter.split(seg), [TranscriptSegment(start: Time(seconds: 1), end: Time(seconds: 2), text: "你好")])
    }

    func testLongClauseWithoutPunctuationSplitByLength() {
        let text = String(repeating: "很", count: 40)
        let lines = SubtitleSplitter.split(TranscriptSegment(start: .zero, end: Time(seconds: 8), text: text))
        XCTAssertTrue(lines.allSatisfy { $0.text.count <= SubtitleSplitter.maxCharacters })
        XCTAssertEqual(lines.map(\.text).joined(), text)
    }

    func testEnglishKeepsInnerSpaces() {
        let lines = SubtitleSplitter.split(TranscriptSegment(start: .zero, end: Time(seconds: 2), text: "Hello world, nice day."))
        XCTAssertEqual(lines.map(\.text), ["Hello world", "nice day"])
    }
}
