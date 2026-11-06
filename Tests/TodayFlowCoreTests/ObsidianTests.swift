import Foundation
import Testing
@testable import TodayFlowCore

@Suite("Obsidian note bridge")
struct ObsidianTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var now: Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 9))!
    }

    @Test func rendersTasksProjectsTagsAndDatesInsideTheManagedBlock() throws {
        let task = WorkItem(
            title: "Review Q4 roadmap",
            priority: .high,
            startAt: now,
            endAt: utc.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 17))!,
            displayOrder: "a0",
            tags: ["launch", "Q4"]
        )
        let project = WorkItem(
            kind: .project,
            title: "Launch Q4",
            startAt: now,
            endAt: now.addingTimeInterval(86_400),
            displayOrder: "p0",
            tags: ["launch"]
        )
        let note = ObsidianNote.render(
            items: [task],
            projects: [project],
            existing: "My own intro\n",
            now: now,
            calendar: WorkCalendar(calendar: utc)
        )

        #expect(note.hasPrefix("My own intro"))
        #expect(note.contains(ObsidianNote.startMarker))
        #expect(note.contains(ObsidianNote.endMarker))
        #expect(note.contains("Review Q4 roadmap"))
        #expect(note.contains("<!-- todayflow:\(task.id) -->"))
        #expect(note.contains("#launch #Q4"))
        #expect(note.contains("📅 2026-11-06"))
        #expect(note.contains("⏰ 17:00"))
        #expect(note.contains("**Launch Q4**"))

        let parsed = try #require(ObsidianNote.parse(note, calendar: utc).first)
        #expect(parsed.id == task.id)
        #expect(parsed.title == "Review Q4 roadmap")
        #expect(parsed.tags == ["launch", "Q4"])
        #expect(parsed.isDone == false)
        #expect(parsed.dueAt == task.endAt)
    }

    @Test func parsesCheckboxChangesAndNewLines() throws {
        let id = UUIDv7(timestampMilliseconds: 1_700_000_000_000)
        let note = """
        <!-- todayflow:start -->
        ## Today
        - [x] Review Q4 roadmap <!-- todayflow:\(id) --> #launch #Q4 📅 2026-11-06 ⏰ 17:00
        - [ ] New from Obsidian #ops 📅 2026-11-07
        - **Launch Q4** <!-- todayflow:\(id) --> #launch
        <!-- todayflow:end -->
        """

        let lines = ObsidianNote.parse(note, calendar: utc)
        #expect(lines.count == 3)
        #expect(lines[0].id == id)
        #expect(lines[0].isDone)
        #expect(lines[0].tags == ["launch", "Q4"])
        #expect(lines[1].id == nil)
        #expect(lines[1].title == "New from Obsidian")
        #expect(lines[1].tags == ["ops"])
        #expect(lines[1].dueAt != nil)
        #expect(lines[2].isProject)
    }

    @Test func preservesTextOutsideTheMarkersOnRewrite() {
        let existing = """
        # My vault note

        Keep this paragraph.

        <!-- todayflow:start -->
        old content
        <!-- todayflow:end -->

        Keep this footer.
        """
        let note = ObsidianNote.render(
            items: [],
            projects: [],
            existing: existing,
            now: now,
            calendar: WorkCalendar(calendar: utc)
        )
        #expect(note.contains("Keep this paragraph."))
        #expect(note.contains("Keep this footer."))
        #expect(!note.contains("old content"))
        #expect(note.contains(ObsidianNote.startMarker))
    }

    @Test func buildsPercentEncodedDeepLinks() throws {
        let url = try #require(
            ObsidianDeepLink.open(vaultName: "My Vault", notePath: "TodayFlow/Tasks.md")
        )
        #expect(url.scheme == "obsidian")
        #expect(url.host == "open")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["vault"] == "My Vault")
        #expect(items["file"] == "TodayFlow/Tasks")
    }

    @Test func itemNoteCarriesFrontmatterAndDescription() {
        let task = WorkItem(
            title: "Review Q4 roadmap",
            descriptionMd: "Check the pricing section.",
            priority: .high,
            startAt: now,
            endAt: utc.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 17))!,
            displayOrder: "a0",
            tags: ["launch", "Q4"]
        )
        let note = ObsidianItemNote.render(
            item: task,
            projectTitle: "Launch Q4",
            now: now
        )
        #expect(note.contains("todayflow_id: \(task.id)"))
        #expect(note.contains("kind: task"))
        #expect(note.contains("priority: 2"))
        #expect(note.contains("tags:"))
        #expect(note.contains("  - launch"))
        #expect(note.contains("project: \"Launch Q4\""))
        #expect(note.contains("# Review Q4 roadmap"))
        #expect(note.contains("Check the pricing section."))
    }

    @Test func parsesObsidianVaultRegistry() {
        let json = """
        {"vaults":{
          "root":{"path":"/Users/me/Vaults"},
          "a":{"path":"/Users/me/Vaults/NBCBrain"},
          "b":{"path":"/Users/me/Vaults/HermesBrain"},
          "c":{"path":"/Users/me/Vaults/NBCBrain"}
        }}
        """
        let vaults = ObsidianVaultRegistry.parse(json)
        #expect(vaults.map(\.name) == ["HermesBrain", "NBCBrain"])
        #expect(vaults.map(\.path) == [
            "/Users/me/Vaults/HermesBrain",
            "/Users/me/Vaults/NBCBrain",
        ])
    }

    @Test func buildsRemoteURLsWithEncodedPaths() throws {
        let settings = ObsidianSettings(
            enabled: true,
            mode: .remote,
            remoteHost: "10.0.2.50",
            remotePort: 27123,
            remoteUseHTTPS: false
        )
        let client = try #require(
            ObsidianRemoteClient(settings: settings, apiKey: "test-key")
        )
        #expect(
            client.url(for: "/vault/Conversations/Daily/TodayFlow.md")?.absoluteString
                == "http://10.0.2.50:27123/vault/Conversations/Daily/TodayFlow.md"
        )
        #expect(
            client.url(for: "/vault/My Note.md")?.absoluteString
                == "http://10.0.2.50:27123/vault/My%20Note.md"
        )
    }

    @Test func olderLocalSettingsDecodeWithLocalMode() throws {
        let json = """
        {"enabled":true,"vaultPath":"/Users/me/Vault","vaultName":"Vault","notePath":"TodayFlow/Tasks.md"}
        """
        let decoded = try JSONDecoder().decode(
            ObsidianSettings.self,
            from: Data(json.utf8)
        )
        #expect(decoded.mode == .local)
        #expect(decoded.vaultPath == "/Users/me/Vault")
        #expect(decoded.isConfigured)
    }

    @Test func remoteSettingsRoundTripAndBaseURL() throws {
        let settings = ObsidianSettings(
            enabled: true,
            mode: .remote,
            remoteHost: "10.0.2.50",
            remotePort: 27123,
            remoteUseHTTPS: false,
            remoteDisplayName: "NBCBrain Mac",
            notePath: "Conversations/Daily/TodayFlow.md"
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ObsidianSettings.self, from: data)
        #expect(decoded == settings)
        #expect(decoded.remoteBaseURL?.absoluteString == "http://10.0.2.50:27123")
        #expect(decoded.isConfigured)
    }

    @Test func enumeratesTheUsableHostsInASlash24() {
        let hosts = ObsidianLANDiscovery.hosts(
            inIPv4: "192.168.1.10",
            netmask: "255.255.255.0"
        )
        #expect(hosts.count == 254)
        #expect(hosts.first == "192.168.1.1")
        #expect(hosts.last == "192.168.1.254")
    }

    @Test func recognizesTheLocalRestAPIStatusShape() {
        let status = Data(#"{"status":"OK","authenticated":false}"#.utf8)
        let unrelated = Data(#"{"hello":"world"}"#.utf8)
        #expect(ObsidianLANDiscovery.isObsidianStatus(status))
        #expect(!ObsidianLANDiscovery.isObsidianStatus(unrelated))
    }

    @Test func normalizesVaultRelativeNotePaths() {
        let settings = ObsidianSettings(
            enabled: true,
            vaultPath: "/Users/me/Vault",
            vaultName: "Vault",
            notePath: "/TodayFlow/Tasks"
        )
        #expect(settings.normalizedNotePath == "TodayFlow/Tasks.md")
        #expect(settings.isConfigured)
        #expect(settings.resolvedVaultName == "Vault")
    }
}
