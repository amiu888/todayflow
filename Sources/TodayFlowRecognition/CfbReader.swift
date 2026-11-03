import Foundation

/// A reader for the Compound File Binary (CFB / OLE2) format — the container
/// used by Outlook `.msg` files and older Office documents.
///
/// This is a small, dependency-free implementation of the subset of MS-CFB
/// needed to read named streams: the header, the FAT (via the DIFAT array and
/// chain), the mini FAT, the directory, and stream contents (regular FAT for
/// large streams, mini FAT for streams under the 4 KiB cutoff).
///
/// Everything is little-endian; non-conforming input simply yields `nil` from
/// `init?` or `nil` from `stream(named:)`, never a crash.
public struct CfbReader: Sendable {
    /// Special FAT / directory values (MS-CFB 2.6.4).
    enum Special {
        static let free: UInt32 = 0xFFFFFFFF
        static let endOfChain: UInt32 = 0xFFFFFFFE
        static let fatSector: UInt32 = 0xFFFFFFFD
        static let difSector: UInt32 = 0xFFFFFFFC
    }

    struct DirectoryEntry: Sendable {
        var name: String
        var type: UInt8          // 1 = storage, 2 = stream, 5 = root entry
        var leftSibling: UInt32
        var rightSibling: UInt32
        var child: UInt32
        var startSector: UInt32
        var size: UInt64
    }

    private let bytes: [UInt8]
    private let sectorSize: Int
    private let miniSectorSize: Int
    private let miniCutoff: Int
    private let fat: [UInt32]
    private let miniFAT: [UInt32]
    private let entries: [DirectoryEntry]
    private let miniContainer: Data

    /// Guard against corrupt files whose FAT chains loop forever.
    private static let maxChainLength = 100_000

    public init?(data: Data) {
        let raw = [UInt8](data)
        guard raw.count >= 512 else { return nil }

        let signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        guard Array(raw[0..<8]) == signature else { return nil }

        let majorVersion = raw.u16(at: 26)
        guard majorVersion == 3 || majorVersion == 4 else { return nil }
        // 0xFFFE means little-endian.
        guard raw.u16(at: 28) == 0xFFFE else { return nil }

        let sectorShift = Int(raw.u16(at: 32))
        let miniSectorShift = Int(raw.u16(at: 34))
        guard (1...15).contains(sectorShift), (1...15).contains(miniSectorShift) else { return nil }

        let sectorSize = 1 << sectorShift
        let miniSectorSize = 1 << miniSectorShift

        let firstDirSector = raw.u32(at: 52)
        let miniCutoff = Int(raw.u32(at: 60))
        let firstMiniFAT = raw.u32(at: 64)
        let firstDIFAT = raw.u32(at: 72)

        // Collect the FAT sector IDs: the header's 109 DIFAT entries, extended
        // by the DIFAT chain (each DIFAT sector holds 126 FAT sector IDs plus
        // the ID of the next DIFAT sector).
        var fatSectorIDs = (0..<109).map { raw.u32(at: 80 + $0 * 4) }
        var difatCursor = firstDIFAT
        var difatSteps = 0
        while difatCursor != Special.free,
              difatCursor != Special.endOfChain,
              difatSteps < 10_000
        {
            let offset = 512 + Int(difatCursor) * sectorSize
            guard raw.count >= offset + sectorSize else { break }
            fatSectorIDs.append(contentsOf: (0..<126).map { raw.u32(at: offset + $0 * 4) })
            difatCursor = raw.u32(at: offset + 126 * 4)
            difatSteps += 1
        }

        let fat = Self.readSectors(sectorIDs: fatSectorIDs, bytes: raw, sectorSize: sectorSize)

        // Mini FAT: the chain of mini FAT sectors from the header.
        let miniFATBytes = Self.readChain(
            start: firstMiniFAT,
            fat: fat,
            bytes: raw,
            sectorSize: sectorSize
        ).map { [UInt8]($0) } ?? []
        let miniFAT = (0..<(miniFATBytes.count / 4)).map { miniFATBytes.u32(at: $0 * 4) }

        // Directory: the chain of directory sectors, 128-byte entries each.
        let dirBytes = Self.readChain(
            start: firstDirSector,
            fat: fat,
            bytes: raw,
            sectorSize: sectorSize
        ).map { [UInt8]($0) } ?? []
        var directoryEntries = [DirectoryEntry]()
        for offset in stride(from: 0, to: dirBytes.count - dirBytes.count % 128, by: 128) {
            directoryEntries.append(Self.parseEntry(dirBytes, at: offset))
        }
        guard !directoryEntries.isEmpty else { return nil }

        // The mini stream container is the root entry's own data (regular FAT).
        var miniContainer = Data()
        if let root = directoryEntries.first(where: { $0.type == 5 }) {
            miniContainer = Self.readChain(
                start: root.startSector,
                fat: fat,
                bytes: raw,
                sectorSize: sectorSize
            ).map { Data($0.prefix(Int(exactly: root.size) ?? $0.count)) } ?? Data()
        }

        self.bytes = raw
        self.sectorSize = sectorSize
        self.miniSectorSize = miniSectorSize
        self.miniCutoff = miniCutoff
        self.fat = fat
        self.miniFAT = miniFAT
        self.entries = directoryEntries
        self.miniContainer = miniContainer
    }

