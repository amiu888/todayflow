import SwiftUI
import Foundation
import TodayFlowCore
import TodayFlowDesign

/// The "Plan my day" sheet (driver.md §8). It is a proposal: the order is only
/// written when the user clicks "Apply order".
public struct DayPlanView: View {
    private let model: DayPlanViewModel
    private let sentPayload: (@MainActor () -> String?)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var showsSent = false

    public init(
        model: DayPlanViewModel,
        sentPayload: (@MainActor () -> String?)? = nil
    ) {
        self.model = model
        self.sentPayload = sentPayload
    }

    @MainActor
    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                if model.isLoading {
                    loadingState
                } else if model.rows.isEmpty {
                    emptyState
                } else {
                    planList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error = model.lastError {
                errorBanner(error)
            }

            if let sentPayload, sentPayload() != nil {
                DisclosureGroup(isExpanded: $showsSent) {
                    ScrollView {
                        Text(sentPayload() ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 120)
                } label: {
                    Text("What was sent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }

            Divider()
            footer
        }
        .frame(width: 480, height: 560)
        .overlay(alignment: .top) { WindowDragGrabber() }
        .task { await model.loadAndPlan() }
    }

    // MARK: - Header

    @MainActor
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Plan my day")
                    .font(.title3.weight(.semibold))

                Text(model.summary.isEmpty ? "A proposed order for today’s tasks." : model.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - List

    @MainActor
    private var planList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(PriorityColor.color(for: row.priority, in: colorScheme))
                                    .frame(width: 7, height: 7)

                                Text(row.title)
                                    .font(.body.weight(.medium))

                                Spacer()

                                Text(row.dueAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !row.reason.isEmpty {
                                Text(row.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - States

    @MainActor
    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Thinking about your day…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("No plan yet")
                .font(.body.weight(.medium))

            Text("Add tasks to today, then try again.")
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
    }

    // MARK: - Footer

    @MainActor
    private var footer: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                model.dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Apply order") {
                Task { await model.apply() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.rows.isEmpty || model.isLoading || model.isApplying)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
