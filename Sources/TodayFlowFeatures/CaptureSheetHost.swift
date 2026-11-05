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

    public init(model: CaptureViewModel) {
        _model = State(initialValue: model)
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
            isSaving: viewModel.isSaving
        )
        .task {
            await model.loadParents()
            await model.loadContactGroups()
        }
    }
}
