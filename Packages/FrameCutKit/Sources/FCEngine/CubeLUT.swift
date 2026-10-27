import FCCore
import Foundation
import simd

/// .cube 格式的 3D LUT（Adobe / Resolve 通用格式）。数据按 R 变化最快排列。
struct CubeLUT: Sendable {
    enum ParseError: LocalizedError {
        case notCube, unsupported1D, wrongCount(expected: Int, got: Int)

        var errorDescription: String? {
            switch self {
            case .notCube: String(localized: "不是有效的 .cube 文件", bundle: .module)
            case .unsupported1D: String(localized: "暂不支持 1D LUT，请使用 3D LUT", bundle: .module)
            case .wrongCount(let e, let g): String(localized: ".cube 数据不完整（应有 \(e) 行，实际 \(g) 行）", bundle: .module)
            }
        }
    }

    let size: Int
    let title: String?
    let domainMin: SIMD3<Double>
    let domainMax: SIMD3<Double>
    let values: [SIMD3<Float>]

    static func parse(_ text: String) throws -> CubeLUT {
        var size = 0
        var title: String?
        var dMin = SIMD3<Double>(repeating: 0), dMax = SIMD3<Double>(repeating: 1)
        var values: [SIMD3<Float>] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            switch parts[0] {
            case "TITLE":
                title = line.dropFirst(5).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            case "LUT_3D_SIZE":
                size = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            case "LUT_1D_SIZE":
                throw ParseError.unsupported1D
            case "DOMAIN_MIN", "DOMAIN_MAX":
                let v = parts.dropFirst().compactMap { Double($0) }
                guard v.count == 3 else { throw ParseError.notCube }
                if parts[0] == "DOMAIN_MIN" { dMin = SIMD3(v[0], v[1], v[2]) } else { dMax = SIMD3(v[0], v[1], v[2]) }
            default:
                let v = parts.compactMap { Float($0) }
                if v.count == 3, parts.count == 3 {
                    values.append(SIMD3(v[0], v[1], v[2]))
                } else if Float(parts[0]) != nil {
                    throw ParseError.notCube
                }
                // 其他关键字（如 LUT_3D_INPUT_RANGE 之外的厂商扩展）忽略
            }
        }
        guard size >= 2, size <= 256 else { throw ParseError.notCube }
        guard values.count == size * size * size else { throw ParseError.wrongCount(expected: size * size * size, got: values.count) }
        return CubeLUT(size: size, title: title, domainMin: dMin, domainMax: dMax, values: values)
    }

    /// 三线性插值取值；输入按 DOMAIN 归一化并截断到 0...1。
    func sample(_ c: SIMD3<Double>) -> SIMD3<Double> {
        let n = size - 1
        let t = simd_clamp((c - domainMin) / simd_max(domainMax - domainMin, SIMD3(repeating: 1e-9)), .zero, .one) * Double(n)
        let i0 = SIMD3<Int>(Int(t.x), Int(t.y), Int(t.z))
        let i1 = SIMD3<Int>(min(i0.x + 1, n), min(i0.y + 1, n), min(i0.z + 1, n))
        let f = t - SIMD3(Double(i0.x), Double(i0.y), Double(i0.z))
        func v(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Double> {
            let x = values[r + g * size + b * size * size]
            return SIMD3(Double(x.x), Double(x.y), Double(x.z))
        }
        let c00 = simd_mix(v(i0.x, i0.y, i0.z), v(i1.x, i0.y, i0.z), SIMD3(repeating: f.x))
        let c10 = simd_mix(v(i0.x, i1.y, i0.z), v(i1.x, i1.y, i0.z), SIMD3(repeating: f.x))
        let c01 = simd_mix(v(i0.x, i0.y, i1.z), v(i1.x, i0.y, i1.z), SIMD3(repeating: f.x))
        let c11 = simd_mix(v(i0.x, i1.y, i1.z), v(i1.x, i1.y, i1.z), SIMD3(repeating: f.x))
        let c0 = simd_mix(c00, c10, SIMD3(repeating: f.y))
        let c1 = simd_mix(c01, c11, SIMD3(repeating: f.y))
        return simd_mix(c0, c1, SIMD3(repeating: f.z))
    }
}

/// 用户 LUT 库：导入的 .cube 存在 Application Support/FrameCut/LUTs/<id>/<名称>.cube，所有工程共用。
public final class UserLUTLibrary: @unchecked Sendable {
    public static let shared = UserLUTLibrary()

    private let lock = NSLock()
    private var cubes: [UUID: CubeLUT] = [:]
    private var refs: [UserLUTRef] = []

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FrameCut/LUTs", isDirectory: true)
    }

    public init() {}

    public var all: [UserLUTRef] { lock.withLock { refs } }

    func cube(_ id: UUID) -> CubeLUT? { lock.withLock { cubes[id] } }

    func register(id: UUID, cube: CubeLUT, name: String? = nil) {
        lock.withLock {
            cubes[id] = cube
            if !refs.contains(where: { $0.id == id }) { refs.append(UserLUTRef(id: id, name: name ?? cube.title ?? "LUT")) }
        }
    }

    /// 读取目录中已导入的 LUT（启动时调用）；损坏的文件跳过。
    public func load(from directory: URL = UserLUTLibrary.defaultDirectory) {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let sorted = dirs.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
        for dir in sorted {
            guard let id = UUID(uuidString: dir.lastPathComponent),
                  let file = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first(where: { $0.pathExtension.lowercased() == "cube" }),
                  let text = try? String(contentsOf: file, encoding: .utf8),
                  let cube = try? CubeLUT.parse(text) else { continue }
            register(id: id, cube: cube, name: file.deletingPathExtension().lastPathComponent)
        }
    }

    /// 导入 .cube：校验后复制到库目录。
    public func importFile(_ url: URL, into directory: URL = UserLUTLibrary.defaultDirectory) throws -> UserLUTRef {
        let text = try String(contentsOf: url, encoding: .utf8)
        let cube = try CubeLUT.parse(text)
        let id = UUID()
        let name = url.deletingPathExtension().lastPathComponent
        let dir = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try text.write(to: dir.appendingPathComponent(name + ".cube"), atomically: true, encoding: .utf8)
        register(id: id, cube: cube, name: name)
        return UserLUTRef(id: id, name: name)
    }

    public func remove(_ id: UUID, from directory: URL = UserLUTLibrary.defaultDirectory) {
        lock.withLock {
            cubes[id] = nil
            refs.removeAll { $0.id == id }
        }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString, isDirectory: true))
    }
}
