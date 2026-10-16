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
