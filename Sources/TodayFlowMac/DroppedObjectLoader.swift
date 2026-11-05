#if canImport(AppKit)
import AppKit
import Foundation
import UniformTypeIdentifiers
import TodayFlowCore
import TodayFlowRecognition

/// Turns AppKit drop payloads (`NSItemProvider`, `NSPasteboard`) into the
/// recognition pipeline's `DroppedObject` (driver.md §7 steps 1–2, FR-01/FR-06).
///
/// Loading is async because a provider may vend its contents lazily (for
/// example after a cross-process drag). All work stays on the main actor: the
/// providers themselves are not `Sendable`, and the drop path is short enough
/// that hopping actors would only delay the 300 ms sheet budget (NFR-01).
@MainActor
public struct DroppedObjectLoader {
    /// The pasteboard UTI an `NSFilePromiseProvider` advertises.
    static let promisedFileType = "com.apple.pasteboard.promised-file-url"

    public init() {}

    /// Loads every provider in order. A provider that yields nothing is
    /// skipped rather than failing the whole drop.
    public func load(from providers: [NSItemProvider]) async -> [DroppedObject] {
        var objects: [DroppedObject] = []
        objects.reserveCapacity(providers.count)
        for provider in providers {
            if let object = await load(provider) {
                objects.append(object)
            }
        }
        return objects
    }

    /// Converts one provider, preferring files over URLs, URLs over text, and
    /// images over text. That keeps a file dragged from Finder a file (rather
    /// than its filename string) while still accepting a plain-text drag.
    public func load(_ provider: NSItemProvider) async -> DroppedObject? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(provider, type: .fileURL),
           url.isFileURL
        {
            return Self.object(forFileURL: url)
        }

        // File promises (Outlook/Mail messages and calendar events) only exist
        // until the receiver copies them. Ask AppKit to materialize the
        // promised file now; `isFilePromise` tells the Materializer to keep a
        // copy in the app container.
        if provider.registeredTypeIdentifiers.contains(Self.promisedFileType),
           let url = await loadInPlaceFile(provider)
        {
            var object = Self.object(forFileURL: url)
            object.isFilePromise = true
            return object
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider, type: .url)
        {
            return DroppedObject(url: url, uti: .url)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let data = await loadData(provider, type: .image)
        {
            return DroppedObject(imageData: data, uti: .image)
        }

        if let (text, type) = await loadText(provider) {
            return DroppedObject(text: text, uti: type)
        }

        return nil
    }

    /// Text providers may vend a `String`/`NSString` object rather than a data
    /// representation (this is what `NSItemProvider(object: NSString)` does),
    /// so try the object first and fall back to the data representation.
    private func loadText(_ provider: NSItemProvider) async -> (String, UTType)? {
        for type in [UTType.utf8PlainText, .plainText, .text] {
            guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { continue }

            let object: String? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                    if let string = item as? String {
                        continuation.resume(returning: string)
                    } else if let string = item as? NSString {
                        continuation.resume(returning: string as String)
                    } else if let data = item as? Data {
                        continuation.resume(returning: String(data: data, encoding: .utf8))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            if let object { return (object, type) }

            if let data = await loadData(provider, type: type),
               let text = String(data: data, encoding: .utf8)
            {
                return (text, type)
            }
        }
        return nil
    }

    // MARK: - Provider loading

    /// Asks for the object first (file URLs and URLs are vended as `URL`), then
    /// falls back to the provider's data representation.
    private func loadURL(_ provider: NSItemProvider, type: UTType) async -> URL? {
        let objectURL: URL? = await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                // Providers vend file URLs as NSURL, URL, String, or Data
                // depending on the source app and OS version. A Finder drag
                // in particular is not guaranteed to hand back a Swift URL.
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let url = item as? NSURL {
                    continuation.resume(returning: url as URL)
                } else if let string = item as? String {
                    continuation.resume(returning: URL(string: string))
                } else if let data = item as? Data {
                    continuation.resume(returning: Self.url(from: data))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        if let objectURL { return objectURL }

        guard let data = await loadData(provider, type: type) else { return nil }
        return Self.url(from: data)
    }

    private func loadData(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// Materializes a promised file (or an in-place file representation) and
    /// returns its temporary URL. Tries each registered type because promise
    /// providers list the concrete type before the generic promise type.
    private func loadInPlaceFile(_ provider: NSItemProvider) async -> URL? {
        for type in provider.registeredTypeIdentifiers {
            let url: URL? = await withCheckedContinuation { continuation in
                provider.loadInPlaceFileRepresentation(forTypeIdentifier: type) { url, _, _ in
                    continuation.resume(returning: url)
                }
            }
            if let url { return url }
        }
        return nil
    }

    /// `public.file-url` / `public.url` data is normally the UTF-8 URL string,
    /// but older providers may hand back an archived `URL`. Accept both.
    nonisolated static func url(from data: Data) -> URL? {
        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed) { return url }
        }
        return URL(dataRepresentation: data, relativeTo: nil)
    }

    // MARK: - File metadata

    /// Builds a `DroppedObject` with the resource metadata recognizers use
    /// (folder flag, UTI, size, modification date) and in-memory bytes for the
    /// small transient formats that may disappear after the drop.
    public static func object(forFileURL url: URL) -> DroppedObject {
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .contentTypeKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ])
        let ext = url.pathExtension.lowercased()
        // Mail/Outlook/Calendar promise files are copied into the container on
        // save; recognizers parse their bytes, so load them now.
        let fileData = ["eml", "msg", "ics"].contains(ext) ? try? Data(contentsOf: url) : nil

        return DroppedObject(
            fileURL: url,
            isDirectory: values?.isDirectory,
            fileData: fileData,
            uti: values?.contentType ?? UTType(filenameExtension: ext),
            fileSize: values?.fileSize.map { Int64($0) },
            modificationDate: values?.contentModificationDate
        )
    }

    // MARK: - Pasteboard (⌘V and the menu-bar icon)

    /// The pasteboard types the app accepts. `NSPasteboard.PasteboardType` is
    /// string-backed, so this list can be registered with a view directly.
    public static let pasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .tiff, .png, .string,
    ]

    /// True when a drag contains something the app can turn into an object.
    public static func canRead(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.types?.contains(where: pasteboardTypes.contains) == true
            || !objects(from: pasteboard).isEmpty
    }

    /// Converts every pasteboard item, preserving the order the user selected
    /// or dragged. Files win over images and text within one item.
    public static func objects(from pasteboard: NSPasteboard) -> [DroppedObject] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            if let string = item.string(forType: .fileURL),
               let url = URL(string: string),
               url.isFileURL
            {
                return object(forFileURL: url)
            }
            if let string = item.string(forType: .URL),
               let url = URL(string: string)
            {
                return DroppedObject(url: url, uti: .url)
            }
            if let data = item.data(forType: .tiff) ?? item.data(forType: .png) {
                return DroppedObject(imageData: data, uti: .image)
            }
            if let text = item.string(forType: .string) {
                return DroppedObject(text: text, uti: .plainText)
            }
            return nil
        }
    }
}
#endif
