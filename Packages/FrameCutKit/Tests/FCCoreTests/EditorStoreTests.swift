import XCTest
@testable import FCCore

@MainActor
final class EditorStoreTests: XCTestCase {
    func testUndoRedo() {
        let store = EditorStore(project: makeProject(clipSeconds: [10]))
        store.perform { _ = $0.splitMain(at: Time(seconds: 5)) }
        XCTAssertEqual(store.project.mainTrack.count, 2)
        XCTAssertTrue(store.canUndo)
        store.undo()
        XCTAssertEqual(store.project.mainTrack.count, 1)
        XCTAssertTrue(store.canRedo)
        store.redo()
        XCTAssertEqual(store.project.mainTrack.count, 2)
    }

    func testNewEditClearsRedo() {
        let store = EditorStore(project: makeProject(clipSeconds: [10]))
        store.perform { _ = $0.splitMain(at: Time(seconds: 5)) }
        store.undo()
        store.perform { $0.name = "x" }
        XCTAssertFalse(store.canRedo)
    }

    func testCoalescing() {
        let store = EditorStore(project: makeProject(clipSeconds: [10]))
        let id = store.project.mainTrack[0].id
        store.beginCoalescing()
        for v in [0.5, 0.6, 0.7] { store.perform { $0.updateMain(id: id) { $0.volume = v } } }
        store.endCoalescing()
        XCTAssertEqual(store.project.mainTrack[0].volume, 0.7)
        store.undo()
        XCTAssertEqual(store.project.mainTrack[0].volume, 1)
        XCTAssertFalse(store.canUndo)
    }

    func testNoOpPerformNotRecorded() {
        let store = EditorStore(project: makeProject(clipSeconds: [10]))
        store.perform { _ in }
        XCTAssertFalse(store.canUndo)
    }

    func testUndoLimit() {
        let store = EditorStore(project: Project(name: "t"))
        for i in 0..<150 { store.perform { $0.name = "\(i)" } }
        var count = 0
        while store.canUndo { store.undo(); count += 1 }
        XCTAssertEqual(count, 100)
    }

    func testOnChangeCalled() {
        let store = EditorStore(project: Project(name: "t"))
        var calls = 0
        store.onChange = { _ in calls += 1 }
        store.perform { $0.name = "a" }
        store.undo()
        XCTAssertEqual(calls, 2)
    }
}
