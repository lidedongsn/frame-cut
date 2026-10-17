import FCCore
@testable import FCEngine
import XCTest

final class LRUCacheTests: XCTestCase {
    func testEvictsLeastRecentlyUsed() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache["a"] = 1
        cache["b"] = 2
        XCTAssertEqual(cache["a"], 1)   // a 变为最近使用
        cache["c"] = 3
        XCTAssertNil(cache["b"])
        XCTAssertEqual(cache["a"], 1)
        XCTAssertEqual(cache["c"], 3)
        XCTAssertEqual(cache.count, 2)
    }

    /// 拖动滑块产生大量不同参数时，缓存不应整体清空：最近用过的 LUT 仍在。
    func testFilterLUTKeepsRecentEntriesUnderChurn() {
        var f = FilterSettings(preset: .warm)
        let first = FilterLUT.data(f, space: .sdr)
        // 共 71 个不同 LUT，超过容量 64；常用的那个在 i=60 时最后一次使用
        for i in 1...70 {
            f.brightness = Double(i) / 100
            _ = FilterLUT.data(f, space: .sdr)
            if i % 10 == 0, i <= 60 { _ = FilterLUT.data(FilterSettings(preset: .warm), space: .sdr) }
        }
        XCTAssertTrue(FilterLUT.isCached(FilterSettings(preset: .warm), space: .sdr))
        XCTAssertNotNil(first)
    }
}
