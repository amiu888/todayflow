import SwiftUI
import TodayFlowCore
import TodayFlowDesign

public struct FilterChipsView: View {
    public let filter: TodayFilter
    public let sort: TodaySort
    public let onFilterChange: @Sendable (TodayFilter) -> Void
    public let onSortChange: @Sendable (TodaySort) -> Void
    public let onSearch: @Sendable () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        filter: TodayFilter,
        sort: TodaySort,
        onFilterChange: @escaping @Sendable (TodayFilter) -> Void,
        onSortChange: @escaping @Sendable (TodaySort) -> Void,
        onSearch: @escaping @Sendable () -> Void
    ) {
        self.filter = filter
        self.sort = sort
        self.onFilterChange = onFilterChange
        self.onSortChange = onSortChange
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
            .accessibilityLabel("Search")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
