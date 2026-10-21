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

/// 识别语言。指定语言比自动检测更准，也避免把中文误判成其他语言。
public enum TranscribeLanguage: String, CaseIterable, Sendable {
    case chinese = "zh"
    case english = "en"
    case auto

    public var title: String {
        switch self {
        case .chinese: "中文"
        case .english: "英文"
        case .auto: "自动"
        }
    }

    var code: String? { self == .auto ? nil : rawValue }
}

public protocol Transcriber: Sendable {
    /// samples：16kHz 单声道。返回的时间与 samples 起点对齐。
    func transcribe(samples: [Float], language: TranscribeLanguage,
                    progress: @escaping @Sendable (TranscribeProgress) -> Void) async throws -> [TranscriptSegment]
}

/// 本地 Whisper 识别。首次使用下载模型到 ~/Library/Application Support/FrameCut/Models。
public actor WhisperKitTranscriber: Transcriber {
    public static let shared = WhisperKitTranscriber()
    /// large-v3 turbo（压缩版，下载约 600MB）：中文准确率远高于 small，在 M 芯片神经网络引擎上依然很快。
    public static let defaultVariant = "openai_whisper-large-v3-v20240930_626MB"
    /// 旧版本用过的模型，换模型后自动删除以免占用磁盘。
    static let legacyVariants = ["openai_whisper-small"]

    /// 默认模型的下载大小，界面提示用。
    public static let downloadSizeMB = 600

    public let variant: String

    private var pipe: WhisperKit?
    /// 识别完成后空闲多久释放模型（大模型占用较多内存）。
    public static let idleUnloadSeconds: UInt64 = 180
    private var useGeneration = 0

    public init(variant: String = WhisperKitTranscriber.defaultVariant) {
        self.variant = variant
    }

    public var isLoaded: Bool { pipe != nil }

    /// 释放已加载的模型，下次识别时重新加载。
    public func unload() {
        pipe = nil
    }

    /// 已下载模型占用的磁盘空间（字节）。
    public static var modelDiskSize: Int64 { ModelStorage.size(of: modelsDirectory) }

    /// 删除已下载的模型（下次识别会重新下载）。
    public func deleteModel() throws {
        pipe = nil
        try ModelStorage.delete(Self.modelsDirectory)
    }

    private func scheduleIdleUnload() {
        useGeneration += 1
        let generation = useGeneration
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.idleUnloadSeconds * 1_000_000_000)
            await self?.unloadIfIdle(generation)
        }
    }

    private func unloadIfIdle(_ generation: Int) {
        if generation == useGeneration { pipe = nil }
    }

    static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("FrameCut/Models", isDirectory: true)
    }

    static func modelFolder(_ variant: String) -> URL {
        modelsDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(variant)", isDirectory: true)
    }

    var isModelDownloaded: Bool { Self.isModelComplete(at: Self.modelFolder(variant)) }

    /// 三个核心模型都在才算下载完整（下载中断时可能只有一部分）。
    static func isModelComplete(at folder: URL) -> Bool {
        ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    /// 分词器仓库：large-v3 系列共用一个，其余按尺寸。
    var tokenizerRepo: String {
        variant.contains("large-v3") ? "openai/whisper-large-v3" : "openai/whisper-small"
    }

    /// 删除旧版本留下的模型与分词器。
    static func removeLegacyModels() {
        for legacy in legacyVariants {
            try? FileManager.default.removeItem(at: modelFolder(legacy))
        }
        try? FileManager.default.removeItem(at: modelsDirectory.appendingPathComponent("models/openai/whisper-small"))
    }

    public func transcribe(samples: [Float], language: TranscribeLanguage = .chinese,
                           progress: @escaping @Sendable (TranscribeProgress) -> Void) async throws -> [TranscriptSegment] {
        guard !samples.isEmpty else { return [] }
        useGeneration += 1
        defer { scheduleIdleUnload() }
        let pipe = try await loadPipeline(progress: progress)
        progress(.transcribing(0))

        let total = Float(samples.count) / 16_000
        let options = Self.decodingOptions(language: language)
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

    /// 识别参数。
    /// - 分块串行处理：WhisperKit 并发分块时会随机丢掉整块结果（失败只写调试日志）。
    /// - 不设首词置信度门槛：哭腔、配乐下开头一词置信度低，会导致整个 30 秒窗口被丢弃。
    /// - 不加提示语：实测对准确率没有帮助，还会让模型输出孤立的引号后提前结束。
    static func decodingOptions(language: TranscribeLanguage) -> DecodingOptions {
        DecodingOptions(
            verbose: false, task: .transcribe, language: language.code, temperature: 0, usePrefillPrompt: true,
            detectLanguage: language.code == nil, skipSpecialTokens: true, withoutTimestamps: false,
            firstTokenLogProbThreshold: nil, concurrentWorkerCount: 1, chunkingStrategy: .vad)
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
                if isModelDownloaded {
                    folder = Self.modelFolder(variant)
                } else {
                    progress(.downloading(0))
                    folder = try await WhisperKit.download(variant: variant, downloadBase: Self.modelsDirectory,
                                                           endpoint: endpoint) { p in
                        progress(.downloading(p.fractionCompleted))
                    }
                }
                try await Self.ensureTokenizer(repo: tokenizerRepo, endpoint: endpoint)
                progress(.loading)
                let config = WhisperKitConfig(modelEndpoint: endpoint, modelFolder: folder.path, tokenizerFolder: Self.modelsDirectory,
                                              verbose: false, logLevel: .error, prewarm: true, load: true, download: false)
                let pipe = try await WhisperKit(config)
                self.pipe = pipe
                if variant == Self.defaultVariant { Self.removeLegacyModels() }
                return pipe
            } catch {
                lastError = error
            }
        }
        throw lastError ?? TranscribeError.downloadFailed
    }

    /// WhisperKit 的分词器下载固定走官方源，这里先从可用源下载到它会优先读取的本地目录。
    static func ensureTokenizer(repo: String, endpoint: String) async throws {
        let folder = modelsDirectory.appendingPathComponent("models/\(repo)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["tokenizer.json", "tokenizer_config.json"] {
            let dest = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            let url = URL(string: "\(endpoint)/\(repo)/resolve/main/\(name)")!
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

/// 模型目录的大小统计与删除。
public enum ModelStorage {
    public static func size(of directory: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard v?.isRegularFile == true else { continue }
            total += Int64(v?.fileSize ?? 0)
        }
        return total
    }

    public static func delete(_ directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
