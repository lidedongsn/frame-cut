import Foundation

/// 用户保存的一套调色（风格 + 调节 + HSL + 效果）。
public struct GradePreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var filter: FilterSettings

    public init(id: UUID = UUID(), name: String, filter: FilterSettings) {
        self.id = id
        self.name = name
        self.filter = filter
    }
}

/// 调色预设库：App 级，所有工程共用，存为 Application Support/FrameCut/GradePresets.json。
public final class GradePresetStore {
    public static let fileName = "GradePresets.json"

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FrameCut", isDirectory: true)
    }

    public private(set) var presets: [GradePreset] = []
    private let url: URL

    public init(directory: URL = GradePresetStore.defaultDirectory) {
        url = directory.appendingPathComponent(Self.fileName)
        guard let data = try? Data(contentsOf: url) else { return }
        if let list = try? JSONDecoder().decode([GradePreset].self, from: data) {
            presets = list
        } else {
            // 读不了的文件留个备份，不直接覆盖
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("bak"))
        }
    }

    @discardableResult
    public func save(name: String, filter: FilterSettings) throws -> GradePreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = GradePreset(name: trimmed.isEmpty ? "我的调色 \(presets.count + 1)" : trimmed, filter: filter)
        presets.append(preset)
        try persist()
        return preset
    }

    public func rename(_ id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].name = trimmed
        try persist()
    }

    public func delete(_ id: UUID) throws {
        presets.removeAll { $0.id == id }
        try persist()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(presets).write(to: url, options: .atomic)
    }
}
