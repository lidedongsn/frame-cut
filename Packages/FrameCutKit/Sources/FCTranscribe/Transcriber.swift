import FCCore
import Foundation
import WhisperKit

public struct TranscriptSegment: Equatable, Sendable {
    public var start: Time
    public var end: Time
    public var text: String

    public init(start: Time, end: Time, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum TranscribeError: LocalizedError {
    case downloadFailed

    public var errorDescription: String? { "识别模型下载失败，请检查网络后重试" }
}

public enum TranscribeProgress: Sendable {
    case downloading(Double)
    case loading
    case transcribing(Double)
}

public protocol Transcriber: Sendable {
    /// samples：16kHz 单声道。返回的时间与 samples 起点对齐。
    func transcribe(samples: [Float], progress: @escaping @Sendable (TranscribeProgress) -> Void) async throws -> [TranscriptSegment]
}

/// 本地 Whisper 识别。首次使用下载模型到 ~/Library/Application Support/FrameCut/Models。
public actor WhisperKitTranscriber: Transcriber {
    public static let shared = WhisperKitTranscriber()
    public static let modelVariant = "openai_whisper-small"

    private var pipe: WhisperKit?

    public init() {}

    static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("FrameCut/Models", isDirectory: true)
    }

    static var expectedModelFolder: URL {
        modelsDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(modelVariant)", isDirectory: true)
    }

    public static var isModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: expectedModelFolder.appendingPathComponent("AudioEncoder.mlmodelc").path)
    }

    public func transcribe(samples: [Float], progress: @escaping @Sendable (TranscribeProgress) -> Void) async throws -> [TranscriptSegment] {
        guard !samples.isEmpty else { return [] }
        let pipe = try await loadPipeline(progress: progress)
        progress(.transcribing(0))

        let total = Float(samples.count) / 16_000
        let options = DecodingOptions(
            verbose: false, task: .transcribe, language: nil, temperature: 0, usePrefillPrompt: true,
            detectLanguage: true, skipSpecialTokens: true, withoutTimestamps: false, chunkingStrategy: .vad)
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options, callback: nil) { segments in
            if let end = segments.map(\.end).max(), total > 0 { progress(.transcribing(Double(min(1, end / total)))) }
        }
        progress(.transcribing(1))
        return results.flatMap(\.segments).compactMap { seg in
            let text = Self.clean(seg.text)
            guard !text.isEmpty, seg.end > seg.start else { return nil }
            return TranscriptSegment(start: Time(seconds: Double(seg.start)), end: Time(seconds: Double(seg.end)), text: text)
        }.flatMap(SubtitleSplitter.split).sorted { $0.start < $1.start }
    }

    /// 官方源不可达时（如国内网络）依次尝试镜像。
    static let endpoints = ["https://huggingface.co", "https://hf-mirror.com"]

    /// 依次尝试各下载源；模型与分词器从同一个可用源获取，已下载的不会重复下载。
    private func loadPipeline(progress: @escaping @Sendable (TranscribeProgress) -> Void) async throws -> WhisperKit {
        if let pipe { return pipe }
        try FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
        var lastError: Error?
        for endpoint in Self.endpoints {
            do {
                let folder: URL
                if Self.isModelDownloaded {
                    folder = Self.expectedModelFolder
                } else {
                    progress(.downloading(0))
                    folder = try await WhisperKit.download(variant: Self.modelVariant, downloadBase: Self.modelsDirectory,
                                                           endpoint: endpoint) { p in
                        progress(.downloading(p.fractionCompleted))
                    }
                }
                try await Self.ensureTokenizer(endpoint: endpoint)
                progress(.loading)
                let config = WhisperKitConfig(modelEndpoint: endpoint, modelFolder: folder.path, tokenizerFolder: Self.modelsDirectory,
                                              verbose: false, logLevel: .error, prewarm: true, load: true, download: false)
                let pipe = try await WhisperKit(config)
                self.pipe = pipe
                return pipe
            } catch {
                lastError = error
            }
        }
        throw lastError ?? TranscribeError.downloadFailed
    }

    static let tokenizerRepo = "openai/whisper-small"

    /// WhisperKit 的分词器下载固定走官方源，这里先从可用源下载到它会优先读取的本地目录。
    static func ensureTokenizer(endpoint: String) async throws {
        let folder = modelsDirectory.appendingPathComponent("models/\(tokenizerRepo)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["tokenizer.json", "tokenizer_config.json"] {
            let dest = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            let url = URL(string: "\(endpoint)/\(tokenizerRepo)/resolve/main/\(name)")!
            let (tmp, response) = try await URLSession.shared.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TranscribeError.downloadFailed }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
        }
    }

    /// 去掉特殊标记与多余空白，繁体转简体。
    static func clean(_ raw: String) -> String {
        let noTokens = raw.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
        let trimmed = noTokens.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? trimmed
    }
}