    /// Reads a stream by name (case-insensitive), or `nil` if it does not exist.
    public func stream(named name: String) -> Data? {
        guard let entry = entries.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { return nil }
        guard entry.type == 2 else { return nil }

        if entry.size < UInt64(miniCutoff) {
            return readMiniChain(start: entry.startSector).map { Data($0.prefix(Int(exactly: entry.size) ?? $0.count)) }
        }
        return readChain(start: entry.startSector).map { Data($0.prefix(Int(exactly: entry.size) ?? $0.count)) }
    }

    // MARK: - Chain walking

    private func readChain(start: UInt32) -> Data? {
        Self.readChain(start: start, fat: fat, bytes: bytes, sectorSize: sectorSize)
    }

    private func readMiniChain(start: UInt32) -> Data? {
        var chunks = [Data]()
        var cursor = start
        var count = 0
        while cursor != Special.endOfChain, cursor != Special.free, count < Self.maxChainLength {
            guard let next = Self.fatEntry(cursor, in: miniFAT) else { break }
            let offset = Int(cursor) * miniSectorSize
            guard miniContainer.count >= offset + miniSectorSize else { break }
            chunks.append(miniContainer.subdata(in: offset..<(offset + miniSectorSize)))
            cursor = next
            count += 1
        }
        return chunks.reduce(into: Data()) { $0.append($1) }
    }

    private static func readChain(
        start: UInt32,
        fat: [UInt32],
        bytes: [UInt8],
        sectorSize: Int
    ) -> Data? {
        guard start != Special.endOfChain, start != Special.free else { return Data() }
        var chunks = [Data]()
        var cursor = start
        var count = 0
        while cursor != Special.endOfChain, cursor != Special.free, count < maxChainLength {
            guard let next = fatEntry(cursor, in: fat) else { break }
            let offset = 512 + Int(cursor) * sectorSize
            guard bytes.count >= offset + sectorSize else { break }
            chunks.append(Data(bytes[offset..<offset + sectorSize]))
            cursor = next
            count += 1
        }
        return chunks.reduce(into: Data()) { $0.append($1) }
    }

    private static func readSectors(sectorIDs: [UInt32], bytes: [UInt8], sectorSize: Int) -> [UInt32] {
        var values = [UInt32]()
        for id in sectorIDs {
            guard id != Special.free, id != Special.endOfChain,
                  id != Special.fatSector, id != Special.difSector
            else { continue }
            let offset = 512 + Int(id) * sectorSize
            guard bytes.count >= offset + sectorSize else { continue }
            values.append(contentsOf: (0..<sectorSize / 4).map { bytes.u32(at: offset + $0 * 4) })
        }
        return values
    }

    private static func fatEntry(_ index: UInt32, in fat: [UInt32]) -> UInt32? {
        guard index < UInt32(fat.count) else { return nil }
        return fat[Int(index)]
    }

    // MARK: - Directory parsing

    private static func parseEntry(_ bytes: [UInt8], at offset: Int) -> DirectoryEntry {
        let nameSize = Int(bytes.u16(at: offset + 64))
        // Name size is a byte count; UTF-16 names are always even-sized, but
        // mask to even so a malformed odd size still decodes the whole units
        // it contains rather than yielding an empty name.
        let nameEnd = min(nameSize, 64) & ~1
        var name = ""
        if nameEnd > 0 {
            name = String(bytes: bytes[offset..<offset + nameEnd], encoding: .utf16LittleEndian) ?? ""
        }
        // Strip the trailing null terminator.
        while name.hasSuffix("\0") {
            name.removeLast()
        }

        return DirectoryEntry(
            name: name,
            type: bytes[offset + 66],
            leftSibling: bytes.u32(at: offset + 68),
            rightSibling: bytes.u32(at: offset + 72),
            child: bytes.u32(at: offset + 76),
            startSector: bytes.u32(at: offset + 116),
            size: bytes.u64(at: offset + 120)
        )
    }
}

// MARK: - Little-endian byte helpers

private extension Array where Element == UInt8 {
    func u16(at offset: Int) -> UInt16 {
        guard count >= offset + 2 else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func u32(at offset: Int) -> UInt32 {
        guard count >= offset + 4 else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func u64(at offset: Int) -> UInt64 {
        guard count >= offset + 8 else { return 0 }
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(self[offset + i]) << (8 * i)
        }
        return value
    }
}
