#if os(iOS)
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures

/// "New task" (docs/ios/DESIGN.md §3.3): one line of natural language, with
/// chips showing what was understood. Saving goes through the Mac's
/// `CaptureViewModel`, so dates and the default schedule follow the same rules.
struct PhoneQuickAddView: View {
    @State private var model: CaptureViewModel
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private let calendar: WorkCalendar

    init(environment: PhoneEnvironment, initialDay: Date? = nil) {
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
                        .disabled(PhoneQuickAdd.title(from: text).isEmpty || model.isSaving)
                }
            }
            .task {
                await model.loadParents()
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
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
        Task {
            await model.save()
            if model.lastError == nil {
                NotificationCenter.default.post(name: TodayFlowEvents.itemsChanged, object: nil)
                dismiss()
            }
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
