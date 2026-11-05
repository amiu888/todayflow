#if canImport(AppKit)
import AppKit
import Testing
import UniformTypeIdentifiers
import TodayFlowCore
import TodayFlowFeatures

@Suite("Contact drag payload")
@MainActor
struct ContactDragPayloadTests {
    @Test func roundTripsWithoutSourceGroup() throws {
        let id = UUIDv7.new()
        let decoded = try #require(
            ContactDragPayload.decode(id.uuid.uuidString)
        )
        #expect(decoded.contactId == id)
        #expect(decoded.sourceGroupId == nil)
    }

    @Test func roundTripsWithSourceGroup() throws {
        let id = UUIDv7.new()
        let group = UUIDv7.new()
        let decoded = try #require(
            ContactDragPayload.decode("\(id.uuid.uuidString)|\(group.uuid.uuidString)")
        )
        #expect(decoded.contactId == id)
        #expect(decoded.sourceGroupId == group)
    }

    @Test func rejectsMalformedPayload() {
        #expect(ContactDragPayload.decode("not-a-uuid") == nil)
        #expect(ContactDragPayload.decode("") == nil)
    }

    @Test func providerUsesTheInternalContactType() {
        let payload = ContactDragPayload(
            contactId: .new(),
            sourceGroupId: .new()
        )
        #expect(
            payload.itemProvider().hasItemConformingToTypeIdentifier(
                UTType.todayFlowContact.identifier
            )
        )
    }

    @Test func loadAllReadsInternalProviders() async {
        let id = UUIDv7.new()
        let group = UUIDv7.new()
        let provider = NSItemProvider(
            item: "\(id.uuid.uuidString)|\(group.uuid.uuidString)" as NSString,
            typeIdentifier: UTType.todayFlowContact.identifier
        )
        let payloads = await ContactDragPayload.loadAll(from: [provider])
        #expect(payloads.count == 1)
        #expect(payloads.first?.contactId == id)
        #expect(payloads.first?.sourceGroupId == group)
    }
}
#endif
