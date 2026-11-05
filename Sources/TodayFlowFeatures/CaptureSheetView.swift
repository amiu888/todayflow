import SwiftUI
import Foundation
import TodayFlowCore
import TodayFlowDesign
#if canImport(AppKit)
import AppKit
#endif

/// One entry of the sheet's parent (project) picker.
public struct CaptureParentOption: Identifiable, Hashable, Sendable {
    public let id: UUIDv7
    public let title: String

    public init(id: UUIDv7, title: String) {
        self.id = id
        self.title = title
    }
}

/// The quick-add "New task" sheet (driver.md §7 step 4): renders an editable
/// `CaptureDraft` and reports user intent through the binding and callbacks.
/// Pure presentation — no business logic, data access, or AI.
public struct CaptureSheetView: View {
    @Binding public var draft: CaptureDraft
    public let parents: [CaptureParentOption]
    public let onSave: @Sendable () -> Void
    public let onCancel: @Sendable () -> Void
    public let onRemoveObject: @Sendable (Int) -> Void
    public let motion: Motion
    /// A failed save (for example an unreadable attachment) to show inline.
    public let errorMessage: String?
    public let isSaving: Bool

    public init(
        draft: Binding<CaptureDraft>,
        parents: [CaptureParentOption] = [],
        onSave: @escaping @Sendable () -> Void,
        onCancel: @escaping @Sendable () -> Void,
        onRemoveObject: @escaping @Sendable (Int) -> Void,
        motion: Motion = Motion(preference: .full),
        errorMessage: String? = nil,
        isSaving: Bool = false
    ) {
        self._draft = draft
        self.parents = parents
        self.onSave = onSave
        self.onCancel = onCancel
        self.onRemoveObject = onRemoveObject
        self.motion = motion
        self.errorMessage = errorMessage
        self.isSaving = isSaving
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var isDescriptionExpanded: Bool = false
    @FocusState private var isTitleFocused: Bool

    @MainActor
    public var body: some View {
        VStack(spacing: 14) {
            header
            titleField
            descriptionSection
            dateRow

            if !draft.objects.isEmpty {
                attachmentChips
            } else {
                dropHint
            }

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(hex: "#fab219"))
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(
                    Color(hex: "#fab219").opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(18)
        .frame(
            width: DesignTokens.Window.capture.width,
            height: DesignTokens.Window.capture.height,
            alignment: .top
        )
        .background(
            DesignTokens.Palette.surface,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignTokens.Palette.gradient, lineWidth: 1)
        )
        .shadow(color: DesignTokens.Palette.shadow, radius: 24, y: 10)
        .tint(DesignTokens.Palette.accent)
    }

    // MARK: - Header

    @MainActor
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(DesignTokens.Palette.accent)

            Text("New task")
                .font(.headline)

            Spacer()

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Title

    @MainActor
    private var titleField: some View {
        TextField("What needs doing?", text: $draft.title)
            .textFieldStyle(.plain)
            .font(.title3.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.Palette.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignTokens.Palette.hairline, lineWidth: 1)
            )
            .focused($isTitleFocused)
            .onAppear {
                isTitleFocused = true
                selectAllTitleText()
            }
            .onChange(of: isTitleFocused) { _, focused in
                if focused { selectAllTitleText() }
            }
            .accessibilityLabel("Title")
    }

    /// Shown when the sheet has no attachments — a quiet reminder that the
    /// panel accepts more than the keyboard.
    @MainActor
    private var dropHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
            Text("Drop a file, link, image, or text here — or press ⌘V.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Selects the prefilled title so the first keystroke overwrites the
    /// suggestion. Deferred to the next main-actor turn so the field is
    /// first responder before the action is sent.
    @MainActor
    private func selectAllTitleText() {
        #if canImport(AppKit)
        Task { @MainActor in
            // The field editor is the first responder while the field is
            // being edited; target it directly (the old sendAction could hit
            // the collection view instead).
            try? await Task.sleep(for: .milliseconds(40))
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                editor.selectAll(nil)
            } else {
                NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
            }
        }
        #endif
    }

    // MARK: - Description

