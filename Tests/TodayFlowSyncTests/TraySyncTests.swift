import Foundation
import GRDB
import Testing
import TodayFlowCore
import TodayFlowPersistence
@testable import TodayFlowSync

/// Working trays are shared by a user's devices (Mac and iPhone); every other
/// setting stays on its device.
struct TraySyncTests {
    private func settings(_ mac: Mac) -> GRDBSettingRepository { GRDBSettingRepository(queue: mac.queue) }

    @Test func trays_reachTheOtherDevice_otherSettingsDoNot() async throws {
        let server = FakeServer()
        let mac = try Mac("Mac", server: server)
        let phone = try Mac("iPhone", server: server)
        try await settings(mac).set(#"[{"name":"Client A"}]"#, for: SettingKeys.workTrays)
        try await settings(mac).set(#"[{"rule":1}]"#, for: SettingKeys.workflowRules)
        try await settings(mac).set("due", for: SettingKeys.todaySort)
        try await mac.sync()
        try await phone.sync()
        #expect(await settings(phone).value(for: SettingKeys.workTrays) == #"[{"name":"Client A"}]"#)
        #expect(await settings(phone).value(for: SettingKeys.workflowRules) == #"[{"rule":1}]"#)
        #expect(await settings(phone).value(for: SettingKeys.todaySort) == nil)
        #expect(await server.data("setting", SettingKeys.todaySort) == nil)

        // And back: a tray edited on the phone reaches the Mac.
        try await settings(phone).set(#"[{"name":"Client A"},{"name":"Errands"}]"#, for: SettingKeys.workTrays)
        try await phone.sync()
        try await mac.sync()
        #expect(await settings(mac).value(for: SettingKeys.workTrays) == #"[{"name":"Client A"},{"name":"Errands"}]"#)
    }

    @Test func pairingANewDevice_keepsTheAccountsTraysAndItsOwn() async throws {
        let server = FakeServer()
        let mac = try Mac("Mac", server: server)
        try await settings(mac).set(#"[{"name":"Client A"}]"#, for: SettingKeys.workTrays)
        try await mac.sync()

        // A new device made its own tray before pairing, later in time.
        let phone = try Mac("iPhone", server: server)
        try await settings(phone).set(#"[{"name":"Errands"}]"#, for: SettingKeys.workTrays)
        try await phone.store.markAllPending()
        try await phone.sync()
        try await mac.sync()

        #expect(try await trays(phone) == ["Client A", "Errands"])
        #expect(try await trays(mac) == ["Client A", "Errands"])
    }

    @Test func pairing_mergesTraysByIdAndName_aTaskStaysInOneTray() async throws {
        let server = FakeServer()
        let mac = try Mac("Mac", server: server)
        try await settings(mac).set("""
            [{"id":"M","name":"Working tray","itemIds":["t2"],"sortOrder":0},
             {"id":"L","name":"Later","itemIds":["t1"],"sortOrder":1},
             {"id":"S","name":"Shared","itemIds":[],"sortOrder":2}]
            """, for: SettingKeys.workTrays)
        try await settings(mac).set(#"[{"id":"r1","sourceTrayId":"L","targetTrayId":"M"}]"#, for: SettingKeys.workflowRules)
        try await mac.sync()

        let phone = try Mac("iPhone", server: server)
        try await settings(phone).set("""
            [{"id":"P","name":"working Tray ","itemIds":["t1","t3"],"sortOrder":0},
             {"id":"S","name":"Shared","itemIds":["t4"],"sortOrder":1},
             {"id":"E","name":"Errands","itemIds":["t5"],"sortOrder":2}]
            """, for: SettingKeys.workTrays)
        try await settings(phone).set(#"[{"id":"r2","sourceTrayId":"P","targetTrayId":"E"}]"#, for: SettingKeys.workflowRules)
        try await phone.store.markAllPending()
        try await phone.sync()
        try await mac.sync()

        for device in [phone, mac] {
            let merged = try await trayRows(device)
            #expect(merged.map(\.id) == ["M", "L", "S", "E"])
            #expect(merged.map(\.items) == [["t2", "t3"], ["t1"], ["t4"], ["t5"]])
            #expect(merged.map(\.order) == [0, 1, 2, 3])
            let rules = try await ruleIds(device)
            #expect(rules == ["r1", "r2"])
        }
        // The phone's rule follows its tray into the Mac's same-named tray.
        #expect(try await settings(mac).value(for: SettingKeys.workflowRules)?.contains(#""sourceTrayId":"M""#) == true)
    }

    @Test func afterPairing_aDeletedTrayStaysDeleted() async throws {
        let server = FakeServer()
        let mac = try Mac("Mac", server: server)
        try await settings(mac).set(#"[{"id":"A","name":"A"},{"id":"B","name":"B"}]"#, for: SettingKeys.workTrays)
        try await mac.sync()
        let phone = try Mac("iPhone", server: server)
        try await phone.store.markAllPending()
        try await phone.sync()
        #expect(try await trays(phone) == ["A", "B"])

        try await settings(mac).set(#"[{"id":"A","name":"A"}]"#, for: SettingKeys.workTrays)
        try await mac.sync()
        try await phone.sync()
        #expect(try await trays(phone) == ["A"])
    }

    @Test func pairing_withNoTraysOnTheServer_uploadsThisDevicesTrays() async throws {
        let server = FakeServer()
        let mac = try Mac("Mac", server: server)
        try await settings(mac).set(#"[{"id":"A","name":"A"}]"#, for: SettingKeys.workTrays)
        try await mac.store.markAllPending()
        try await mac.sync()
        let phone = try Mac("iPhone", server: server)
        try await phone.store.markAllPending()
        try await phone.sync()
        #expect(try await trays(phone) == ["A"])
    }

    /// An older app version ignores entities it doesn't know but still moves
    /// its cursor past them; once it learns them, it pulls everything again.
    @Test func skippedChanges_arePulledAgainOnceTheyAreKnown() async throws {
        let mac = try Mac("Mac", server: FakeServer())
        let future = SyncChange(
            entity: "future_thing", id: "x", op: "upsert",
            changedAt: "2026-01-01T00:00:00.000Z", data: ["id": .string("x")]
        )
        try await mac.store.apply([future], cursor: 42)
        #expect(try await mac.store.cursor() == 42)
        #expect(try await mac.store.rewindForSkippedChanges { _ in false } == false)
        #expect(try await mac.store.cursor() == 42)
        #expect(try await mac.store.rewindForSkippedChanges { $0 == "future_thing" } == true)
        #expect(try await mac.store.cursor() == 0)
        // Only once.
        #expect(try await mac.store.rewindForSkippedChanges { _ in true } == false)
    }

    @Test func aRemoteChangeToAPrivateSetting_isIgnored() async throws {
        let mac = try Mac("Mac", server: FakeServer())
        let change = SyncChange(
            entity: "setting", id: SettingKeys.todaySort, op: "upsert",
            changedAt: "2030-01-01T00:00:00.000Z",
            data: ["key": .string(SettingKeys.todaySort), "value_json": .string("due")]
        )
        #expect(try await mac.store.apply([change]) == 0)
        #expect(await settings(mac).value(for: SettingKeys.todaySort) == nil)
    }

    private struct TrayRow: Equatable {
        var id: String
        var items: [String]
        var order: Int
    }

    private func trayRows(_ device: Mac) async throws -> [TrayRow] {
        let raw = try #require(await settings(device).value(for: SettingKeys.workTrays))
        let list = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        return list.map {
            TrayRow(id: $0["id"] as? String ?? "", items: $0["itemIds"] as? [String] ?? [], order: $0["sortOrder"] as? Int ?? -1)
        }
    }

    private func trays(_ device: Mac) async throws -> [String] {
        let raw = try #require(await settings(device).value(for: SettingKeys.workTrays))
        let list = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        return list.compactMap { $0["name"] as? String }
    }

    private func ruleIds(_ device: Mac) async throws -> [String] {
        let raw = try #require(await settings(device).value(for: SettingKeys.workflowRules))
        let list = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        return list.compactMap { $0["id"] as? String }
    }
}
