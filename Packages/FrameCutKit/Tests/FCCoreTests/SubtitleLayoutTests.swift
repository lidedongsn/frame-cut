@testable import FCCore
import XCTest

final class SubtitleLayoutTests: XCTestCase {
    private let canvas = CGSize(width: 1000, height: 500)

    func testFrameCenteredAtPosition() {
        var style = SubtitleStyle()
        style.horizontalPosition = 0.3
        style.verticalPosition = 0.8
        let r = style.frame(textSize: CGSize(width: 200, height: 40), canvas: canvas)
        XCTAssertEqual(r, CGRect(x: 200, y: 380, width: 200, height: 40))
    }

    func testFrameStaysInsideCanvas() {
        var style = SubtitleStyle()
        style.horizontalPosition = 0
        style.verticalPosition = 1
        let r = style.frame(textSize: CGSize(width: 200, height: 40), canvas: canvas)
        XCTAssertEqual(r, CGRect(x: 0, y: 460, width: 200, height: 40))
    }

    func testDefaultIsCenteredHorizontally() {
        XCTAssertEqual(SubtitleStyle().horizontalPosition, 0.5)
    }

    func testOldStyleDecodesWithCenteredPosition() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SubtitleStyle())) as! [String: Any]
        json["horizontalPosition"] = nil
        let style = try JSONDecoder().decode(SubtitleStyle.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(style.horizontalPosition, 0.5)
        XCTAssertEqual(style.fontSize, SubtitleStyle().fontSize)
    }
}
