import FCCore
import FCEngine
@testable import FCTranscribe
import XCTest

/// 诊断：对真实工程按指定声音来源识别并打印每段结果。
/// FC_PROJECT=<工程路径> [FC_ORIGINAL=0|1] [FC_MUSIC=0|1] [FC_SECONDS=秒数]
final class ProjectTranscribeProbe: XCTestCase {
    func testProbeProject() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["FC_PROJECT"] else { throw XCTSkip("设置 FC_PROJECT 运行") }
        let project = try ProjectFile.read(from: URL(fileURLWithPath: path))
        var samples = try await AudioExtractor.samples(project: project, original: env["FC_ORIGINAL"] != "0",
                                                       music: env["FC_MUSIC"] == "1")
        let from = env["FC_FROM"].flatMap(Int.init) ?? 0
        if from > 0 { samples = Array(samples.dropFirst(from * 16_000)) }
        if let s = env["FC_SECONDS"].flatMap(Int.init) { samples = Array(samples.prefix(s * 16_000)) }
        let segments = try await WhisperKitTranscriber.shared.transcribe(samples: samples) { _ in }
        XCTAssertFalse(segments.isEmpty)
        // 直接写 stderr：stdout 重定向到文件时 print 有缓冲，进程退出可能丢输出。
        for seg in segments {
            let line = String(format: "PROBE %6.2f-%6.2f ", seg.start.seconds + Double(from), seg.end.seconds + Double(from)) + seg.text + "\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }
}
