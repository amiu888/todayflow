import SwiftUI
import TodayFlowCore
import TodayFlowDesign

public struct FilterChipsView: View {
    public let filter: TodayFilter
    public let sort: TodaySort
    public let onFilterChange: @Sendable (TodayFilter) -> Void
    public let onSortChange: @Sendable (TodaySort) -> Void
    public let onSearch: @Sendable () -> Void
    public let projects: [WorkItem]
    public let projectFilter: UUIDv7?
    public let onProjectChange: (@Sendable (UUIDv7?) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    public init(
        filter: TodayFilter,
        sort: TodaySort,
        projects: [WorkItem] = [],
        projectFilter: UUIDv7? = nil,
        onFilterChange: @escaping @Sendable (TodayFilter) -> Void,
        onSortChange: @escaping @Sendable (TodaySort) -> Void,
        onProjectChange: (@Sendable (UUIDv7?) -> Void)? = nil,
        onSearch: @escaping @Sendable () -> Void
    ) {
        self.filter = filter
        self.sort = sort
        self.projects = projects
        self.projectFilter = projectFilter
        self.onFilterChange = onFilterChange
        self.onSortChange = onSortChange
        self.onProjectChange = onProjectChange
        self.onSearch = onSearch
    }

    public var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(TodayFilter.allCases) { filterCase in
                    chip(for: filterCase)
                }
            }

            Spacer()

            if !projects.isEmpty {
                projectMenu
            }

            Menu {
                ForEach(TodaySort.allCases) { sortCase in
                    Button {
                        onSortChange(sortCase)
                    } label: {
                        HStack {
                            Text(sortCase.label)
                            Spacer()
                            if sortCase == sort {
                                Image(systemName: "checkmark")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Sort")
                        .foregroundStyle(.secondary)
                    Text(sort.label)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Sort")

            Button {
                onSearch()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel("Search")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var projectMenu: some View {
        let selected = projects.first { $0.id == projectFilter }?.title

        Menu {
            Button("All projects") { onProjectChange?(nil) }
            Divider()
            ForEach(projects) { project in
                Button {
                    onProjectChange?(project.id)
                } label: {
                    HStack {
                        Text(project.title)
                        if project.id == projectFilter {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                if let selected {
                    Text(selected)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(selected == nil ? .secondary : .primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Filter by project")
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color(hex: "#38383A") : Color(hex: "#E5E5EA")
    }

    private func chip(for candidate: TodayFilter) -> some View {
        let isSelected = candidate == filter

        return Button {
            onFilterChange(candidate)
        } label: {
            Text(candidate.label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? Color.clear : borderColor, lineWidth: 1)
                )
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.label)
    }
}
