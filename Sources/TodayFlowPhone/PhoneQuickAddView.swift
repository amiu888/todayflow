#if os(iOS)
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures
import TodayFlowRecognition
import UniformTypeIdentifiers

/// "New task" (docs/ios/DESIGN.md §3.3): one line of natural language, with
/// chips showing what was understood. Saving goes through the Mac's
/// `CaptureViewModel`, so dates and the default schedule follow the same rules.
struct PhoneQuickAddView: View {
    @State private var model: CaptureViewModel
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    /// What was pasted: screenshots, links, text.
    @State private var pasted: [DroppedObject] = []
    @State private var isReading = false
    /// To-dos found in what was pasted; the ticked ones become the checklist.
    @State private var todos: [PickedTodo] = []

    private let calendar: WorkCalendar
    private let environment: PhoneEnvironment

    init(environment: PhoneEnvironment, initialDay: Date? = nil) {
        self.environment = environment
        calendar = environment.workCalendar
        let model = CaptureViewModel(
            repository: environment.workItems,
            attachmentRepository: environment.attachments,
            contactRepository: environment.contacts,
            materializer: environment.materializer,
            calendar: environment.workCalendar
        )
        if let initialDay, !Calendar.current.isDateInToday(initialDay) {
            // Planning another day: start at the beginning of that day's work hours.
            let start = environment.workCalendar.startOfBusiness(for: initialDay)
            model.draft.startAt = start
            model.draft.endAt = TaskSchedule.dueAfterStart(
                start: start, due: environment.workCalendar.endOfBusiness(for: initialDay)
            )
        }
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Call Maria tomorrow 3pm #Q4", text: $text, axis: .vertical)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .onChange(of: text) { model.draft.title = PhoneQuickAdd.title(from: text) }
                    understood
                }
                pasteSection
                if !todos.isEmpty { todoSection }
                Section {
                    Picker("Priority", selection: $model.draft.priority) {
                        ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Project", selection: $model.draft.parentId) {
                        Text("None").tag(UUIDv7?.none)
                        ForEach(model.parents) { Text($0.title).tag(Optional($0.id)) }
                    }
                    DatePicker("Due", selection: $model.draft.endAt)
                }
                if let error = model.lastError {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save)
                        .disabled(PhoneQuickAdd.title(from: text).isEmpty || model.isSaving || isReading)
                }
            }
            .task {
                await model.loadParents()
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Paste

    private var pasteSection: some View {
        Section {
            ForEach(Array(pasted.enumerated()), id: \.offset) { index, object in
                HStack(spacing: 10) {
                    PastedPreview(object: object)
                    Spacer()
                    Button("Remove", systemImage: "xmark.circle.fill") {
                        pasted.remove(at: index)
                        Task { await understandPaste() }
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                PasteButton(supportedContentTypes: [.image, .url, .plainText]) { providers in
                    // Item providers aren't Sendable; they're only read on the main actor.
                    let box = ProvidersBox(providers: providers)
                    Task { @MainActor in await paste(box.providers) }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                if isReading {
                    Spacer()
                    ProgressView()
                    Text(PhoneSmartCapture.hasAppleIntelligence ? "Reading with Apple Intelligence…" : "Reading…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(pasted.isEmpty
                 ? "Copy a screenshot, a link or a message, then paste it here. Screenshots are read on this iPhone."
                 : "Read on this iPhone; nothing is sent anywhere. Edit the title if it isn't right.")
        }
    }

    private var todoSection: some View {
        Section {
            ForEach($todos) { $todo in
                Toggle(isOn: $todo.picked) { Text(todo.text) }
                    .toggleStyle(PhoneCheckToggleStyle())
            }
        } header: {
            Text("To-dos found")
        } footer: {
            Text("The ticked ones become the task's checklist.")
        }
    }

    private func paste(_ providers: [NSItemProvider]) async {
        for provider in providers {
            if let object = await PhonePasteLoader.object(from: provider) { pasted.append(object) }
        }
        await understandPaste()
    }

    /// Reads what was pasted and fills the title, description and to-dos,
    /// keeping a title the person already typed and the choices they made.
    private func understandPaste() async {
        guard !pasted.isEmpty else {
            todos = []
            return
        }
        isReading = true
        defer { isReading = false }
        let typed = PhoneQuickAdd.title(from: text)
        let priority = model.draft.priority
        let parent = model.draft.parentId
        let reading = await PhoneSmartCapture.read(pasted, pipeline: environment.pipeline)
        await PhoneSmartCapture.prepare(model, dropped: pasted, reading: reading)
        if priority != .default { model.draft.priority = priority }
        model.draft.parentId = parent
        if typed.isEmpty {
            text = model.draft.title
        } else {
            model.draft.title = typed
        }
        let found = await PhoneSmartCapture.todos(title: model.draft.title, reading: reading)
        todos = found.map { PickedTodo(text: $0) }
    }

    /// Chips for the date and tags read from the text.
    private var understood: some View {
        HStack(spacing: 6) {
            chip(model.draft.endAt.formatted(.dateTime.weekday(.abbreviated).day().hour().minute()), systemImage: "calendar")
            ForEach(PhoneQuickAdd.tags(in: text), id: \.self) { tag in
                chip("#\(tag)", systemImage: nil)
            }
        }
        .listRowSeparator(.hidden)
    }

    private func chip(_ label: String, systemImage: String?) -> some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(label)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.15), in: .capsule)
        .foregroundStyle(Color.accentColor)
    }

    private func save() {
        let title = PhoneQuickAdd.title(from: text)
        guard !title.isEmpty else { return }
        model.draft.tags = PhoneQuickAdd.tags(in: text)
        let checklist = todos.filter(\.picked).map(\.text)
        Task {
            await model.save()
            if model.lastError == nil {
                if let item = model.savedItem, !checklist.isEmpty {
                    await PhoneSmartCapture.addChecklist(checklist, to: item.id, repository: environment.actions)
                }
                NotificationCenter.default.post(name: TodayFlowEvents.itemsChanged, object: nil)
                dismiss()
            }
        }
    }
}

private struct ProvidersBox: @unchecked Sendable { let providers: [NSItemProvider] }

struct PickedTodo: Identifiable {
    let id = UUID()
    var text: String
    var picked = true
}

/// A checkbox row, like the task's checklist.
struct PhoneCheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? Color.accentColor : .secondary)
                configuration.label.foregroundStyle(.primary)
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

/// One pasted thing: a screenshot's thumbnail, a link, or the text.
private struct PastedPreview: View {
    let object: DroppedObject

    var body: some View {
        if let data = object.imageData, let image = UIImage(data: data) {
            HStack(spacing: 10) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 8))
                Text("Screenshot").font(.subheadline)
            }
        } else if let url = object.url {
            Label(url.host() ?? url.absoluteString, systemImage: "link").lineLimit(1)
        } else if let text = object.text {
            Label(text, systemImage: "text.quote").lineLimit(2)
        }
    }
}

