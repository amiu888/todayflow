import SwiftUI
import TodayFlowCore
import UIKit
import UniformTypeIdentifiers

/// "Share → TodayFlow" (docs/ios/DESIGN.md §4). Reads what was shared, lets the
/// person confirm a title, priority and day, and leaves it in the app group
/// inbox. The app turns it into a task the next time it opens.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.onFinish = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        model.onCancel = { [weak self] in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { await model.load(items) }
    }
}

@MainActor
@Observable
final class ShareModel {
    var title = ""
    var priority: Priority = .default
    var due: ShareInboxItem.Due = .automatic
    var urls: [URL] = []
    var texts: [String] = []
    var files: [URL] = []
    var isLoading = true
    var error: String?

    @ObservationIgnored var onFinish: () -> Void = {}
    @ObservationIgnored var onCancel: () -> Void = {}

    /// Copies of shared files live here until they are moved into the inbox.
    private let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true)

    var summary: String {
        var parts: [String] = []
        if !urls.isEmpty { parts.append(urls.count == 1 ? "1 link" : "\(urls.count) links") }
        if !files.isEmpty { parts.append(files.count == 1 ? files[0].lastPathComponent : "\(files.count) files") }
        if !texts.isEmpty, urls.isEmpty, files.isEmpty { parts.append("text") }
        return parts.joined(separator: " · ")
    }

    func load(_ items: [NSExtensionItem]) async {
        defer { isLoading = false }
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var suggestedTitle = items.compactMap { $0.attributedContentText?.string }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    urls.append(url)
                }
            } else if let type = Self.fileType(of: provider) {
                if let copy = await copyFile(provider, type: type) { files.append(copy) }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    // Some apps share a link as text.
                    if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                       url.scheme?.hasPrefix("http") == true {
                        urls.append(url)
                    } else {
                        texts.append(text)
                    }
                }
            }
        }
        if suggestedTitle == nil {
            suggestedTitle = texts.first.map { String($0.prefix(120)) }
                ?? files.first.map { $0.deletingPathExtension().lastPathComponent }
        }
        // A bare link: leave the title empty so the app's recognizers name it
        // (page titles, Jira keys) exactly as on the Mac.
        title = suggestedTitle?
            .split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    func save() {
        guard let inbox = ShareInbox.shared() else {
            error = "TodayFlow's shared folder isn't available. Open TodayFlow once, then try again."
            return
        }
        let item = ShareInboxItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: priority,
            due: due,
            urls: urls,
            texts: texts
        )
        do {
            _ = try inbox.add(item, copying: files)
            try? FileManager.default.removeItem(at: scratch)
            onFinish()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func cancel() {
        try? FileManager.default.removeItem(at: scratch)
        onCancel()
    }

    private static let fileTypes: [UTType] = [.image, .pdf, .movie, .audio, .data]

    private static func fileType(of provider: NSItemProvider) -> UTType? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) { return .data }
        guard !provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return fileTypes.first { provider.hasItemConformingToTypeIdentifier($0.identifier) }
    }

    private func copyFile(_ provider: NSItemProvider, type: UTType) async -> URL? {
        let suggestedName = provider.suggestedName
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { [scratch] url, _, _ in
                guard let url else { return continuation.resume(returning: nil) }
                let name = suggestedName.map { name in
                    url.pathExtension.isEmpty || name.hasSuffix(".\(url.pathExtension)")
                        ? name : "\(name).\(url.pathExtension)"
                } ?? url.lastPathComponent
                let target = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    .appendingPathComponent(name)
                do {
                    try FileManager.default.createDirectory(
                        at: target.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    try FileManager.default.copyItem(at: url, to: target)
                    continuation.resume(returning: target)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (optional for links)", text: $model.title, axis: .vertical)
                        .lineLimit(1...3)
                    if model.isLoading {
                        ProgressView()
                    } else if !model.summary.isEmpty {
                        Label(model.summary, systemImage: model.files.isEmpty ? "link" : "paperclip")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Picker("Due", selection: $model.due) {
                        Text("Today").tag(ShareInboxItem.Due.automatic)
                        Text("Tomorrow").tag(ShareInboxItem.Due.tomorrow)
                        Text("Next week").tag(ShareInboxItem.Due.nextWeek)
                    }
                    .pickerStyle(.segmented)
                    Picker("Priority", selection: $model.priority) {
                        ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text("The task appears in TodayFlow the next time you open it.")
                }
                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Add to TodayFlow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.cancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { model.save() }
                        .disabled(model.isLoading || (model.title.isEmpty && model.urls.isEmpty
                            && model.files.isEmpty && model.texts.isEmpty))
                }
            }
        }
    }
}