    @MainActor
    @ViewBuilder
    private var descriptionSection: some View {
        if isDescriptionExpanded {
            TextEditor(text: $draft.descriptionMd)
                .font(.body)
                .frame(height: 80)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    Button("Hide") {
                        setDescriptionExpanded(false)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .accessibilityLabel("Hide description")
                }
                .accessibilityLabel("Description")
        } else {
            Button {
                setDescriptionExpanded(true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add description")
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add description")
        }
    }

    /// Expands or collapses the description, animating only when the motion
    /// preference allows it (nil duration = reduced motion = no animation).
    @MainActor
    private func setDescriptionExpanded(_ expanded: Bool) {
        if let duration = motion.duration(for: .rowSlide) {
            withAnimation(.easeInOut(duration: duration)) {
                isDescriptionExpanded = expanded
            }
        } else {
            isDescriptionExpanded = expanded
        }
    }

    // MARK: - Date row

    @MainActor
    private var dateRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)

            Text(dayLabel(for: draft.startAt))

            DatePicker("", selection: $draft.startAt, displayedComponents: [.hourAndMinute])
                .labelsHidden()
                .accessibilityLabel("Start")

            Text("→")
                .foregroundStyle(.secondary)

            Text(dayLabel(for: draft.endAt))

            DatePicker("", selection: $draft.endAt, displayedComponents: [.hourAndMinute])
                .labelsHidden()
                .accessibilityLabel("End")

            Spacer()

            priorityMenu
        }
    }

    /// "Today" / "Tomorrow" / "EEE d MMM" for a date.
    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    @MainActor
    private var priorityMenu: some View {
        let current = draft.priority
        let scheme = colorScheme

        return Menu {
            ForEach(Priority.allCases, id: \.self) { priority in
                Button {
                    draft.priority = priority
                } label: {
                    HStack {
                        Text(priority.label)
                        Spacer()
                        if priority == current {
                            Image(systemName: "checkmark")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(PriorityColor.color(for: current, in: scheme))
                    .frame(width: 8, height: 8)

                Text(current.label)

                Image(systemName: "chevron.down")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Priority")
    }

    // MARK: - Attachment chips

    @MainActor
    private var attachmentChips: some View {
        let scheme = colorScheme

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(draft.objects.enumerated()), id: \.offset) { index, object in
                    chip(for: object, index: index, scheme: scheme)
                }
            }
        }
    }

    @MainActor
    private func chip(for object: RecognizedObject, index: Int, scheme: ColorScheme) -> some View {
        let style = AttachmentIconStyle.style(
            uti: object.uti,
            displayName: object.displayName,
            kind: object.type
        )
        let remove = onRemoveObject

        return HStack(spacing: 6) {
            if let thumbnail = imageThumbnail(for: object) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: style.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(style.tint(in: scheme))
            }

            Text(object.displayName)
                .lineLimit(1)

            if let sourceApp = object.sourceApp {
                Text(shortAppName(sourceApp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                remove(index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(object.displayName)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.clear)
        )
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.accessibilityName), \(object.displayName)")
    }

    /// A real preview for image attachments when a local file is available.
    private func imageThumbnail(for object: RecognizedObject) -> NSImage? {
        #if canImport(AppKit)
        guard object.type == .image else { return nil }
        guard let path = object.localCopyPath ?? object.reference else { return nil }
        return NSImage(contentsOfFile: path)
        #else
        return nil
        #endif
    }

    /// "com.microsoft.outlook" → "outlook".
    private func shortAppName(_ sourceApp: String) -> String {
        sourceApp.split(separator: ".").last.map(String.init) ?? sourceApp
    }

    // MARK: - Footer

    @MainActor
    private var footer: some View {
        HStack {
            Picker("Project", selection: $draft.parentId) {
                Text("None").tag(UUIDv7?.none)

                ForEach(parents) { parent in
                    Text(parent.title).tag(Optional(parent.id))
                }
            }
            .fixedSize()
            .accessibilityLabel("Project")

            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cancel")

            Button(isSaving ? "Adding…" : "Add") {
                onSave()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(
                isSaving
                    || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .accessibilityLabel("Add task")
        }
    }

    // MARK: - Style

    private var borderColor: Color {
        DesignTokens.Palette.hairline
    }
}
