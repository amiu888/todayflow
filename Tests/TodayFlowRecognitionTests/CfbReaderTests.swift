import Foundation
import Testing
@testable import TodayFlowRecognition

@Suite("CfbReader")
struct CfbReaderTests {
    /// A `.msg`-shaped container: subject (8-bit), body (16-bit), and a
    /// delivery-time FILETIME, all small enough for the mini FAT.
    private static let msgFixture = CfbBuilder()
        .adding(name: "__substg1.0_0037001F", data: Data("Hello from Outlook\0".utf8))
        .adding(name: "__substg1.0_007D001E", data: utf16("Body text here"))
        .adding(name: "__substg1.0_00760040", data: fileTime(134_120_833_200_000_000))

    private static func utf16(_ text: String) -> Data {
        var bytes = [UInt8](text.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        bytes.append(0)
        bytes.append(0)
        return Data(bytes)
    }

    private static func fileTime(_ ticks: Int64) -> Data {
        var data = Data()
        for i in 0..<8 {
            data.append(UInt8((ticks >> (8 * i)) & 0xFF))
        }
        return data
    }

    @Test("readsMiniFatStreams")
    func readsMiniFatStreams() {
        let reader = CfbReader(data: Self.msgFixture.build())
        #expect(reader != nil)

        let subject = reader!.stream(named: "__substg1.0_0037001F")
        #expect(subject == Data("Hello from Outlook\0".utf8))

        let body = reader!.stream(named: "__substg1.0_007D001E")
        #expect(body == Self.utf16("Body text here"))
    }

    @Test("streamLookupIsCaseInsensitive")
    func streamLookupIsCaseInsensitive() {
        let reader = CfbReader(data: Self.msgFixture.build())
        #expect(reader != nil)
        #expect(reader!.stream(named: "__SUBSTG1.0_0037001F") != nil)
    }

    @Test("missingStreamYieldsNil")
    func missingStreamYieldsNil() {
        let reader = CfbReader(data: Self.msgFixture.build())
        #expect(reader != nil)
        #expect(reader!.stream(named: "__substg1.0_9999001F") == nil)
    }

    @Test("readsLargeStreamFromRegularFat")
    func readsLargeStreamFromRegularFat() {
        // Exactly the 4 KiB cutoff, so this must come from the regular FAT.
        let large = Data(repeating: 0x41, count: 4096)
        let reader = CfbReader(data: CfbBuilder()
            .adding(name: "__substg1.0_007D001F", data: large)
            .build())

        #expect(reader != nil)
        #expect(reader!.stream(named: "__substg1.0_007D001F") == large)
    }

    @Test("justBelowCutoffUsesMiniFat")
    func justBelowCutoffUsesMiniFat() {
        let small = Data(repeating: 0x42, count: 4095)
        let reader = CfbReader(data: CfbBuilder()
            .adding(name: "__substg1.0_007D001F", data: small)
            .build())

        #expect(reader != nil)
        #expect(reader!.stream(named: "__substg1.0_007D001F") == small)
    }

    @Test("garbageYieldsNil")
    func garbageYieldsNil() {
        #expect(CfbReader(data: Data("definitely not a cfb file".utf8)) == nil)
    }

    @Test("truncatedFileYieldsNil")
    func truncatedFileYieldsNil() {
        #expect(CfbReader(data: Data(repeating: 0xD0, count: 100)) == nil)
    }

    @Test("wrongSignatureYieldsNil")
    func wrongSignatureYieldsNil() {
        var bytes = [UInt8](Self.msgFixture.build())
        bytes[0] = 0x00
        #expect(CfbReader(data: Data(bytes)) == nil)
    }

    @Suite("MsgReader")
    struct MsgReaderTests {
        @Test("readsMessageFromCompoundFile")
        func readsMessageFromCompoundFile() {
            let message = MsgReader.read(CfbReaderTests.msgFixture.build())

            #expect(message != nil)
            #expect(message?.subject == "Hello from Outlook")
            #expect(message?.body == "Body text here")

            // 134,120,833,200,000,000 ticks = 2026-01-05 10:42:00 UTC.
            var components = DateComponents()
            components.year = 2026
            components.month = 1
            components.day = 5
            components.hour = 10
            components.minute = 42
            components.second = 0
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let expected = calendar.date(from: components)!
            #expect(message?.deliveredAt != nil)
            #expect(abs(message!.deliveredAt!.timeIntervalSince(expected)) < 0.001)
        }

        @Test("fileTimeConversion")
        func fileTimeConversion() {
            // 11,644,473,600 seconds (1601 → 1970) × 10,000,000 ticks/second.
            let epochTicks = Int64(11_644_473_600) * 10_000_000
            #expect(MsgReader.fileTimeToSeconds(epochTicks) != nil)
            #expect(abs(MsgReader.fileTimeToSeconds(epochTicks)!.timeIntervalSince1970) < 0.001)

            #expect(MsgReader.fileTimeToSeconds(0) == nil)
            #expect(MsgReader.fileTimeToSeconds(-5) == nil)
        }

        @Test("decodesStringStreams")
        func decodesStringStreams() {
            #expect(MsgReader.decodeString8(Data("héllo\0\0".utf8)) == "héllo")
            var bytes = [UInt8]("hi".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
            bytes.append(0)
            bytes.append(0)
            #expect(MsgReader.decodeString16(Data(bytes)) == "hi")
        }

        @Test("returnsNilForNonMsgData")
        func returnsNilForNonMsgData() {
            #expect(MsgReader.read(Data("plain text".utf8)) == nil)
        }
    }
}
