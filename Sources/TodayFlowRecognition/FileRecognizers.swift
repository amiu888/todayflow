import Foundation
import UniformTypeIdentifiers
import TodayFlowCore

/// Recognizes folders (driver.md §7).
public struct FolderRecognizer: ObjectRecognizer {
    public init() {}

    public func canHandle(_ object: DroppedObject) -> Bool {
        object.fileURL != nil && object.isDirectory == true
    }

    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        guard let url = object.fileURL else {
            return RecognizedObject(type: .folder, displayName: "Folder")
        }
        let name = url.lastPathComponent
        return RecognizedObject(
            type: .folder,
            uti: object.uti?.identifier ?? UTType.folder.identifier,
            displayName: name,
            sourceApp: object.sourceApp,
            reference: url.path,
            metadata: [
                MetadataKeys.path: url.path,
                MetadataKeys.size: object.fileSize.map(String.init),
            ].compactMapValues { $0 },
            suggestedTitle: name
        )
    }
}

/// Recognizes Word, Excel, and PowerPoint documents (driver.md §7).
public struct OfficeDocumentRecognizer: ObjectRecognizer {
    /// The Office UTIs v1 supports, with the kind used for `metadata[officeKind]`.
    static let kinds: [(uti: String, kind: String)] = [
        ("com.microsoft.word.doc", "word"),
        ("org.openxmlformats.wordprocessingml.document", "word"),
        ("org.openxmlformats.wordprocessingml.document.macroEnabled", "word"),
        ("com.microsoft.excel.xls", "excel"),
        ("org.openxmlformats.spreadsheetml.sheet", "excel"),
        ("org.openxmlformats.spreadsheetml.sheet.macroEnabled", "excel"),
        ("com.microsoft.powerpoint.ppt", "powerpoint"),
        ("org.openxmlformats.presentationml.presentation", "powerpoint"),
        ("org.openxmlformats.presentationml.presentation.macroEnabled", "powerpoint"),
    ]

    public init() {}

    public func canHandle(_ object: DroppedObject) -> Bool {
        guard let identifier = object.uti?.identifier else { return false }
        return Self.kinds.contains { $0.uti == identifier }
    }

    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        guard let url = object.fileURL else {
            return RecognizedObject(type: .file, displayName: "Office document")
        }
        let name = url.lastPathComponent
        let baseName = url.deletingPathExtension().lastPathComponent
        let kind = Self.kinds.first { $0.uti == object.uti?.identifier }?.kind
        return RecognizedObject(
            type: .file,
            uti: object.uti?.identifier,
            displayName: name,
            sourceApp: object.sourceApp,
            reference: url.path,
            metadata: [
                MetadataKeys.size: object.fileSize.map(String.init),
                MetadataKeys.officeKind: kind,
            ].compactMapValues { $0 },
            suggestedTitle: baseName
        )
    }
}

/// Recognizes PDFs (driver.md §7).
///
/// The PDF's own title metadata and page count are extracted asynchronously by
/// the enricher (driver.md §7 step 5) — the drop path only uses the file name
/// to stay inside the 300 ms budget (NFR-01).
public struct PDFRecognizer: ObjectRecognizer {
    public init() {}

    public func canHandle(_ object: DroppedObject) -> Bool {
        object.uti?.conforms(to: .pdf) == true
    }

    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        guard let url = object.fileURL else {
            return RecognizedObject(type: .file, displayName: "PDF")
        }
        let name = url.lastPathComponent
        let baseName = url.deletingPathExtension().lastPathComponent
        return RecognizedObject(
            type: .file,
            uti: object.uti?.identifier ?? UTType.pdf.identifier,
            displayName: name,
            sourceApp: object.sourceApp,
            reference: url.path,
            metadata: [MetadataKeys.size: object.fileSize.map(String.init)].compactMapValues { $0 },
            suggestedTitle: baseName
        )
    }
}

/// Recognizes images, including pasted screenshots (driver.md §7).
public struct ImageRecognizer: ObjectRecognizer {
    public init() {}

    public func canHandle(_ object: DroppedObject) -> Bool {
        object.uti?.conforms(to: .image) == true || object.imageData != nil
    }

    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        let name = object.fileURL?.lastPathComponent ?? "Pasted image"
        let baseName = object.fileURL?.deletingPathExtension().lastPathComponent ?? "Pasted image"
        return RecognizedObject(
            type: .image,
            uti: object.uti?.identifier ?? UTType.image.identifier,
            displayName: name,
            sourceApp: object.sourceApp,
            reference: object.fileURL?.path,
            metadata: [MetadataKeys.size: object.fileSize.map(String.init)].compactMapValues { $0 },
            suggestedTitle: baseName
        )
    }
}

/// Recognizes web links (driver.md §7).
///
/// The page title is fetched asynchronously by the enricher; the drop path
/// falls back to the domain.
public struct WebURLRecognizer: ObjectRecognizer {
    public init() {}

    public func canHandle(_ object: DroppedObject) -> Bool {
        guard let scheme = object.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        guard let url = object.url else {
            return RecognizedObject(type: .url, displayName: "Link")
        }
        let host = (url.host() ?? "").replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        return RecognizedObject(
            type: .url,
            displayName: host.isEmpty ? url.absoluteString : host,
            sourceApp: object.sourceApp,
            reference: url.absoluteString,
            metadata: [MetadataKeys.domain: host].compactMapValues { $0 },
            suggestedTitle: host.isEmpty ? nil : host
        )
    }
}

/// Recognizes any other file (driver.md §7) — the catch-all for file URLs.
public struct GenericFileRecognizer: ObjectRecognizer {
    public init() {}

    public func canHandle(_ object: DroppedObject) -> Bool {
        object.fileURL != nil && object.isDirectory != true
    }

    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        guard let url = object.fileURL else {
            return RecognizedObject(type: .file, displayName: "File")
        }
        let name = url.lastPathComponent
        let baseName = url.deletingPathExtension().lastPathComponent
        return RecognizedObject(
            type: .file,
            uti: object.uti?.identifier,
            displayName: name,
            sourceApp: object.sourceApp,
            reference: url.path,
            metadata: [
                MetadataKeys.size: object.fileSize.map(String.init),
                MetadataKeys.path: url.path,
            ].compactMapValues { $0 },
            suggestedTitle: baseName
        )
    }
}

/// Recognizes pasted or dropped plain text (driver.md §7).
public struct PlainTextRecognizer: ObjectRecognizer {
    public init() {}

    public func canHandle(_ object: DroppedObject) -> Bool {
        object.text != nil
    }

    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        let text = object.text ?? ""
        let firstLine = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
            .map { String($0.prefix(80)) }

        return RecognizedObject(
            type: .text,
            displayName: "Pasted text",
            sourceApp: object.sourceApp,
            suggestedTitle: firstLine,
            previewText: text
        )
    }
}
