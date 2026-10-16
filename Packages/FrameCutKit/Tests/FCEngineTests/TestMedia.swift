import Foundation
import XCTest

enum TestMedia {
    static let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("TestMedia")

    static func url(_ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("缺少测试素材 \(name)，先运行 scripts/make-test-media.sh")
        }
        return url
    }
}
