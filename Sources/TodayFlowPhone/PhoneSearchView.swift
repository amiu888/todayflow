#if os(iOS)
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures

/// The Search tab (docs/ios/DESIGN.md §3.5): Quick Find as a screen, with the
/// same filter words as the Mac (`#tag @person /project due:today overdue done`).
struct PhoneSearchView: View {
    @Bindable var model: QuickFindModel

    private static let filters = ["due:today", "overdue", "done", "blocked"]

    var body: some View {
        List {
            if model.query.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.filters, id: \.self) { token in
                                Button(token) { model.insertFilter(token) }
                                    .font(.subheadline)
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            Section(model.heading) {
                ForEach(model.results) { result in
                    NavigationLink(value: result.id) { PhoneSearchRow(result: result) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Search")
        .searchable(
            text: $model.text,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Tasks, #tags, @people, /projects"
        )
        .searchSuggestions {
            ForEach(model.completions) { completion in
                Text(completion.label).searchCompletion(completion.insert + " ")
            }
        }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .overlay {
            if !model.query.isEmpty, model.results.isEmpty, !model.isLoading {
                ContentUnavailableView.search(text: model.text)
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

struct PhoneSearchRow: View {
    let result: QuickFindResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                PriorityPill(priority: result.item.priority)
                Text(result.item.title)
                    .strikethrough(result.item.status.isComplete)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if let project = result.projectTitle { Text(project) }
                Text(result.item.endAt.formatted(.dateTime.day().month(.abbreviated)))
                if let reason = result.reason { Text("· \(reason)") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let snippet = result.snippet, !snippet.isEmpty {
                Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}
#endif
