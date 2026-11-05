#if canImport(AppKit)
import AppKit
import Foundation
import UniformTypeIdentifiers
import TodayFlowCore

/// Reads contact cards dropped from other apps (macOS Contacts, Outlook, a
/// vCard file, or a contact text card) into `ImportedContact` values.
@MainActor
public enum ContactProviderImporter {
    public static func contacts(from providers: [NSItemProvider]) async -> [ImportedContact] {
        var results: [ImportedContact] = []
        for provider in providers {
            results.append(contentsOf: await contacts(from: provider))
        }
        return results
    }

    private static func contacts(from provider: NSItemProvider) async -> [ImportedContact] {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(provider),
           url.isFileURL
        {
            return await contacts(fromFile: url)
        }

        let vcardType = UTType(importedAs: "public.vcard")
        if provider.hasItemConformingToTypeIdentifier(vcardType.identifier) {
            if let data = await loadData(provider, type: vcardType),
               let text = String(data: data, encoding: .utf8)
            {
                return await parsed(text, source: "contacts")
            }
            if let text = await loadString(provider, type: vcardType) {
                return await parsed(text, source: "contacts")
            }
        }

        for type in [UTType.utf8PlainText, .plainText, .text] {
            guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { continue }
            if let text = await loadString(provider, type: type) {
                return await parsed(text, source: "contacts")
            }
        }
        return []
    }

    private static func contacts(fromFile url: URL) async -> [ImportedContact] {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return [] }
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            switch url.pathExtension.lowercased() {
            case "vcf", "vcard":
                return VCardParser.parse(text, source: "contacts")
            case "csv":
                return CSVContactParser.parse(text, source: "contacts")
            case "tsv":
                return CSVContactParser.parse(text, source: "contacts", delimiter: "\t")
            default:
                return Self.parsedSync(text, source: "contacts")
            }
        }.value
    }

    private static func parsed(_ text: String, source: String) async -> [ImportedContact] {
        await Task.detached(priority: .userInitiated) {
            Self.parsedSync(text, source: source)
        }.value
    }

    private nonisolated static func parsedSync(
        _ text: String,
        source: String
    ) -> [ImportedContact] {
        if text.contains("BEGIN:VCARD") {
            return VCardParser.parse(text, source: source)
        }
        if let contact = ContactTextParser.parse(text, source: source),
           !contact.emails.isEmpty || !contact.phones.isEmpty
        {
            return [contact]
        }
        return []
    }

    private static func loadData(
        _ provider: NSItemProvider,
        type: UTType
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadString(
        _ provider: NSItemProvider,
        type: UTType
    ) async -> String? {
        await withCheckedContinuation { continuation in
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
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let url = item as? NSURL {
                    continuation.resume(returning: url as URL)
                } else if let string = item as? String {
                    continuation.resume(returning: URL(string: string))
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8)
                {
                    continuation.resume(returning: URL(string: string))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
#endif
