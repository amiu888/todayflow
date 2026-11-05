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
        HStack(spacing: 6) {
            ForEach(TodayFilter.allCases) { filterCase in
                chip(for: filterCase)
            }

            Spacer(minLength: 4)

            if !projects.isEmpty {
                projectMenu
            }

            sortMenu

            Button {
                onSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .help("Search")
            .accessibilityLabel("Search")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var sortMenu: some View {
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
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    sort == .manual
                        ? DesignTokens.Palette.textSecondary
                        : DesignTokens.Palette.accent
                )
                .frame(width: 26, height: 26)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort: \(sort.label)")
        .accessibilityLabel("Sort: \(sort.label)")
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
            Image(systemName: selected == nil ? "folder" : "folder.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    selected == nil
                        ? DesignTokens.Palette.textSecondary
                        : DesignTokens.Palette.accent
                )
                .frame(width: 26, height: 26)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(selected.map { "Project: \($0)" } ?? "Filter by project")
        .accessibilityLabel(selected.map { "Project: \($0)" } ?? "Filter by project")
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
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            isSelected
                                ? DesignTokens.Palette.accent.opacity(0.22)
                                : DesignTokens.Palette.surface
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            isSelected
                                ? DesignTokens.Palette.accent.opacity(0.7)
                                : DesignTokens.Palette.hairline,
                            lineWidth: 1
                        )
                )
                .foregroundStyle(
                    isSelected
                        ? DesignTokens.Palette.accent
                        : DesignTokens.Palette.textSecondary
                )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(candidate.label)
    }
}
