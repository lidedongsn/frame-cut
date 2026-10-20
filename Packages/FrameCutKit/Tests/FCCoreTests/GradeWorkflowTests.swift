import XCTest
@testable import FCCore

final class GradeWorkflowTests: XCTestCase {
    private func graded() -> FilterSettings {
        var f = FilterSettings(preset: .film)
        f.shadows = 0.3
        f.hsl[.blue] = HSLAdjust(saturation: 0.4)
        f.vignette = 0.2
        return f
    }

    func testPasteFilterToClips() {
        var p = makeProject(clipSeconds: [2, 2, 2])
        let ids = p.mainTrack.map(\.id)
        p.applyFilter(graded(), to: [ids[0], ids[2]])
        XCTAssertEqual(p.mainTrack[0].filter, graded())
        XCTAssertTrue(p.mainTrack[1].filter.isIdentity)
        XCTAssertEqual(p.mainTrack[2].filter, graded())
    }

    func testWithoutGradingStripsEveryClip() {
        var p = makeProject(clipSeconds: [2, 2])
        p.applyFilterToAll(graded())
        p.mainTrack[0].transform.scale = 1.5
        let original = p.withoutGrading()
        XCTAssertTrue(original.mainTrack.allSatisfy { $0.filter.isIdentity })
        XCTAssertEqual(original.mainTrack[0].transform.scale, 1.5, "只去掉调色，其他不变")
        XCTAssertEqual(CompositionInvariant.durations(original), CompositionInvariant.durations(p))
    }

    func testPresetStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fc-presets-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = GradePresetStore(directory: dir)
        XCTAssertTrue(store.presets.isEmpty)
        let saved = try store.save(name: "海边", filter: graded())
        XCTAssertEqual(store.presets.map(\.name), ["海边"])

        let reloaded = GradePresetStore(directory: dir)
        XCTAssertEqual(reloaded.presets.first?.filter, graded())
        XCTAssertEqual(reloaded.presets.first?.id, saved.id)

        try reloaded.rename(saved.id, to: "夕阳")
        try reloaded.delete(saved.id)
        XCTAssertTrue(GradePresetStore(directory: dir).presets.isEmpty)
    }

    func testPresetNameTrimmedAndDefaulted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fc-presets-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = GradePresetStore(directory: dir)
        XCTAssertEqual(try store.save(name: "  ", filter: graded()).name, "我的调色 1")
        XCTAssertEqual(try store.save(name: " 暖 ", filter: graded()).name, "暖")
        XCTAssertEqual(try store.save(name: "", filter: graded()).name, "我的调色 3")
    }

    func testCorruptPresetFileIgnored() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fc-presets-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent(GradePresetStore.fileName))
        XCTAssertTrue(GradePresetStore(directory: dir).presets.isEmpty)
    }
}

/// 测试辅助：各片段的时间线时长。
enum CompositionInvariant {
    static func durations(_ p: Project) -> [Time] { TimelineLayout(project: p).placements.map(\.duration) }
}
