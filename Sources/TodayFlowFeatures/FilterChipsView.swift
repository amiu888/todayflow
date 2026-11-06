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
    public let onEditProjectTags: (@Sendable (WorkItem) -> Void)?
    public let tags: [String]
    public let tagFilter: String?
    public let onTagChange: (@Sendable (String?) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    public init(
        filter: TodayFilter,
        sort: TodaySort,
        projects: [WorkItem] = [],
        projectFilter: UUIDv7? = nil,
        onFilterChange: @escaping @Sendable (TodayFilter) -> Void,
        onSortChange: @escaping @Sendable (TodaySort) -> Void,
        onProjectChange: (@Sendable (UUIDv7?) -> Void)? = nil,
        onEditProjectTags: (@Sendable (WorkItem) -> Void)? = nil,
        tags: [String] = [],
        tagFilter: String? = nil,
        onTagChange: (@Sendable (String?) -> Void)? = nil,
        onSearch: @escaping @Sendable () -> Void
    ) {
        self.filter = filter
        self.sort = sort
        self.projects = projects
        self.projectFilter = projectFilter
        self.onFilterChange = onFilterChange
        self.onSortChange = onSortChange
        self.onProjectChange = onProjectChange
        self.onEditProjectTags = onEditProjectTags
        self.tags = tags
        self.tagFilter = tagFilter
        self.onTagChange = onTagChange
        self.onSearch = onSearch
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                filterChips
                Spacer(minLength: 4)
                projectMenuIfAny
                tagMenuIfAny
                sortMenu
                searchButton
            }
            ChipFlowLayout(spacing: 6, lineSpacing: 4) {
                filterChips
                projectMenuIfAny
                tagMenuIfAny
                sortMenu
                searchButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var filterChips: some View {
        ForEach(TodayFilter.allCases) { filterCase in
            chip(for: filterCase)
        }
    }

    @ViewBuilder
    private var projectMenuIfAny: some View {
        if !projects.isEmpty {
            projectMenu
        }
    }

    private var searchButton: some View {
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
                        Text(
                            project.tags.isEmpty
                                ? project.title
                                : "\(project.title) · \(TagName.display(project.tags, limit: 2))"
                        )
                        if project.id == projectFilter {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if let selectedProject = projects.first(where: { $0.id == projectFilter }),
               let onEditProjectTags
            {
                Divider()
                Button("Edit tags for “\(selectedProject.title)”…") {
                    onEditProjectTags(selectedProject)
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

    @ViewBuilder
    private var tagMenuIfAny: some View {
        if !tags.isEmpty {
            Menu {
                Button("All tags") { onTagChange?(nil) }
                Divider()
                ForEach(tags, id: \.self) { tag in
                    Button {
                        onTagChange?(tag)
                    } label: {
                        HStack {
                            Text("#\(tag)")
                            if tag == tagFilter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: tagFilter == nil ? "tag" : "tag.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        tagFilter == nil
                            ? DesignTokens.Palette.textSecondary
                            : DesignTokens.Palette.accent
                    )
                    .frame(width: 26, height: 26)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(tagFilter.map { "Tag: #\($0)" } ?? "Filter by tag")
            .accessibilityLabel(tagFilter.map { "Tag: #\($0)" } ?? "Filter by tag")
        }
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
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            isSelected
                                ? DesignTokens.Palette.accent.opacity(0.22)
                                : DesignTokens.Palette.surface
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
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


/// Wraps filter chips onto a second row when the panel is narrow. Every
/// control stays visible instead of clipping or hiding behind an overflow.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return CGSize(width: proposal.width ?? usedWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
