#if os(iOS)
import QuickLook
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures

/// A task's whole story (docs/ios/DESIGN.md §3.2), on the Mac's `DetailViewModel`.
struct PhoneDetailView: View {
    @State private var model: DetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var noteText = ""
    @State private var newAction = ""
    @State private var newTag = ""
    @State private var showingTag = false
    @State private var showingReminder = false
    @State private var confirmDelete = false
    @State private var previewURL: URL?
    @State private var suggestions: [PickedTodo] = []
    @State private var showingSuggestions = false
    @State private var isSuggesting = false
    @FocusState private var noteFocused: Bool
    private let attachmentsDirectory: URL

    init(id: UUIDv7, environment: PhoneEnvironment) {
        attachmentsDirectory = environment.materializer.attachmentsDirectory
        _model = State(initialValue: DetailViewModel(
            itemId: id,
            repository: environment.workItems,
            linkRepository: environment.links,
            attachmentRepository: environment.attachments,
            contactRepository: environment.contacts,
            activityRepository: environment.activities,
            reminderRepository: environment.reminders,
            actionRepository: environment.actions,
            calendar: environment.workCalendar
        ))
    }

    var body: some View {
        List {
            if let item = model.item {
                header(item)
                if !model.edit.summary.isEmpty {
                    Section("Summary") { Text(model.edit.summary).font(.callout) }
                }
                notesSection
                checklistSection
                peopleSection
                relatedSection
                filesSection
                historySection
            } else if !model.isLoading {
                ContentUnavailableView("Task not found", systemImage: "questionmark.circle")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(model.item?.kind == .project ? "Project" : "Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { moreMenu } }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) { noteBar }
        .task { await model.load() }
        .onDisappear { Task { _ = await model.commit() } }
        .onChange(of: model.isDeleted) { _, deleted in if deleted { dismiss() } }
        .quickLookPreview($previewURL)
        .alert("Add tag", isPresented: $showingTag) {
            TextField("Tag", text: $newTag)
            Button("Cancel", role: .cancel) { newTag = "" }
            Button("Add") {
                let tag = newTag
                newTag = ""
                Task { await model.addTag(tag) }
            }
        }
        .sheet(isPresented: $showingReminder) { reminderSheet }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await model.delete() } }
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { model.lastError != nil }, set: { if !$0 { model.dismissError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    // MARK: Header

    @ViewBuilder
    private func header(_ item: WorkItem) -> some View {
        Section {
            TextField("Title", text: $model.edit.title, axis: .vertical)
                .font(.title2.weight(.semibold))
                .submitLabel(.done)
                .onSubmit { Task { _ = await model.commit() } }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(Priority.allCases, id: \.self) { priority in
                            Button(priority.label) { Task { await model.setPriority(priority) } }
                        }
                    } label: {
                        pill(model.priority.label, color: PriorityColor.color(for: model.priority, in: scheme))
                    }
                    Menu {
                        ForEach([Status.todo, .inProgress, .blocked, .done, .cancelled], id: \.self) { status in
                            Button(status.label) { Task { await model.setStatus(status) } }
                        }
                    } label: {
                        pill(model.displayStatus.label, color: .accentColor)
                    }
                    if let project = model.parent, project.kind == .project {
                        pill(project.title, color: .purple)
                    }
                }
            }
            .listRowSeparator(.hidden)

            DatePicker("Start", selection: $model.edit.startAt)
                .onChange(of: model.edit.startAt) { Task { _ = await model.commit() } }
            DatePicker("Due", selection: $model.edit.endAt, in: model.edit.startAt...)
                .onChange(of: model.edit.endAt) { Task { _ = await model.commit() } }

            tagsRow(item)
        }
    }

    private func tagsRow(_ item: WorkItem) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(item.tags, id: \.self) { tag in
                    Menu {
                        Button("Remove #\(tag)", systemImage: "xmark", role: .destructive) {
                            Task { await model.removeTag(tag) }
                        }
                    } label: {
                        Text("#\(tag)")
                            .font(.subheadline)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12), in: .capsule)
                    }
                }
                Button("Add tag", systemImage: "number") { showingTag = true }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.16), in: .capsule)
            .foregroundStyle(color)
    }

    // MARK: Sections

    @ViewBuilder
    private var notesSection: some View {
        Section("Notes") {
            if model.notes.isEmpty {
                Text("No notes yet").foregroundStyle(.secondary)
            }
            ForEach(model.notes.reversed()) { note in
                VStack(alignment: .leading, spacing: 4) {
                    if !note.isUndated {
                        Text(note.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(note.text)
                        .textSelection(.enabled)
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await model.deleteNote(note.id) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var checklistSection: some View {
        if !model.actions.isEmpty || model.item?.kind == .task {
            Section {
                ForEach(model.actions) { action in
                    Button {
                        Task { await model.toggleAction(action) }
                    } label: {
                        Label {
                            Text(action.text)
                                .strikethrough(action.isDone)
                                .foregroundStyle(action.isDone ? .secondary : .primary)
                        } icon: {
                            Image(systemName: action.isDone ? "checkmark.square.fill" : "square")
                        }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Task { await model.deleteAction(action) }
                        }
                    }
                }
                TextField("Add an item", text: $newAction)
                    .submitLabel(.done)
                    .onSubmit {
                        let text = newAction
                        newAction = ""
                        Task { await model.addAction(text) }
                    }
                Button {
                    Task { await suggestTodos() }
                } label: {
                    HStack {
                        Label(PhoneSmartCapture.hasAppleIntelligence ? "Find To-dos with Apple Intelligence" : "Find To-dos",
                              systemImage: "sparkles")
                        if isSuggesting { Spacer(); ProgressView() }
                    }
                }
                .disabled(isSuggesting)
            } header: {
                HStack {
                    Text("Checklist")
                    Spacer()
                    if !model.actions.isEmpty {
                        Text("\(model.actions.filter(\.isDone).count) of \(model.actions.count)")
                            .monospacedDigit()
                    }
                }
            }
            .sheet(isPresented: $showingSuggestions) { suggestionSheet }
        }
    }

    /// Reads the task's description, summary and screenshots for to-dos.
    private func suggestTodos() async {
        guard let item = model.item else { return }
        isSuggesting = true
        defer { isSuggesting = false }
        let text = await ChecklistSuggestions.sourceText(
            for: item, attachments: model.attachments, attachmentsDirectory: attachmentsDirectory
        )
        let found = await ChecklistSuggestions.suggest(
            title: item.title, text: text,
            existing: model.actions.map(\.text),
            using: PhoneSmartCapture.checklistSuggester
        )
        suggestions = found.map { PickedTodo(text: $0) }
        showingSuggestions = true
    }

    private var suggestionSheet: some View {
        NavigationStack {
            Group {
                if suggestions.isEmpty {
                    ContentUnavailableView(
                        "No to-dos found",
                        systemImage: "checklist",
                        description: Text("Nothing in this task's notes, summary or screenshots asks for something to be done.")
                    )
                } else {
                    List {
                        Section {
                            ForEach($suggestions) { $todo in
                                Toggle(isOn: $todo.picked) { Text(todo.text) }
                                    .toggleStyle(PhoneCheckToggleStyle())
                            }
                        } footer: {
                            Text(PhoneSmartCapture.hasAppleIntelligence
                                 ? "Found by Apple Intelligence on this iPhone. Tick the ones to add."
                                 : "Found in the task's text. Tick the ones to add.")
                        }
                    }
                }
            }
            .navigationTitle("To-dos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingSuggestions = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let picked = suggestions.filter(\.picked).map(\.text)
                        showingSuggestions = false
                        Task { await model.addActions(picked) }
                    }
                    .disabled(!suggestions.contains(where: \.picked))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var peopleSection: some View {
        if !model.contacts.isEmpty {
            Section("People") {
                ForEach(model.contacts) { contact in
                    Menu {
                        ForEach(contact.phones, id: \.self) { phone in
                            if let url = URL(string: "tel:" + phone.filter { !$0.isWhitespace }) {
                                Link(destination: url) { Label("Call \(phone)", systemImage: "phone") }
                            }
                        }
                        ForEach(contact.emails, id: \.self) { email in
                            if let url = URL(string: "mailto:" + email) {
                                Link(destination: url) { Label("Mail \(email)", systemImage: "envelope") }
                            }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(contact.displayName).foregroundStyle(.primary)
                            if !contact.company.isEmpty {
                                Text(contact.company).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var relatedSection: some View {
        let groups: [(String, [WorkItem])] = [
            ("Blocked by", model.blockers),
            ("Blocks", model.blockings),
            ("Related", model.related),
            ("Subtasks", model.children),
        ].filter { !$0.1.isEmpty }
        if !groups.isEmpty {
            Section("Related") {
                ForEach(groups, id: \.0) { group in
                    ForEach(group.1) { other in
                        NavigationLink(value: other.id) {
                            VStack(alignment: .leading) {
                                Text(group.0).font(.caption).foregroundStyle(.secondary)
                                Text(other.title)
                                    .strikethrough(other.status.isComplete)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var filesSection: some View {
        if !model.attachments.isEmpty {
            Section("Files") {
                ForEach(model.attachments) { attachment in
                    Button {
                        open(attachment)
                    } label: {
                        HStack {
                            Image(systemName: icon(for: attachment.kind))
                            VStack(alignment: .leading) {
                                Text(attachment.displayName).lineLimit(1)
                                if let note = attachment.note, !note.isEmpty {
                                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            if localFile(attachment) == nil, webURL(attachment) == nil {
                                Image(systemName: "icloud.slash").foregroundStyle(.secondary)
                                    .accessibilityLabel("Not on this iPhone")
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !model.activity.isEmpty {
            Section {
                DisclosureGroup("History · \(model.activity.count)") {
                    ForEach(model.activity.sorted { $0.occurredAt > $1.occurredAt }) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.summary).font(.callout)
                            Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Bars and menus

    private var noteBar: some View {
        HStack(spacing: 8) {
            TextField("Add a note…", text: $noteText, axis: .vertical)
                .lineLimit(1...4)
                .focused($noteFocused)
                .padding(.horizontal, 12).padding(.vertical, 8)
            Button("Send", systemImage: "arrow.up.circle.fill") {
                let text = noteText
                noteText = ""
                noteFocused = false
                Task { await model.addNote(text) }
            }
            .labelStyle(.iconOnly)
            .font(.title2)
            .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.trailing, 8)
        .glassEffect(in: .rect(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            Button("Move to Tomorrow", systemImage: "arrow.right.circle") {
                Task { await model.moveToTomorrow() }
            }
            Menu("Due", systemImage: "calendar") {
                ForEach(DetailViewModel.DateShortcut.allCases) { shortcut in
                    Button(shortcut.label) { Task { await model.applyDateShortcut(shortcut) } }
                }
            }
            Button(model.reminder == nil ? "Remind Me…" : "Change Reminder…", systemImage: "bell") {
                showingReminder = true
            }
            Menu("Repeat", systemImage: "repeat") {
                Button("Never") { Task { await model.setRecurrence(nil) } }
                ForEach(Recurrence.allCases, id: \.self) { option in
                    Button(option.label) { Task { await model.setRecurrence(option) } }
                }
            }
            Menu("Project", systemImage: "folder") {
                Button("None") { Task { await model.setProject(nil) } }
                ForEach(model.availableProjects) { project in
                    Button(project.title) { Task { await model.setProject(project.id) } }
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
        }
    }

    private var reminderSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Remind me", selection: $model.reminderDate)
                    .datePickerStyle(.graphical)
                if model.reminder != nil {
                    Button("Remove Reminder", role: .destructive) {
                        Task { await model.clearReminder() }
                        showingReminder = false
                    }
                }
            }
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingReminder = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        Task { await model.setReminder(at: model.reminderDate) }
                        showingReminder = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Attachments

    /// The attachment's file on this iPhone. iOS moves the app's folder when
    /// the app is updated, so a stored path that no longer exists is looked
    /// up by name in the current Attachments folder.
    private func localFile(_ attachment: Attachment) -> URL? {
        let manager = FileManager.default
        for path in [attachment.localCopyPath, attachment.reference].compactMap({ $0 }) where path.hasPrefix("/") {
            if manager.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
            let moved = attachmentsDirectory.appendingPathComponent((path as NSString).lastPathComponent)
            if manager.fileExists(atPath: moved.path) { return moved }
        }
        return nil
    }

    private func webURL(_ attachment: Attachment) -> URL? {
        guard let reference = attachment.reference, let url = URL(string: reference),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    private func open(_ attachment: Attachment) {
        if let file = localFile(attachment) {
            previewURL = file
        } else if let url = webURL(attachment) {
            UIApplication.shared.open(url)
        }
    }

    private func icon(for kind: Attachment.Kind) -> String {
        switch kind {
        case .url: "link"
        case .image: "photo"
        case .email: "envelope"
        case .text: "text.alignleft"
        default: "doc"
        }
    }
}

#endif
