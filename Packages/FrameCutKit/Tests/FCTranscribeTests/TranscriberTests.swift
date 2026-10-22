import AVFoundation
import FCCore
@testable import FCTranscribe
import XCTest

final class TranscriberTests: XCTestCase {
    func testCleanRemovesTokensAndConvertsToSimplified() {
        XCTAssertEqual(WhisperKitTranscriber.clean(" <|zh|><|0.00|>今天天氣很好<|2.00|> "), "今天天气很好")
    }

    /// 下载中断只留下部分模型文件时不算已下载，下次会重新下载补齐。
    func testPartialModelFolderIsNotComplete() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fc-model-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("AudioEncoder.mlmodelc"), withIntermediateDirectories: true)
        XCTAssertFalse(WhisperKitTranscriber.isModelComplete(at: dir))
        for name in ["MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        XCTAssertTrue(WhisperKitTranscriber.isModelComplete(at: dir))
    }

    /// 并发分块会随机丢掉整段识别结果；首词置信度门槛会把哭腔、配乐下开头的整个窗口丢掉。
    func testDecodingOptionsAvoidDroppingWindows() {
        let options = WhisperKitTranscriber.decodingOptions(language: .chinese)
        XCTAssertEqual(options.concurrentWorkerCount, 1)
        XCTAssertNil(options.firstTokenLogProbThreshold)
        XCTAssertNil(options.promptTokens)
        XCTAssertEqual(options.language, "zh")
        XCTAssertFalse(options.detectLanguage)
        XCTAssertEqual(WhisperKitTranscriber.decodingOptions(language: .auto).language, nil)
        XCTAssertTrue(WhisperKitTranscriber.decodingOptions(language: .auto).detectLanguage)
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

final class ModelStorageTests: XCTestCase {
    func testDirectorySizeAndDelete() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fc-models-\(UUID())")
        let sub = dir.appendingPathComponent("models/a", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data(count: 3000).write(to: sub.appendingPathComponent("x.bin"))
        try Data(count: 2000).write(to: dir.appendingPathComponent("y.bin"))
        XCTAssertEqual(ModelStorage.size(of: dir), 5000)
        try ModelStorage.delete(dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertEqual(ModelStorage.size(of: dir), 0)
    }

    func testUnloadIsSafeWhenNotLoaded() async {
        let t = WhisperKitTranscriber()
        await t.unload()
        let loaded = await t.isLoaded
        XCTAssertFalse(loaded)
    }

    func testCharacterErrorRateIgnoresPunctuation() {
        XCTAssertEqual(Self.characterErrorRate(reference: "今天，天气好。", hypothesis: "今天天气好"), 0)
        XCTAssertEqual(Self.characterErrorRate(reference: "今天天气好", hypothesis: "今天天汽好"), 0.2, accuracy: 1e-9)
    }

    /// 中文准确率评测：不同语速朗读一段 vlog 口播并混入环境噪声，输出字错率（CER）。
    /// FC_TRANSCRIBE=1 运行；FC_VARIANT 指定模型，FC_LANG 指定语言（zh / en / auto）。
    func testChineseAccuracy() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["FC_TRANSCRIBE"] == "1" else { throw XCTSkip("设置 FC_TRANSCRIBE=1 运行") }
        let script: [(Int, String)] = [
            (180, "哈喽大家好，欢迎回到我的频道。今天带大家去杭州西湖边走一走。"),
            (220, "我们早上七点就出门了，人还不算多，空气特别清新。"),
            (260, "先去断桥拍了几张照片，然后沿着苏堤一直往南走。"),
            (200, "中午在一家本地小馆子吃了西湖醋鱼和东坡肉，味道真的很不错。"),
            (240, "下午租了一条小船，在湖上漂了大概40分钟，价格是150块。"),
            (280, "这次用的是 iPhone 拍的，全程开了 HDR，晚上的灯光效果特别好看。"),
            (220, "如果你们也喜欢这种慢节奏的旅行，记得点赞关注，我们下期再见。"),
        ]
        let dir = FileManager.default.temporaryDirectory
        var samples: [Float] = []
        for (i, (rate, line)) in script.enumerated() {
            let aiff = dir.appendingPathComponent("fc-eval-\(i).aiff")
            defer { try? FileManager.default.removeItem(at: aiff) }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            p.arguments = ["-v", "Tingting", "-r", "\(rate)", "-o", aiff.path, line]
            try p.run()
            p.waitUntilExit()
            samples += try Self.load16k(aiff)
            samples += [Float](repeating: 0, count: 8_000)
        }
        // 约 20dB 信噪比的环境噪声，模拟户外收音。
        var rng = SystemRandomNumberGenerator()
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        let noise = rms * 0.1
        samples = samples.map { $0 + Float.random(in: -1...1, using: &rng) * noise * 1.7 }

        let variant = env["FC_VARIANT"] ?? WhisperKitTranscriber.defaultVariant
        let language = TranscribeLanguage(rawValue: env["FC_LANG"] ?? "zh") ?? .chinese
        let transcriber = WhisperKitTranscriber(variant: variant)
        _ = try await transcriber.transcribe(samples: Array(samples.prefix(16_000)), language: language) { _ in }
        let start = Date()
        let segments = try await transcriber.transcribe(samples: samples, language: language) { _ in }
        let elapsed = Date().timeIntervalSince(start)
        let text = segments.map(\.text).joined()
        let reference = script.map(\.1).joined()
        let cer = Self.characterErrorRate(reference: reference, hypothesis: text)
        print("EVAL variant=\(variant) lang=\(language.rawValue) audio=\(samples.count / 16_000)s time=\(String(format: "%.1f", elapsed))s CER=\(String(format: "%.1f%%", cer * 100))")
        print("EVAL text:", segments.map(\.text).joined(separator: " | "))
        XCTAssertLessThan(cer, 0.15)
    }

    static func load16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
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
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }

    /// 字错率：忽略标点与空白、英文不区分大小写的编辑距离 / 参考长度。
    static func characterErrorRate(reference: String, hypothesis: String) -> Double {
        func normalize(_ s: String) -> [Character] {
            Array(s.lowercased().filter { !$0.isPunctuation && !$0.isWhitespace && !$0.isSymbol })
        }
        let r = normalize(reference), h = normalize(hypothesis)
        guard !r.isEmpty else { return h.isEmpty ? 0 : 1 }
        var prev = Array(0...h.count)
        for i in 1...r.count {
            var cur = [i] + [Int](repeating: 0, count: h.count)
            for j in stride(from: 1, through: h.count, by: 1) {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return Double(prev[h.count]) / Double(r.count)
    }
}
