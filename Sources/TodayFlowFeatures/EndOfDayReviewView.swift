import SwiftUI
import Foundation
import TodayFlowCore
import TodayFlowDesign

/// The end-of-day review sheet (driver.md FR-43): unfinished tasks with
/// one-click Move to tomorrow / Pick a date / Done / Cancel.
///
/// Pure presentation over `EndOfDayReviewViewModel`; the model owns every
/// mutation. The date picker is inline per row so "Pick a date" never opens a
/// second modal on top of the review.
public struct EndOfDayReviewView: View {
    private let model: EndOfDayReviewViewModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var pickingDateFor: UUIDv7?
    @State private var pickedDate: Date = .now

    public init(model: EndOfDayReviewViewModel) {
        self.model = model
    }

    @MainActor
    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                if model.isLoading && model.rows.isEmpty {
                    loadingState
                } else if model.rows.isEmpty {
                    emptyState
                } else {
                    reviewList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let lastError = model.lastError {
                errorBanner(lastError)
            }

            Divider()
            footer
        }
        .frame(width: 440, height: 520)
        .task { await model.load() }
    }

    // MARK: - Header

    @MainActor
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("End of day")
                    .font(.title3.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var subtitle: String {
        let count = model.rows.count
        if count == 0 { return "Everything is wrapped up." }
        return "\(count) task\(count == 1 ? "" : "s") still open"
    }

    // MARK: - List

    @MainActor
    private var reviewList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(model.rows) { row in
                    rowView(row)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @MainActor
    private func rowView(_ row: EndOfDayReviewViewModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(PriorityColor.color(for: row.priority, in: colorScheme))
                    .frame(width: 8, height: 8)

                Text(row.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                Spacer()

                if row.isOverdue {
                    Text("Overdue")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(hex: "#d03b3b"))
                } else {
                    Text(row.endAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button("Tomorrow") {
                    Task { @MainActor in
                        await model.moveToTomorrow(row.id)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Move \(row.title) to tomorrow")

                Button("Pick a date…") {
                    pickedDate = model.suggestedDate
                    pickingDateFor = row.id
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Pick a date for \(row.title)")

                Button("Done") {
                    Task { @MainActor in
                        await model.markDone(row.id)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Mark \(row.title) done")

                Spacer()

                Button("Keep") {
                    model.keep(row.id)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Keep \(row.title) for today")
            }

            if pickingDateFor == row.id {
                datePicker(for: row)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @MainActor
    private func datePicker(for row: EndOfDayReviewViewModel.Row) -> some View {
        HStack(spacing: 8) {
            DatePicker(
                "Move to",
                selection: $pickedDate,
                in: model.earliestDate...,
                displayedComponents: .date
            )
            .labelsHidden()
            .accessibilityLabel("New date for \(row.title)")

            Button("Move") {
                let date = pickedDate
                pickingDateFor = nil
                Task { @MainActor in
                    await model.move(row.id, to: date)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button("Cancel") {
                pickingDateFor = nil
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - States

    @MainActor
    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Looking at what’s left…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color(hex: "#0ca30c"))

            Text("Nothing left to review")
                .font(.body.weight(.medium))

            Text("Every task on today’s list is done.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: "#fab219"))

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(hex: "#fab219").opacity(0.12))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    @MainActor
    private var footer: some View {
        HStack {
            Text("Unfinished tasks stay on today’s list.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") {
                model.finish()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cancel the end-of-day review")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