/// Turns what the system Paste button hands over into dropped objects.
@MainActor
enum PhonePasteLoader {
    static func object(from provider: NSItemProvider) async -> DroppedObject? {
        if let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }),
           let data = await data(provider, type) {
            return DroppedObject(imageData: data, sourceApp: "Clipboard", uti: type)
        }
        if provider.canLoadObject(ofClass: URL.self), let url = await url(provider), url.scheme != nil {
            return DroppedObject(url: url, sourceApp: "Clipboard")
        }
        if let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .plainText) }),
           let data = await data(provider, type),
           let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            if let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme) {
                return DroppedObject(url: url, sourceApp: "Clipboard")
            }
            return DroppedObject(text: text, sourceApp: "Clipboard")
        }
        return nil
    }

    private static func url(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    private static func data(_ provider: NSItemProvider, _ type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, _ in continuation.resume(returning: data) }
        }
    }
}

/// Splits the quick-add line into a title and #tags. Dates stay in the title,
/// as on the Mac, so the parser and the person read the same words.
enum PhoneQuickAdd {
    static func tags(in text: String) -> [String] {
        var seen = Set<String>()
        return words(text).compactMap { word -> String? in
            guard word.hasPrefix("#"), word.count > 1 else { return nil }
            let tag = String(word.dropFirst()).trimmingCharacters(in: .punctuationCharacters)
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { return nil }
            return tag
        }
    }

    static func title(from text: String) -> String {
        words(text)
            .filter { !($0.hasPrefix("#") && $0.count > 1) }
            .joined(separator: " ")
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
#endif
