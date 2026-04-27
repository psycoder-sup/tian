import Testing
import Foundation
@testable import tian

@Suite("LimitedBuffer")
struct LimitedBufferTests {

    @Test func append_belowCap_doesNotTruncate() {
        let buffer = LimitedBuffer(cap: 100)
        buffer.append(Data(repeating: 0x41, count: 50))
        let (data, truncated) = buffer.snapshot()
        #expect(data.count == 50)
        #expect(truncated == false)
    }

    @Test func append_exactlyAtCap_marksTruncated() {
        // Chunk fills the buffer to the cap exactly. Any further data would be
        // dropped, so the truncation flag must be set so the eventual log line
        // surfaces the fact that we may have lost output.
        let buffer = LimitedBuffer(cap: 100)
        buffer.append(Data(repeating: 0x41, count: 100))
        let (data, truncated) = buffer.snapshot()
        #expect(data.count == 100)
        #expect(truncated == true)
    }

    @Test func append_overflow_truncatesAndKeepsPrefix() {
        let buffer = LimitedBuffer(cap: 100)
        buffer.append(Data(repeating: 0x41, count: 150))
        let (data, truncated) = buffer.snapshot()
        #expect(data.count == 100)
        #expect(truncated == true)
        #expect(data == Data(repeating: 0x41, count: 100))
    }

    @Test func append_afterTruncation_isDiscarded() {
        let buffer = LimitedBuffer(cap: 100)
        buffer.append(Data(repeating: 0x41, count: 150))   // truncates here
        buffer.append(Data(repeating: 0x42, count: 50))    // ignored
        let (data, truncated) = buffer.snapshot()
        #expect(data.count == 100)
        #expect(truncated == true)
        // No 0x42 bytes leaked into the buffer.
        #expect(data == Data(repeating: 0x41, count: 100))
    }

    @Test func append_multipleSmallChunks_accumulate() {
        let buffer = LimitedBuffer(cap: 100)
        for _ in 0..<10 {
            buffer.append(Data(repeating: 0x41, count: 5))
        }
        let (data, truncated) = buffer.snapshot()
        #expect(data.count == 50)
        #expect(truncated == false)
    }
}
