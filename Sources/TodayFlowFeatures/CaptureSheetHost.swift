#if os(macOS)
// Mac-only: hosts the Mac capture sheet; the iPhone has its own quick add.
import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// Hosts a `CaptureViewModel` and its `CaptureSheetView` (driver.md FR-02/FR-05).
///
/// The app's capture window and any future sheet presentation share this view:
/// it owns the observable model as `@State` and wires the sheet's callbacks to
/// the model's save/cancel/remove actions.
public struct CaptureSheetHost: View {
    @State private var model: CaptureViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onDropProviders: (@MainActor ([NSItemProvider]) -> Bool)?
    private let onPaste: (@MainActor (Bool) -> Bool)?
    private let onAddLink: (@MainActor (URL) -> Void)?

    public init(
        model: CaptureViewModel,
        onDropProviders: (@MainActor ([NSItemProvider]) -> Bool)? = nil,
        onPaste: (@MainActor (Bool) -> Bool)? = nil,
        onAddLink: (@MainActor (URL) -> Void)? = nil
    ) {
        self.onAddLink = onAddLink
        _model = State(initialValue: model)
        self.onDropProviders = onDropProviders
        self.onPaste = onPaste
    }

    @MainActor
    public var body: some View {
        @Bindable var model = model
        // Capturing the view model directly (rather than the @State storage)
        // keeps the closures sendable without touching the sheet's API.
        let viewModel = model

        CaptureSheetView(
            draft: $model.draft,
            parents: viewModel.parents,
            contactDrops: $model.contactDrops,
            contactGroups: viewModel.contactGroups,
            onSave: {
                Task { @MainActor in
                    await viewModel.save()
                }
            },
            onCancel: {
                Task { @MainActor in
                    viewModel.cancel()
                }
            },
            onRemoveObject: { index in
                Task { @MainActor in
                    viewModel.removeObject(at: index)
                }
            },
            motion: Motion(preference: reduceMotion ? .reduced : .full),
            errorMessage: viewModel.lastError,
            isSaving: viewModel.isSaving,
            onCreateProject: { name in
                Task { @MainActor in
                    await viewModel.createProject(named: name)
                }
            },
            onDropProviders: onDropProviders,
            onPaste: onPaste,
            onAddLink: onAddLink,
            onCompareContact: { id in viewModel.compareContactDrop(id) }
        )
        .sheet(isPresented: Binding(
            get: { viewModel.comparingContactDrop != nil },
            set: { if !$0 { viewModel.cancelContactCompare() } }
        )) {
            if let drop = viewModel.comparingContactDrop, let match = drop.match {
                ContactCompareView(
                    existing: match.existing,
                    dropped: drop.imported.contact(deviceId: "local", at: .now),
                    reason: match.explanation,
                    allowsUseExisting: true,
                    onChoose: { choice in
                        Task { @MainActor in await viewModel.chooseContactDrop(choice) }
                    },
                    onCancel: { viewModel.cancelContactCompare() }
                )
            }
        }
        .task {
            await model.loadParents()
            await model.loadContactGroups()
        }
    }
}
#endif
