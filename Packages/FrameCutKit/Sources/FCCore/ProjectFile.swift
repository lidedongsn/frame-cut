import Foundation

public enum ProjectFileError: LocalizedError {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v): "工程文件版本（\(v)）高于当前应用支持的版本，请升级 FrameCut。"
        }
    }
}

/// `.framecut` 工程包：目录内含 project.json 与 cache/。
public enum ProjectFile {
    public static let fileExtension = "framecut"
    static let jsonName = "project.json"

    public static func write(_ project: Project, to packageURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: packageURL.appendingPathComponent(jsonName), options: .atomic)
    }

    public static func read(from packageURL: URL) throws -> Project {
        let data = try Data(contentsOf: packageURL.appendingPathComponent(jsonName))
        let project = try JSONDecoder().decode(Project.self, from: data)
        if project.schemaVersion > Project.currentSchemaVersion {
            throw ProjectFileError.unsupportedVersion(project.schemaVersion)
        }
        return project
    }

    public static func cacheDirectory(for packageURL: URL) -> URL {
        let url = packageURL.appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// 最近打开的工程（最多 20 个，自动过滤已不存在的）。
public struct RecentProjects {
    static let key = "FrameCut.recentProjects"
    static let limit = 20

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func list() -> [URL] {
        let paths = defaults.stringArray(forKey: RecentProjects.key) ?? []
        return paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    public func add(_ url: URL) {
        var paths = defaults.stringArray(forKey: RecentProjects.key) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        defaults.set(Array(paths.prefix(RecentProjects.limit)), forKey: RecentProjects.key)
    }

    public func remove(_ url: URL) {
        var paths = defaults.stringArray(forKey: RecentProjects.key) ?? []
        paths.removeAll { $0 == url.path }
        defaults.set(paths, forKey: RecentProjects.key)
    }

    /// 清空记录（不删除工程文件）。
    public func clear() {
        defaults.removeObject(forKey: RecentProjects.key)
    }
}
