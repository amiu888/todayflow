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
    @Binding public var contactDrops: [CaptureContactDrop]
    public let contactGroups: [ContactGroup]

    public init(
        draft: Binding<CaptureDraft>,
        parents: [CaptureParentOption] = [],
        contactDrops: Binding<[CaptureContactDrop]> = .constant([]),
        contactGroups: [ContactGroup] = [],
        onSave: @escaping @Sendable () -> Void,
        onCancel: @escaping @Sendable () -> Void,
        onRemoveObject: @escaping @Sendable (Int) -> Void,
        motion: Motion = Motion(preference: .full),
        errorMessage: String? = nil,
        isSaving: Bool = false
    ) {
        self._draft = draft
        self.parents = parents
        self._contactDrops = contactDrops
        self.contactGroups = contactGroups
        self.onSave = onSave
        self.onCancel = onCancel
        self.onRemoveObject = onRemoveObject
        self.motion = motion
        self.errorMessage = errorMessage
        self.isSaving = isSaving
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var isDescriptionExpanded: Bool = false
    @State private var tagText = ""
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isTagsFocused: Bool

    @MainActor
    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleField
                    tagsField
                    attachmentSection
                    if !contactDrops.isEmpty {
                        contactSection
                    }

                    if let errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DesignTokens.Palette.warning)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.Palette.textSecondary)
                            Spacer()
                        }
                        .padding(8)
                        .background(
                            DesignTokens.Palette.warning.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .accessibilityElement(children: .combine)
                    }

                    scheduleCard
                    descriptionSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            footer
        }
        .frame(
            width: DesignTokens.Window.capture.width,
            height: DesignTokens.Window.capture.height,
            alignment: .top
        )
        .background(DesignTokens.Palette.background)
        .background(alignment: .top) {
            DesignTokens.Palette.aurora
                .frame(height: 220)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignTokens.Palette.gradient, lineWidth: 1)
        )
        .shadow(color: DesignTokens.Palette.shadow, radius: 28, y: 12)
        .overlay(alignment: .top) {
            WindowDragGrabber()
        }
        .tint(DesignTokens.Palette.accent)
        .onAppear {
            tagText = draft.tags.joined(separator: ", ")
        }
    }

    // MARK: - Header

    @MainActor
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(
                        colors: [
                            DesignTokens.Palette.accent,
                            DesignTokens.Palette.violet,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Capture something")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                Text("Drop anything, or type a task with a date")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }

            Spacer()

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Close without saving")
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Title

    @MainActor
    private var titleField: some View {
        TextField("What needs doing?", text: $draft.title)
            .textFieldStyle(.plain)
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .foregroundStyle(DesignTokens.Palette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignTokens.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isTitleFocused
                            ? DesignTokens.Palette.accent.opacity(0.8)
                            : DesignTokens.Palette.hairline,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isTitleFocused ? DesignTokens.Palette.accent.opacity(0.15) : .clear,
                radius: 8
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
            .help("Type a task; dates like “tomorrow 3pm” are understood")
    }

    // MARK: - Attachments

    @MainActor
    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Attachments")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                if !draft.objects.isEmpty {
                    Text("\(draft.objects.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(DesignTokens.Palette.accent))
                }
                Spacer()
                Text(draft.objects.isEmpty ? "optional" : "drop more to add")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Palette.textSecondary.opacity(0.8))
            }

            if draft.objects.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .foregroundStyle(DesignTokens.Palette.accent)
                    Text("Drop a file, image, link, or text · or ⌘V")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DesignTokens.Palette.surface.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            DesignTokens.Palette.hairline,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                )
                .accessibilityElement(children: .combine)
            } else {
                attachmentChips
            }
        }
    }

    /// Selects the prefilled title so the first keystroke overwrites the
    /// suggestion. Deferred to the next main-actor turn so the field is
    /// first responder before the action is sent.
    // MARK: - Tags

    @MainActor
    private var tagsField: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.caption)
                .foregroundStyle(DesignTokens.Palette.textSecondary)

            TextField("Add tags (comma separated)", text: $tagText)
                .textFieldStyle(.plain)
                .font(.caption)
                .focused($isTagsFocused)
                .onSubmit { applyTags() }

            if !draft.tags.isEmpty {
                Text("\(draft.tags.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignTokens.Palette.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DesignTokens.Palette.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(DesignTokens.Palette.hairline, lineWidth: 1)
        )
        .help("Tags make tasks and projects easy to find and filter")
        .accessibilityLabel("Tags")
    }

    @MainActor
    private func applyTags() {
        let tags = TagName.parse(tagText)
        draft.tags = tags
        tagText = tags.joined(separator: ", ")
    }

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

    // MARK: - Schedule

    @MainActor
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Contacts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                Text("\(contactDrops.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(DesignTokens.Palette.accent))
                Spacer()
                Text("added when you save")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Palette.textSecondary.opacity(0.8))
            }

            ForEach($contactDrops) { $drop in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(DesignTokens.Palette.accent)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(drop.imported.displayName)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text(drop.imported.emails.first ?? drop.imported.phones.first ?? "Contact")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Toggle("Add to Contacts", isOn: $drop.addToContacts)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .help("Add \(drop.imported.displayName) to Contacts")
                            .accessibilityLabel("Add to Contacts")

                        if drop.addToContacts, !contactGroups.isEmpty {
                            Menu {
                                Button("No group") { drop.groupId = nil }
                                ForEach(contactGroups) { group in
                                    Button(group.name) { drop.groupId = group.id }
                                }
                            } label: {
                                Label(groupName(for: drop), systemImage: "folder")
                                    .font(.caption)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Choose a contact group")
                        }
                    }

                    if drop.addToContacts {
                        HStack(spacing: 6) {
                            if let duplicate = drop.duplicate {
                                Image(systemName: "person.crop.circle.badge.exclamationmark")
                                    .font(.caption2)
                                    .foregroundStyle(DesignTokens.Palette.warning)
                                Text("Already in Contacts: \(duplicate.displayName)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Menu {
                                    ForEach(ContactDuplicateResolution.allCases) { resolution in
                                        Button(resolution.label) {
                                            drop.resolution = resolution
                                        }
                                    }
                                } label: {
                                    Label(drop.resolution.label, systemImage: "arrow.triangle.merge")
                                        .font(.caption2)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .help(drop.resolution.hint)
                            } else {
                                Text("New contact")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    } else {
                        Text("Task only — not added to Contacts")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DesignTokens.Palette.surface.opacity(0.55))
                )
            }
        }
    }

    private func groupName(for drop: CaptureContactDrop) -> String {
        guard let id = drop.groupId,
              let group = contactGroups.first(where: { $0.id == id })
        else { return "No group" }
        return group.name
    }

    @MainActor
    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Schedule", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                Spacer()
                priorityMenu
            }

            HStack(spacing: 10) {
                dateColumn(
                    title: "Starts",
                    selection: $draft.startAt
                )
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                dateColumn(
                    title: "Due",
                    selection: $draft.endAt
                )
            }

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                Picker("Project", selection: $draft.parentId) {
                    Text("No project").tag(UUIDv7?.none)
                    ForEach(parents) { parent in
                        Text(parent.title).tag(Optional(parent.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Project")
            }

            HStack(spacing: 6) {
                Image(systemName: "repeat")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                Picker("Repeat", selection: $draft.recurrence) {
                    Text("Does not repeat").tag(Recurrence?.none)
                    ForEach(Recurrence.allCases, id: \.self) { rule in
                        Text(rule.label).tag(Optional(rule))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Repeat")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Palette.hairline, lineWidth: 1)
        )
    }

    @MainActor
    private func dateColumn(
        title: String,
        selection: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
            DatePicker("", selection: selection, displayedComponents: [.date])
                .labelsHidden()
                .accessibilityLabel("\(title) date")
            DatePicker("", selection: selection, displayedComponents: [.hourAndMinute])
                .labelsHidden()
                .accessibilityLabel("\(title) time")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            HStack(spacing: 5) {
                Circle()
                    .fill(PriorityColor.color(for: current, in: scheme))
                    .frame(width: 7, height: 7)

                Text(current.label)
                    .font(.caption.weight(.semibold))

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(DesignTokens.Palette.surfaceRaised)
            )
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Set priority")
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
        HStack(spacing: 10) {
            Text("↩ add · esc cancel")
                .font(.caption2)
                .foregroundStyle(DesignTokens.Palette.textSecondary.opacity(0.8))

            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.large)
            .help("Discard this capture")
            .accessibilityLabel("Cancel")

            Button {
                applyTags()
                onSave()
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "plus")
                    }
                    Text(isSaving ? "Adding…" : "Add task")
                }
                .frame(minWidth: 92)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                isSaving
                    || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .help("Create the task (Return)")
            .accessibilityLabel("Add task")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(DesignTokens.Palette.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignTokens.Palette.hairline)
                .frame(height: 1)
        }
    }

    // MARK: - Style

    private var borderColor: Color {
        DesignTokens.Palette.hairline
    }
}
