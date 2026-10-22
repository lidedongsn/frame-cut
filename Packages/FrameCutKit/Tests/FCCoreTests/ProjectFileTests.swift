import XCTest
@testable import FCCore

final class ProjectFileTests: XCTestCase {
    var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testWriteRead() throws {
        let url = dir.appendingPathComponent("a.framecut")
        let p = makeProject(clipSeconds: [3, 4])
        try ProjectFile.write(p, to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent("project.json").path))
        XCTAssertEqual(try ProjectFile.read(from: url), p)
        // 覆盖写
        var p2 = p
        p2.name = "改名"
        try ProjectFile.write(p2, to: url)
        XCTAssertEqual(try ProjectFile.read(from: url).name, "改名")
    }

    func testReadRejectsNewerSchema() throws {
        let url = dir.appendingPathComponent("b.framecut")
        var p = Project(name: "x")
        p.schemaVersion = 99
        try ProjectFile.write(p, to: url)
        XCTAssertThrowsError(try ProjectFile.read(from: url))
    }

    func testMissingAssetsDetected() throws {
        var p = makeProject(clipSeconds: [1])
        let real = dir.appendingPathComponent("real.mp4")
        FileManager.default.createFile(atPath: real.path, contents: Data())
        p.assets.append(MediaAsset(kind: .video, name: "r", path: real.path, duration: Time(seconds: 1), width: 1, height: 1, hasAudio: false, frameRate: 30))
        let missing = p.missingAssets { FileManager.default.fileExists(atPath: $0) }
        XCTAssertEqual(missing.map(\.path), ["/tmp/a.mp4"])
    }

    func testRecentProjects() throws {
        let defaults = UserDefaults(suiteName: "fc-test-\(UUID().uuidString)")!
        let recent = RecentProjects(defaults: defaults)
        let a = dir.appendingPathComponent("a.framecut")
        let b = dir.appendingPathComponent("b.framecut")
        try ProjectFile.write(Project(name: "a"), to: a)
        try ProjectFile.write(Project(name: "b"), to: b)
        recent.add(a)
        recent.add(b)
        recent.add(a)
        XCTAssertEqual(recent.list().map(\.lastPathComponent), ["a.framecut", "b.framecut"])
        try FileManager.default.removeItem(at: b)
        XCTAssertEqual(recent.list().map(\.lastPathComponent), ["a.framecut"])
    }

    func testRecentProjectsRemoveAndClearKeepFiles() throws {
        let defaults = UserDefaults(suiteName: "fc-test-\(UUID().uuidString)")!
        let recent = RecentProjects(defaults: defaults)
        let a = dir.appendingPathComponent("a.framecut")
        let b = dir.appendingPathComponent("b.framecut")
        try ProjectFile.write(Project(name: "a"), to: a)
        try ProjectFile.write(Project(name: "b"), to: b)
        recent.add(a)
        recent.add(b)
        recent.remove(b)
        XCTAssertEqual(recent.list().map(\.lastPathComponent), ["a.framecut"])
        recent.clear()
        XCTAssertEqual(recent.list(), [])
        // 只清记录，不动工程文件
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }
}
