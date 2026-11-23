import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// Side by side: the contact already in Contacts on the left, the dropped one
/// on the right. Click a value to keep it, tick the emails and phones to keep,
/// then Merge, or Replace / Keep Both without picking anything.
public struct ContactCompareView: View {
    private let reason: String
    private let progress: String?
    private let allowsUseExisting: Bool
    private let cancelTitle: String
    private let onChoose: @MainActor (ContactDropChoice) -> Void
    private let onCancel: @MainActor () -> Void
    @State private var draft: ContactMergeDraft

    public init(
        existing: Contact,
        dropped: Contact,
        reason: String,
        progress: String? = nil,
        allowsUseExisting: Bool = false,
        cancelTitle: String = "Cancel",
        onChoose: @escaping @MainActor (ContactDropChoice) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.reason = reason
        self.progress = progress
        self.allowsUseExisting = allowsUseExisting
        self.cancelTitle = cancelTitle
        self.onChoose = onChoose
        self.onCancel = onCancel
        _draft = State(initialValue: ContactMergeDraft(existing: existing, dropped: dropped))
    }

    private let labelWidth: CGFloat = 84

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    columnHeaders
                    ForEach(ContactMergeDraft.Field.allCases) { field in
                        fieldRow(field)
                    }
                    listRows(title: "Email", values: $draft.emails)
                    listRows(title: "Phone", values: $draft.phones)
                }
                .padding(20)
            }
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 600, idealWidth: 660, maxWidth: .infinity)
        .frame(minHeight: 420, idealHeight: 540, maxHeight: .infinity)
        .resizableWindow()
        .background(DesignTokens.Palette.background)
        .accessibilityIdentifier("contact-compare")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.title2)
                .foregroundStyle(DesignTokens.Palette.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(draft.dropped.displayName) may already be in Contacts")
                    .font(.title3.weight(.semibold))
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                Text("Click the value to keep in each row, then Merge. Replace and Keep Both ignore your picks.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
            Spacer()
            if let progress {
                Text(progress)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DesignTokens.Palette.surfaceRaised, in: Capsule())
            }
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: labelWidth, height: 1)
            personHeader(draft.existing, caption: "In Contacts", subtitle: sourceText(draft.existing))
            personHeader(draft.dropped, caption: "Dropped", subtitle: sourceText(draft.dropped))
        }
        .padding(.bottom, 6)
    }

    private func personHeader(_ contact: Contact, caption: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Text(contact.initials)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(DesignTokens.Palette.accent.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(caption.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                Text(contact.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceText(_ contact: Contact) -> String {
        let source: String
        switch contact.source {
        case "outlook": source = "Outlook"
        case "macos": source = "macOS Contacts"
        case "vcard": source = "vCard"
        case "csv": source = "CSV"
        case "drag": source = "Dropped"
        default: source = "Added here"
        }
        return "\(source) · \(contact.updatedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: - Rows

    @ViewBuilder
    private func fieldRow(_ field: ContactMergeDraft.Field) -> some View {
        let left = ContactMergeDraft.value(field, of: draft.existing)
        let right = ContactMergeDraft.value(field, of: draft.dropped)
        if !left.isEmpty || !right.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                rowLabel(field.label, conflict: draft.isConflict(field))
                if draft.isSame(field) {
                    valueCell(left, selected: true, same: true, field: field) {}
                        .frame(maxWidth: .infinity)
                    sameCell
                } else {
                    valueCell(left, selected: draft.choices[field] == .existing, same: false, field: field) {
                        draft.choices[field] = .existing
                    }
                    valueCell(right, selected: draft.choices[field] == .dropped, same: false, field: field) {
                        draft.choices[field] = .dropped
                    }
                }
            }
        }
    }

    private func rowLabel(_ text: String, conflict: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignTokens.Palette.textSecondary)
            if conflict {
                Circle().fill(DesignTokens.Palette.warning).frame(width: 5, height: 5)
                    .help("The two contacts differ here")
            }
        }
        .frame(width: labelWidth, alignment: .trailing)
        .padding(.top, 9)
    }

    private var sameCell: some View {
        Label("Same", systemImage: "equal.circle")
            .font(.caption)
            .foregroundStyle(DesignTokens.Palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.horizontal, 10)
    }

    private func valueCell(
        _ text: String, selected: Bool, same: Bool, field: ContactMergeDraft.Field,
        action: @escaping () -> Void
    ) -> some View {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? DesignTokens.Palette.accent : DesignTokens.Palette.textSecondary.opacity(0.6))
                    .opacity(same ? 0 : 1)
                Text(empty ? "Empty" : text)
                    .font(.callout)
                    .foregroundStyle(empty ? DesignTokens.Palette.textSecondary : DesignTokens.Palette.textPrimary)
                    .italic(empty)
                    .lineLimit(field == .notes ? 4 : 1)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected && !same ? DesignTokens.Palette.accentSoft : DesignTokens.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected && !same ? DesignTokens.Palette.accent : DesignTokens.Palette.hairline,
                            lineWidth: selected && !same ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(same)
        .help(same ? "Both contacts have this" : "Keep this \(field.label.lowercased())")
        .accessibilityLabel("\(field.label): \(empty ? "empty" : text)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Each email or phone sits in the column it came from; ones on both sides
    /// show once on the left, marked "Both".
    @ViewBuilder
    private func listRows(title: String, values: Binding<[ContactMergeDraft.Value]>) -> some View {
        if !values.wrappedValue.isEmpty {
            ForEach(Array(values.wrappedValue.enumerated()), id: \.element.id) { index, value in
                HStack(alignment: .top, spacing: 10) {
                    if index == 0 {
                        rowLabel(title + (values.wrappedValue.count > 1 ? "s" : ""), conflict: false)
                    } else {
                        Color.clear.frame(width: labelWidth, height: 1)
                    }
                    if value.side == .existing {
                        checkCell(value: values[index], both: isOnBothSides(value, title: title))
                        Color.clear.frame(maxWidth: .infinity, minHeight: 1)
                    } else {
                        Color.clear.frame(maxWidth: .infinity, minHeight: 1)
                        checkCell(value: values[index], both: false)
                    }
                }
            }
        }
    }

    private func isOnBothSides(_ value: ContactMergeDraft.Value, title: String) -> Bool {
        if title == "Email" {
            let key = value.text.lowercased()
            return draft.dropped.emails.contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == key }
        }
        let key = value.text.filter(\.isNumber)
        return draft.dropped.phones.contains { $0.filter(\.isNumber) == key }
    }

    private func checkCell(value: Binding<ContactMergeDraft.Value>, both: Bool) -> some View {
        Button {
            value.wrappedValue.kept.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: value.wrappedValue.kept ? "checkmark.square.fill" : "square")
                    .foregroundStyle(value.wrappedValue.kept ? DesignTokens.Palette.accent : DesignTokens.Palette.textSecondary)
                Text(value.wrappedValue.text)
                    .font(.callout)
                    .strikethrough(!value.wrappedValue.kept)
                    .foregroundStyle(value.wrappedValue.kept ? DesignTokens.Palette.textPrimary : DesignTokens.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if both {
                    Text("Both")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DesignTokens.Palette.surfaceRaised, in: Capsule())
                        .help("Both contacts have this")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(value.wrappedValue.kept ? DesignTokens.Palette.accentSoft : DesignTokens.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(value.wrappedValue.kept ? DesignTokens.Palette.accent.opacity(0.6) : DesignTokens.Palette.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(value.wrappedValue.kept ? "Kept in the merged contact. Click to leave it out." : "Left out. Click to keep it.")
    }

    // MARK: - Footer

    private var resultSummary: String {
        let merged = draft.merged(at: .now)
        var parts = [merged.displayName]
        if !merged.company.isEmpty { parts.append(merged.company) }
        parts.append(merged.emails.count == 1 ? "1 email" : "\(merged.emails.count) emails")
        parts.append(merged.phones.count == 1 ? "1 phone" : "\(merged.phones.count) phones")
        return parts.joined(separator: " · ")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.merge")
                    .foregroundStyle(DesignTokens.Palette.accent)
                Text("Merge result: \(resultSummary)")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .lineLimit(1)
            }
            HStack {
                Button(cancelTitle) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if allowsUseExisting {
                    Button("Use Existing") { onChoose(.useExisting) }
                        .help("Link the contact on the left and change nothing")
                }
                Button("Keep Both") { onChoose(.keepBoth) }
                    .help("Add the dropped contact as a separate, new contact")
                    .accessibilityIdentifier("contact-compare-keep-both")
                Button("Replace") { onChoose(.replace) }
                    .help("Overwrite the contact on the left with everything on the right. Its groups and tasks stay.")
                    .accessibilityIdentifier("contact-compare-replace")
                Button("Merge") { onChoose(.merge(draft)) }
                    .keyboardShortcut(.defaultAction)
                    .help("Keep the values you picked in one contact")
                    .accessibilityIdentifier("contact-compare-merge")
            }
        }
    }
}
