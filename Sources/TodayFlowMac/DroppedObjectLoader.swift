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
        let sourceApp = Self.sourceAppHint(
            from: provider.registeredTypeIdentifiers
        ) ?? Self.externalSourceApp()
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(provider, type: .fileURL),
           url.isFileURL
        {
            return Self.object(forFileURL: url, sourceApp: sourceApp)
        }

        // File promises (Outlook/Mail messages and calendar events) only exist
        // until the receiver copies them. Ask AppKit to materialize the
        // promised file now; `isFilePromise` tells the Materializer to keep a
        // copy in the app container.
        if provider.registeredTypeIdentifiers.contains(Self.promisedFileType),
           let url = await loadInPlaceFile(provider)
        {
            var object = Self.object(forFileURL: url, sourceApp: sourceApp)
            object.isFilePromise = true
            return object
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider, type: .url)
        {
            // Some providers only advertise public.url even for a file.
            if url.isFileURL { return Self.object(forFileURL: url, sourceApp: sourceApp) }
            var object = DroppedObject(url: url, sourceApp: sourceApp, uti: .url)
            // Mail and Outlook deep links often carry the message text on the
            // same pasteboard item; keep it for the summary.
            if Self.isMailScheme(url),
               let (text, _) = await loadText(provider),
               !text.isEmpty
            {
                object.text = text
            }
            return object
        }

        // vCard data from Contacts/Outlook (some apps do not use a file URL).
        let vcardType = UTType(importedAs: "public.vcard")
        if provider.hasItemConformingToTypeIdentifier(vcardType.identifier) {
            if let data = await loadData(provider, type: vcardType),
               let text = String(data: data, encoding: .utf8),
               !text.isEmpty
            {
                return DroppedObject(text: text, sourceApp: sourceApp, uti: vcardType)
            }
            let text: String? = await withCheckedContinuation { continuation in
                provider.loadItem(
                    forTypeIdentifier: vcardType.identifier,
                    options: nil
                ) { item, _ in
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
            if let text, !text.isEmpty {
                return DroppedObject(text: text, sourceApp: sourceApp, uti: vcardType)
            }
        }

        // Ask for concrete image types first: a provider may list `public.png`
        // or `public.tiff` but refuse to vend data through the `public.image`
        // supertype. Safari/Preview screenshots commonly take this path.
        for type in [UTType.png, .tiff, .jpeg, .heic, .image] {
            guard provider.hasItemConformingToTypeIdentifier(type.identifier),
                  let data = await loadData(provider, type: type)
            else { continue }
            return DroppedObject(imageData: data, sourceApp: sourceApp, uti: type)
        }

        // Teams and other rich clients may only put HTML/RTF on the
        // pasteboard. Prefer rich text when the source app is Teams; plain
        // text is cleaner for every other source.
        if let sourceApp, sourceApp.localizedCaseInsensitiveContains("teams"),
           let (text, type) = await loadRichText(provider)
        {
            return DroppedObject(text: text, sourceApp: sourceApp, uti: type)
        }
        if let (text, type) = await loadText(provider) {
            return DroppedObject(text: text, sourceApp: sourceApp, uti: type)
        }
        if let (text, type) = await loadRichText(provider) {
            return DroppedObject(text: text, sourceApp: sourceApp, uti: type)
        }

        return nil
    }

    /// HTML/RTF from a provider, converted to readable plain text.
    private func loadRichText(_ provider: NSItemProvider) async -> (String, UTType)? {
        for type in [UTType.html, .rtf] {
            guard provider.hasItemConformingToTypeIdentifier(type.identifier) else {
                continue
            }
            if let data = await loadData(provider, type: type),
               let text = Self.plainText(from: data, type: type)
            {
                return (text, type)
            }
            let object: String? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                    if let string = item as? String {
                        continuation.resume(returning: string)
                    } else if let string = item as? NSString {
                        continuation.resume(returning: string as String)
                    } else if let attributed = item as? NSAttributedString {
                        continuation.resume(returning: attributed.string)
                    } else if let data = item as? Data {
                        continuation.resume(returning: Self.plainText(from: data, type: type))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            if let object, !object.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (object, type)
            }
        }
        return nil
    }

    /// Converts an HTML or RTF payload to plain text without WebKit.
    nonisolated static func plainText(from data: Data, type: UTType) -> String? {
        var text: String?
        if type.conforms(to: .rtf) {
            text = NSAttributedString(rtf: data, documentAttributes: nil)?.string
        } else if type.conforms(to: .html) {
            if let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            ) {
                text = attributed.string
            } else if let html = String(data: data, encoding: .utf8) {
                text = html.replacingOccurrences(
                    of: "<[^>]+>",
                    with: " ",
                    options: .regularExpression
                )
            }
        }
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
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

    /// A source hint encoded in custom pasteboard types. Teams, Outlook, and
    /// Mail may be the frontmost app only until the drop lands, so the custom
    /// type is a more reliable attribution.
    nonisolated static func sourceAppHint(from identifiers: [String]) -> String? {
        let joined = identifiers.joined(separator: " ").lowercased()
        if joined.contains("teams") { return "teams" }
        if joined.contains("outlook") { return "outlook" }
        if joined.contains("contacts") || joined.contains("addressbook") {
            return "contacts"
        }
        if joined.contains("mail") { return "com.apple.mail" }
        return nil
    }

    /// The app the user dragged from. Returns nil when TodayFlow itself is
    /// frontmost (for example ⌘V paste), so the log never claims TodayFlow
    /// supplied its own clipboard content.
    private static func externalSourceApp() -> String? {
        guard let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              identifier != Bundle.main.bundleIdentifier
        else { return nil }
        return identifier
    }

    /// Mail's message links and Outlook's deep links.
    nonisolated static func isMailScheme(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "message" || scheme == "ms-outlook"
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
    public static func object(
        forFileURL url: URL,
        sourceApp: String? = nil
    ) -> DroppedObject {
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .contentTypeKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ])
        let ext = url.pathExtension.lowercased()
        // Mail/Outlook/Calendar promise files are copied into the container on
        // save; recognizers parse their bytes, so load them now.
        let fileData = ["eml", "msg", "ics", "vcf", "vcard"].contains(ext)
            ? try? Data(contentsOf: url)
            : nil

        return DroppedObject(
            fileURL: url,
            isDirectory: values?.isDirectory,
            fileData: fileData,
            sourceApp: sourceApp,
            uti: values?.contentType ?? UTType(filenameExtension: ext),
            fileSize: values?.fileSize.map { Int64($0) },
            modificationDate: values?.contentModificationDate
        )
    }

    // MARK: - Pasteboard (⌘V and the menu-bar icon)

    /// The pasteboard types the app accepts. `NSPasteboard.PasteboardType` is
    /// string-backed, so this list can be registered with a view directly.
    public static let pasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .tiff, .png, .string, .html, .rtf,
        NSPasteboard.PasteboardType(UTType(importedAs: "public.vcard").identifier),
    ]

    /// True when a drag contains something the app can turn into an object.
    public static func canRead(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.types?.contains(where: pasteboardTypes.contains) == true
            || !objects(from: pasteboard).isEmpty
    }

    /// Reads the live drag pasteboard. During a drop this still contains the
    /// file URLs even when the `NSItemProvider` refuses to vend them, which is
    /// the safest fallback for Finder/Outlook/Teams drags.
    public static func objectsFromDragPasteboard() -> [DroppedObject] {
        objects(from: NSPasteboard(name: .drag))
    }

    /// Converts every pasteboard item, preserving the order the user selected
    /// or dragged. Files win over images and text within one item.
    public static func objects(from pasteboard: NSPasteboard) -> [DroppedObject] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        let sourceApp = sourceAppHint(
            from: (pasteboard.types ?? []).map(\.rawValue)
        ) ?? externalSourceApp()
        return items.compactMap { item in
            if let string = item.string(forType: .fileURL),
               let url = URL(string: string),
               url.isFileURL
            {
                return object(forFileURL: url, sourceApp: sourceApp)
            }
            if let string = item.string(forType: .URL),
               let url = URL(string: string)
            {
                var object = DroppedObject(url: url, sourceApp: sourceApp, uti: .url)
                if Self.isMailScheme(url),
                   let text = item.string(forType: .string),
                   !text.isEmpty,
                   text != string
                {
                    object.text = text
                }
                return object
            }
            if let data = item.data(forType: .tiff) ?? item.data(forType: .png) {
                return DroppedObject(imageData: data, sourceApp: sourceApp, uti: .image)
            }
            let vcardPasteboardType = NSPasteboard.PasteboardType(
                UTType(importedAs: "public.vcard").identifier
            )
            if let data = item.data(forType: vcardPasteboardType),
               let text = String(data: data, encoding: .utf8),
               !text.isEmpty
            {
                return DroppedObject(
                    text: text,
                    sourceApp: sourceApp,
                    uti: UTType(importedAs: "public.vcard")
                )
            }

            // Rich text (Teams chat cards, Outlook/Mail messages) before the
            // generic plain-text fallback.
            for type in [UTType.html, .rtf] {
                if let data = item.data(
                    forType: NSPasteboard.PasteboardType(type.identifier)
                ), let text = plainText(from: data, type: type) {
                    return DroppedObject(text: text, sourceApp: sourceApp, uti: type)
                }
            }
            if let text = item.string(forType: .string) {
                return DroppedObject(text: text, sourceApp: sourceApp, uti: .plainText)
            }
            return nil
        }
    }
}
#endif
