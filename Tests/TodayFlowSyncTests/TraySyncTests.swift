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

    @Test func pairingANewDevice_keepsTheAccountsTrays() async throws {
        let server = FakeServer()
        let mac = try Mac("Mac", server: server)
        try await settings(mac).set(#"[{"name":"Client A"}]"#, for: SettingKeys.workTrays)
        try await mac.sync()

        // A new device made its own default tray before pairing, later in time.
        let phone = try Mac("iPhone", server: server)
        try await settings(phone).set(#"[{"name":"Working tray"}]"#, for: SettingKeys.workTrays)
        try await phone.store.markAllPending()
        try await phone.sync()
        try await mac.sync()

        #expect(await settings(phone).value(for: SettingKeys.workTrays) == #"[{"name":"Client A"}]"#)
        #expect(await settings(mac).value(for: SettingKeys.workTrays) == #"[{"name":"Client A"}]"#)
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
}
