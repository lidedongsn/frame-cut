@testable import FCCore
import XCTest

final class SRTTests: XCTestCase {
    func testEncode() {
        let subs = [Subtitle(start: Time(seconds: 1.5), end: Time(seconds: 3), text: "你好"),
                    Subtitle(start: Time(seconds: 3661.042), end: Time(seconds: 3662), text: "第二行")]
        XCTAssertEqual(SRT.encode(subs), """
        1
        00:00:01,500 --> 00:00:03,000
        你好

        2
        01:01:01,042 --> 01:01:02,000
        第二行

        """)
    }

    func testDecodeToleratesCRLFBOMDotsAndMultiline() {
        let text = "\u{FEFF}1\r\n00:00:01.5 --> 00:00:03,000\r\n第一行\r\n第二行\r\n\r\n\r\n2\r\n00:00:04,000 --> 00:00:05,000 X1:0\r\n<i>斜体</i>\r\n"
        let subs = SRT.decode(text)
        XCTAssertEqual(subs.count, 2)
        XCTAssertEqual(subs[0].start, Time(seconds: 1.5))
        XCTAssertEqual(subs[0].end, Time(seconds: 3))
        XCTAssertEqual(subs[0].text, "第一行\n第二行")
        XCTAssertEqual(subs[1].text, "斜体")
    }

    func testRoundTrip() {
        let subs = [Subtitle(start: Time(seconds: 0), end: Time(seconds: 1.25), text: "a"),
                    Subtitle(start: Time(seconds: 2), end: Time(seconds: 3), text: "b c")]
        XCTAssertEqual(SRT.decode(SRT.encode(subs)).map { [$0.start, $0.end] }, subs.map { [$0.start, $0.end] })
        XCTAssertEqual(SRT.decode(SRT.encode(subs)).map(\.text), ["a", "b c"])
    }

    func testDecodeSkipsGarbage() {
        XCTAssertTrue(SRT.decode("not a subtitle file").isEmpty)
    }

    func testDecodeDataDetectsEncoding() {
        let text = "1\n00:00:01,000 --> 00:00:02,000\n你好世界\n"
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        for data in [Data(text.utf8),
                     text.data(using: String.Encoding(rawValue: gb))!,
                     text.data(using: .utf16)!] {  // .utf16 带 BOM
            XCTAssertEqual(SRT.decode(data: data).first?.text, "你好世界")
        }
    }

    func testEncodeCollapsesBlankLinesInsideText() {
        let subs = [Subtitle(start: .zero, end: Time(seconds: 1), text: "上\n\n下")]
        XCTAssertEqual(SRT.decode(SRT.encode(subs)).first?.text, "上\n下")
    }
}
