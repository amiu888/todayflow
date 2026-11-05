import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// The contacts window: groups, search, import, duplicate review, and task
/// associations.
public struct ContactsView: View {
    @Bindable private var model: ContactsViewModel
    private let onPickImportFile: () -> URL?
    private let onImportFile: (URL) async throws -> [ImportedContact]
    private let onImportFromContacts: () async throws -> [ImportedContact]
    private let requestContactsAccess: () async -> Bool
    private let onOpenTask: (@MainActor (UUIDv7) -> Void)?

    @State private var editorContact: Contact?
    @State private var showingImport = false
    @State private var showingDuplicates = false
    @State private var showingNewGroup = false
    @State private var newGroupName = ""
    @State private var renamingGroup: ContactGroup?
    @State private var groupName = ""

    public init(
        model: ContactsViewModel,
        onPickImportFile: @escaping () -> URL? = { nil },
        onImportFile: @escaping (URL) async throws -> [ImportedContact] = { _ in [] },
        onImportFromContacts: @escaping () async throws -> [ImportedContact] = { [] },
        requestContactsAccess: @escaping () async -> Bool = { false },
        onOpenTask: (@MainActor (UUIDv7) -> Void)? = nil
    ) {
        self.model = model
        self.onPickImportFile = onPickImportFile
        self.onImportFile = onImportFile
        self.onImportFromContacts = onImportFromContacts
        self.requestContactsAccess = requestContactsAccess
        self.onOpenTask = onOpenTask
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            NavigationSplitView {
                sidebar
            } content: {
                contactList
            } detail: {
                detail
            }
        }
        .frame(minWidth: 840, minHeight: 560)
        .sheet(item: $editorContact) { contact in
            ContactEditorView(
                contact: contact,
                groups: model.groups,
                selectedGroupIds: Set(model.contactGroupIds[contact.id] ?? [])
            ) { saved, groupIds in
                Task { await model.save(saved, groupIds: groupIds) }
                editorContact = nil
            }
        }
        .sheet(isPresented: $showingImport) {
            ContactImportView(
                model: model,
                onPickImportFile: onPickImportFile,
                onImportFile: onImportFile,
                onImportFromContacts: onImportFromContacts,
                requestContactsAccess: requestContactsAccess
            )
        }
        .sheet(isPresented: $showingDuplicates) {
            ContactDuplicatesView(model: model)
        }
        .alert("New group", isPresented: $showingNewGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Cancel", role: .cancel) { newGroupName = "" }
            Button("Create") {
                let name = newGroupName
                newGroupName = ""
                Task { await model.addGroup(name: name) }
            }
        }
        .alert(
            "Rename group",
            isPresented: Binding(
                get: { renamingGroup != nil },
                set: { if !$0 { renamingGroup = nil } }
            )
        ) {
            TextField("Group name", text: $groupName)
            Button("Cancel", role: .cancel) { renamingGroup = nil }
            Button("Rename") {
                if let group = renamingGroup {
                    let name = groupName
                    renamingGroup = nil
                    Task { await model.renameGroup(group, to: name) }
                } else {
                    renamingGroup = nil
                }
            }
        }
        .task { await model.load() }
    }

    @MainActor
    private var header: some View {
        HStack(spacing: 10) {
            TextField("Search contacts", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            Spacer()

            Button {
                editorContact = Contact()
            } label: {
                Label("New Contact", systemImage: "person.badge.plus")
            }
            .help("Create a contact")

            Button {
                showingImport = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import from Contacts, Outlook vCard, or CSV")

            Button {
                Task {
                    guard await requestContactsAccess() else { return }
                    if let records = try? await onImportFromContacts() {
                        model.prepareImport(records, source: "macOS Contacts")
                        showingImport = true
                    }
                }
            } label: {
                Label("Sync Contacts", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Sync from macOS Contacts")

            Button {
                model.refreshDuplicates()
                showingDuplicates = true
            } label: {
                Label("Duplicates", systemImage: "person.2.badge.key")
            }
            .help("Review possible duplicate contacts")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @MainActor
    private var sidebar: some View {
        List(selection: $model.selectedGroupID) {
            Label("All Contacts", systemImage: "person.2")
                .tag(UUIDv7?.none)
                .badge(model.contacts.count)

            Button {
                model.refreshDuplicates()
                showingDuplicates = true
            } label: {
                HStack {
                    Label("Duplicates", systemImage: "person.2.badge.key")
                    Spacer()
                    if !model.duplicates.isEmpty {
                        Text("\(model.duplicates.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Section("Groups") {
                ForEach(model.groups) { group in
                    Label {
                        HStack {
                            Text(group.name)
                            Spacer()
                            Text("\(model.contactCount(in: group))")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color(hex: group.colorHex))
                    }
                    .tag(UUIDv7?.some(group.id))
                    .contextMenu {
                        Button("Rename…") {
                            renamingGroup = group
                            groupName = group.name
                        }
                        Button("Delete Group", role: .destructive) {
                            Task { await model.deleteGroup(group) }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                newGroupName = ""
                showingNewGroup = true
            } label: {
                Label("New Group", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    }

    @MainActor
    private var contactList: some View {
        List(selection: $model.selectedContactID) {
            if model.contacts.isEmpty {
                ContentUnavailableView(
                    "No contacts yet",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Create a contact or import your address book.")
                )
            } else if model.filteredContacts.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else {
                ForEach(model.filteredContacts) { contact in
                    ContactRow(contact: contact, groups: model.groups(for: contact))
                        .tag(contact.id)
                }
            }
        }
        .onChange(of: model.selectedContactID) { _, newValue in
            Task { await model.selectContact(newValue) }
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 300)
    }

    @MainActor
    @ViewBuilder
    private var detail: some View {
        if let contact = model.selectedContact {
            ContactDetailPane(
                contact: contact,
                groups: model.groups(for: contact),
                tasks: model.selectedContactTasks,
                onEdit: { editorContact = contact },
                onDelete: {
                    Task { await model.delete(contact) }
                },
                onOpenTask: { onOpenTask?($0) }
            )
        } else {
            ContentUnavailableView(
                "Select a contact",
                systemImage: "person.crop.circle",
                description: Text("Choose a contact to see emails, groups, and associated tasks.")
            )
        }
    }
}

private struct ContactRow: View {
    let contact: Contact
    let groups: [ContactGroup]

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        groups.first.map { Color(hex: $0.colorHex).opacity(0.2) }
                            ?? DesignTokens.Palette.surfaceRaised
                    )
                Text(contact.initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        groups.first.map { Color(hex: $0.colorHex) }
                            ?? DesignTokens.Palette.textSecondary
                    )
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(contact.company.isEmpty ? contact.emails.first ?? contact.phones.first ?? "" : contact.company)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !groups.isEmpty {
                Text(groups.map(\.name).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ContactDetailPane: View {
    let contact: Contact
    let groups: [ContactGroup]
    let tasks: [WorkItem]
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onOpenTask: (UUIDv7) -> Void

    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(DesignTokens.Palette.accent.opacity(0.16))
                        Text(contact.initials)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DesignTokens.Palette.accent)
                    }
                    .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(contact.displayName)
                            .font(.title2.weight(.semibold))
                        if !contact.jobTitle.isEmpty || !contact.company.isEmpty {
                            Text([contact.jobTitle, contact.company]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("Edit", action: onEdit)
                    Button("Delete", role: .destructive) {
                        confirmingDelete = true
                    }
                }

                if !groups.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionTitle("Groups")
                        HStack(spacing: 6) {
                            ForEach(groups) { group in
                                Text(group.name)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(Color(hex: group.colorHex).opacity(0.16))
                                    )
                                    .foregroundStyle(Color(hex: group.colorHex))
                            }
                        }
                    }
                }

                if !contact.emails.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionTitle("Email")
                        ForEach(contact.emails, id: \.self) { email in
                            if let url = URL(
                                string: "mailto:\(email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email)"
                            ) {
                                Link(email, destination: url)
                                    .font(.callout)
                            } else {
                                Text(email).font(.callout)
                            }
                        }
                    }
                }

                if !contact.phones.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionTitle("Phone")
                        ForEach(contact.phones, id: \.self) { phone in
                            Text(phone).font(.callout)
                        }
                    }
                }

                if !contact.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionTitle("Notes")
                        Text(contact.notes)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if !tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionTitle("Tasks")
                        ForEach(tasks) { task in
                            Button {
                                onOpenTask(task.id)
                            } label: {
                                HStack {
                                    Image(systemName: "checklist")
                                    Text(task.title).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Delete contact?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the contact and its group and task links.")
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(DesignTokens.Palette.textSecondary)
    }
}

private struct ContactEditorView: View {
    let contact: Contact
    let groups: [ContactGroup]
    let selectedGroupIds: Set<UUIDv7>
    let onSave: (Contact, Set<UUIDv7>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Contact
    @State private var emailText: String
    @State private var phoneText: String
    @State private var groupIds: Set<UUIDv7>

    init(
        contact: Contact,
        groups: [ContactGroup],
        selectedGroupIds: Set<UUIDv7>,
        onSave: @escaping (Contact, Set<UUIDv7>) -> Void
    ) {
        self.contact = contact
        self.groups = groups
        self.selectedGroupIds = selectedGroupIds
        self.onSave = onSave
        _draft = State(initialValue: contact)
        _emailText = State(initialValue: contact.emails.joined(separator: "\n"))
        _phoneText = State(initialValue: contact.phones.joined(separator: "\n"))
        _groupIds = State(initialValue: selectedGroupIds)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(contact.displayName == "Unnamed contact" ? "New Contact" : "Edit Contact")
                    .font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()

            Form {
                Section("Name") {
                    TextField("First name", text: $draft.firstName)
                        .accessibilityIdentifier("contact-first-name")
                    TextField("Last name", text: $draft.lastName)
                        .accessibilityIdentifier("contact-last-name")
                    TextField("Company", text: $draft.company)
                        .accessibilityIdentifier("contact-company")
                    TextField("Job title", text: $draft.jobTitle)
                        .accessibilityIdentifier("contact-job-title")
                }
                Section("Email") {
                    TextEditor(text: $emailText)
                        .frame(minHeight: 52)
                        .accessibilityIdentifier("contact-emails")
                    Text("One address per line").font(.caption).foregroundStyle(.secondary)
                }
                Section("Phone") {
                    TextEditor(text: $phoneText)
                        .frame(minHeight: 46)
                        .accessibilityIdentifier("contact-phones")
                    Text("One number per line").font(.caption).foregroundStyle(.secondary)
                }
                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 50)
                        .accessibilityIdentifier("contact-notes")
                }
                if !groups.isEmpty {
                    Section("Groups") {
                        ForEach(groups) { group in
                            Toggle(group.name, isOn: Binding(
                                get: { groupIds.contains(group.id) },
                                set: { isOn in
                                    if isOn { groupIds.insert(group.id) }
                                    else { groupIds.remove(group.id) }
                                }
                            ))
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    var saved = draft
                    saved.emails = lines(emailText)
                    saved.phones = lines(phoneText)
                    onSave(saved, groupIds)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 560)
    }

    private func lines(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "\n,;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct ContactImportView: View {
    @Bindable var model: ContactsViewModel
    let onPickImportFile: () -> URL?
    let onImportFile: (URL) async throws -> [ImportedContact]
    let onImportFromContacts: () async throws -> [ImportedContact]
    let requestContactsAccess: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Import Contacts").font(.title3.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }
            }

            HStack(spacing: 10) {
                Button {
                    guard let url = onPickImportFile() else { return }
                    loadFile(url)
                } label: {
                    Label("Choose vCard / CSV…", systemImage: "doc.badge.plus")
                }
                Button {
                    loadContacts()
                } label: {
                    Label("Import from Contacts", systemImage: "person.crop.circle.badge.checkmark")
                }
                if isLoading { ProgressView().controlSize(.small) }
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Divider()

            if !model.pendingImportRecords.isEmpty {
                Text("Source: \(model.importSourceLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Filter by name, email, company, or group", text: $model.importFilter.query)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.importFilter.query) { _, _ in model.recomputeImportPlan() }

                HStack {
                    Toggle("Require email", isOn: $model.importFilter.requireEmail)
                    Toggle("Require phone", isOn: $model.importFilter.requirePhone)
                }
                .onChange(of: model.importFilter.requireEmail) { _, _ in model.recomputeImportPlan() }
                .onChange(of: model.importFilter.requirePhone) { _, _ in model.recomputeImportPlan() }

                if let plan = model.importPlan {
                    Text("\(plan.importedCount) new · \(plan.mergedCount) merged · \(plan.skippedCount) filtered out")
                        .font(.callout)
                    Text("Matching emails and phone numbers are merged automatically; existing rows are updated.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                HStack {
                    Spacer()
                    Button("Cancel") {
                        model.clearImport()
                        dismiss()
                    }
                    Button("Import \(model.importPlan?.contacts.count ?? 0) Contacts") {
                        Task {
                            await model.applyImport()
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.importPlan?.contacts.isEmpty ?? true)
                }
            } else {
                Text("Outlook: File → Open & Export → Import/Export → Export to a file → Comma Separated Values or vCard, then choose that file here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Apple Contacts: use Import from Contacts. Only contacts you approve are read; they stay local.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }

    private func loadFile(_ url: URL) {
        isLoading = true
        error = nil
        Task {
            defer { isLoading = false }
            do {
                let records = try await onImportFile(url)
                model.prepareImport(records, source: url.lastPathComponent)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func loadContacts() {
        isLoading = true
        error = nil
        Task {
            defer { isLoading = false }
            guard await requestContactsAccess() else {
                self.error = "Contacts access was denied. Enable it in System Settings → Privacy & Security → Contacts."
                return
            }
            do {
                let records = try await onImportFromContacts()
                model.prepareImport(records, source: "macOS Contacts")
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct ContactDuplicatesView: View {
    @Bindable var model: ContactsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Duplicate Contacts").font(.title3.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }
            }
            if model.duplicates.isEmpty {
                ContentUnavailableView(
                    "No duplicates",
                    systemImage: "checkmark.seal",
                    description: Text("Contacts that share an email or phone number appear here.")
                )
            } else {
                HStack {
                    Text("\(model.duplicates.count) possible duplicate group(s)")
                        .font(.callout)
                    Spacer()
                    Button("Auto-merge all") {
                        Task { await model.autoMergeDuplicates() }
                    }
                }
                List {
                    ForEach(Array(model.duplicates.enumerated()), id: \.offset) { _, group in
                        Section {
                            ForEach(group) { contact in
                                HStack {
                                    Text(contact.displayName)
                                    Spacer()
                                    Text(contact.emails.first ?? contact.phones.first ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } header: {
                            Menu("Merge into…") {
                                ForEach(group) { primary in
                                    Button(primary.displayName) {
                                        Task { await model.merge(group, into: primary) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
    }
}
