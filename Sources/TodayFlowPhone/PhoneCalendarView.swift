#if os(iOS)
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures

/// The Calendar tab (docs/ios/DESIGN.md §3.4): a week or month grid with
/// dots, and the selected day's tasks below. Uses the Mac's `CalendarViewModel`.
struct PhoneCalendarView: View {
    @Bindable var model: CalendarViewModel
    var onAdd: (Date) -> Void

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Picker("View", selection: $model.mode) {
                        ForEach(CalendarViewModel.Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Button("Previous", systemImage: "chevron.left") { model.previous() }
                            .labelStyle(.iconOnly)
                        Spacer()
                        Text(model.title).font(.headline)
                        Spacer()
                        Button("Next", systemImage: "chevron.right") { model.next() }
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)

                    weekdayHeader
                    if model.mode == .week {
                        dayRow(model.weekDays)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(Array(model.monthWeeks.enumerated()), id: \.offset) { _, week in
                                dayRow(week)
                            }
                        }
                    }
                }
                .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                    if value.translation.width < -40 { model.next() }
                    if value.translation.width > 40 { model.previous() }
                })
            }

            let plan = model.selectedDayPlan
            Section {
                if plan.items.isEmpty {
                    Text("No tasks").foregroundStyle(.secondary)
                }
                ForEach(plan.items.sorted { $0.endAt < $1.endAt }) { item in
                    NavigationLink(value: item.id) { PhoneCalendarRow(item: item) }
                }
            } header: {
                Text(plan.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Today") {
                    model.goToToday()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Task", systemImage: "plus") { onAdd(model.selectedDay) }
            }
        }
        .refreshable { await model.load() }
        .task { await model.load() }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.weekDays.enumerated()), id: \.offset) { _, day in
                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayRow(_ days: [CalendarViewModel.Day]) -> some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                Button {
                    model.selectedDay = day.date
                } label: {
                    VStack(spacing: 3) {
                        Text(day.date.formatted(.dateTime.day()))
                            .font(.callout.weight(day.isToday ? .bold : .regular))
                            .foregroundStyle(
                                day.isToday ? Color.accentColor
                                    : day.isInCurrentMonth || model.mode == .week ? .primary : .secondary
                            )
                        HStack(spacing: 2) {
                            ForEach(0..<min(day.openCount, 3), id: \.self) { _ in
                                Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        model.isSelected(day.date) ? Color.accentColor.opacity(0.18) : .clear,
                        in: .rect(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted) + ", \(day.openCount) open")
            }
        }
    }
}

/// A task in the selected day's list.
struct PhoneCalendarRow: View {
    let item: WorkItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.status.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.status.isComplete ? .green : .secondary)
            PriorityPill(priority: item.priority)
            Text(item.title)
                .strikethrough(item.status.isComplete)
                .lineLimit(1)
            Spacer()
            Text(item.endAt.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
#endif
