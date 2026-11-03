import Foundation

/// A minimal Compound File Binary (CFB / OLE2) file builder for tests.
///
/// Produces a valid little-endian CFB container (512-byte sectors, 64-byte
/// mini sectors, 4 KiB mini cutoff) holding the given named streams — enough
/// for `CfbReader` and `MsgReader` to read back, so the tests do not need
/// binary fixture files checked into the repository.
struct CfbBuilder {
    struct Stream {
        let name: String
        let data: Data
    }

    private var streams: [Stream] = []

    private static let sectorSize = 512
    private static let miniSectorSize = 64
    private static let miniCutoff = 4096

    private static let free: UInt32 = 0xFFFFFFFF
    private static let endOfChain: UInt32 = 0xFFFFFFFE

    func adding(name: String, data: Data) -> CfbBuilder {
        var copy = self
        copy.streams.append(Stream(name: name, data: data))
        return copy
    }

    func build() -> Data {
        let sectorSize = Self.sectorSize
        let miniSectorSize = Self.miniSectorSize

        let streamCount = streams.count
        let entryCount = streamCount + 2 // root + streams + one free entry
        let dirSectors = (entryCount + 3) / 4

        let miniStreams = streams.enumerated().filter { $0.element.data.count < Self.miniCutoff }
        let regularStreams = streams.enumerated().filter { $0.element.data.count >= Self.miniCutoff }

        let miniSectorCount = miniStreams.reduce(0) {
            $0 + Int((Double($1.element.data.count) / Double(miniSectorSize)).rounded(.up))
        }
        let miniFatSectors = miniSectorCount > 0 ? (miniSectorCount + 15) / 16 : 0
        let containerSectors = (miniSectorCount + 7) / 8 // 8 mini sectors per regular sector

        // Sector layout: FAT, directory, mini FAT, mini container, stream data.
        var next = 0
        let fatSector = next; next += 1
        let dirStart = next; next += dirSectors
        let miniFatStart = next; next += miniFatSectors
        let containerStart = next; next += containerSectors
        let dataStarts: [Int] = regularStreams.map { stream -> Int in
            let start = next
            next += Int((Double(stream.element.data.count) / Double(sectorSize)).rounded(.up))
            return start
        }
        let totalSectors = next

        var file = [UInt8](repeating: 0, count: 512 + totalSectors * sectorSize)

        // Header.
        let signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        for (i, byte) in signature.enumerated() { file[i] = byte }
        file.setU16(0x003E, at: 24) // minor version
        file.setU16(3, at: 26)      // major version
        file.setU16(0xFFFE, at: 28) // little-endian
        file.setU16(UInt16(Self.log2(sectorSize)), at: 32)
        file.setU16(UInt16(Self.log2(miniSectorSize)), at: 34)
        file.setU32(0, at: 44) // directory sectors (must be 0 in v3)
        file.setU32(UInt32(dirSectors), at: 48)
        file.setU32(UInt32(dirStart), at: 52)
        file.setU32(UInt32(Self.miniCutoff), at: 60)
        file.setU32(miniFatSectors > 0 ? UInt32(miniFatStart) : Self.free, at: 64)
        file.setU32(UInt32(miniFatSectors), at: 68)
        file.setU32(Self.free, at: 72) // no DIFAT sectors
        file.setU32(0, at: 76)
        file.setU32(UInt32(fatSector), at: 80) // DIFAT[0]
        for i in 1..<109 {
            file.setU32(Self.free, at: 80 + i * 4)
        }

        // FAT.
        var fat = [UInt32](repeating: Self.free, count: totalSectors)
        fat[fatSector] = Self.endOfChain
        setChain(in: &fat, start: dirStart, length: dirSectors)
        if miniFatSectors > 0 { setChain(in: &fat, start: miniFatStart, length: miniFatSectors) }
        if containerSectors > 0 { setChain(in: &fat, start: containerStart, length: containerSectors) }
        for (index, start) in dataStarts.enumerated() {
            let length = Int((Double(regularStreams[index].element.data.count) / Double(sectorSize)).rounded(.up))
            setChain(in: &fat, start: start, length: length)
        }
        for (i, value) in fat.enumerated() {
            file.setU32(value, at: 512 + fatSector * sectorSize + i * 4)
        }

        // Directory.
        let freeIndex = UInt32(streamCount + 1)
        writeEntry(&file, index: 0, dirStart: dirStart, name: "Root Entry", type: 5,
                   left: freeIndex, right: freeIndex,
                   child: streamCount > 0 ? 1 : freeIndex,
                   start: miniSectorCount > 0 ? UInt32(containerStart) : Self.endOfChain,
                   size: UInt64(miniSectorCount * miniSectorSize))
        for (i, stream) in streams.enumerated() {
            let isMini = stream.data.count < Self.miniCutoff
            let start: UInt32
            if isMini {
                let offset = streams.prefix(i).filter { $0.data.count < Self.miniCutoff }.reduce(0) {
                    $0 + Int((Double($1.data.count) / Double(miniSectorSize)).rounded(.up))
                }
                start = UInt32(offset)
            } else {
                let regularIndex = streams.prefix(i).filter { $0.data.count >= Self.miniCutoff }.count
                start = UInt32(dataStarts[regularIndex])
            }
            writeEntry(&file, index: i + 1, dirStart: dirStart, name: stream.name, type: 2,
                       left: freeIndex,
                       right: i + 1 < streamCount ? UInt32(i + 2) : freeIndex,
                       child: freeIndex,
                       start: start,
                       size: UInt64(stream.data.count))
        }
        // The free entry stays all zeros.

        // Mini FAT.
        if miniSectorCount > 0 {
            var miniFat = [UInt32](repeating: Self.free, count: ((miniSectorCount + 15) / 16) * 16)
            var offset = 0
            for stream in miniStreams {
                let length = Int((Double(stream.element.data.count) / Double(miniSectorSize)).rounded(.up))
                setChain(in: &miniFat, start: offset, length: length)
                offset += length
            }
            for (i, value) in miniFat.enumerated() {
                file.setU32(value, at: 512 + miniFatStart * sectorSize + i * 4)
            }
        }

        // Mini container.
        var miniOffset = 0
        for stream in miniStreams {
            let base = 512 + containerStart * sectorSize + miniOffset * miniSectorSize
            stream.element.data.copyBytes(to: &file, at: base)
            miniOffset += Int((Double(stream.element.data.count) / Double(miniSectorSize)).rounded(.up))
        }

        // Regular stream data.
        for (index, stream) in regularStreams.enumerated() {
            let base = 512 + dataStarts[index] * sectorSize
            stream.element.data.copyBytes(to: &file, at: base)
        }

        return Data(file)
    }

    private func setChain(in fat: inout [UInt32], start: Int, length: Int) {
        for i in 0..<length {
            fat[start + i] = i < length - 1 ? UInt32(start + i + 1) : Self.endOfChain
        }
    }

    private func writeEntry(
        _ file: inout [UInt8],
        index: Int,
        dirStart: Int,
        name: String,
        type: UInt8,
        left: UInt32,
        right: UInt32,
        child: UInt32,
        start: UInt32,
        size: UInt64
    ) {
        let base = 512 + (dirStart + index / 4) * Self.sectorSize + (index % 4) * 128
        let nameUnits = Array((name + "\0").utf16)
        for (i, unit) in nameUnits.enumerated() {
            file[base + i * 2] = UInt8(unit & 0xFF)
            file[base + i * 2 + 1] = UInt8(unit >> 8)
        }
        // The name size is in BYTES (UTF-16 code units × 2), per the MS-CFB
        // directory-entry spec — the reader decodes it as a byte count.
        file.setU16(UInt16(nameUnits.count * 2), at: base + 64)
        file[base + 66] = type
        file[base + 67] = 1 // black node
        file.setU32(left, at: base + 68)
        file.setU32(right, at: base + 72)
        file.setU32(child, at: base + 76)
        file.setU32(start, at: base + 116)
        file.setU64(size, at: base + 120)
    }

    private static func log2(_ value: Int) -> Int {
        var result = 0
        var v = value
        while v > 1 {
            v /= 2
            result += 1
        }
        return result
    }
}

private extension Data {
    func copyBytes(to file: inout [UInt8], at offset: Int) {
        let bytes = [UInt8](self)
        for (i, byte) in bytes.enumerated() {
            file[offset + i] = byte
        }
    }
}

private extension Array where Element == UInt8 {
    mutating func setU16(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8(value >> 8 & 0xFF)
    }

    mutating func setU32(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8(value >> 8 & 0xFF)
        self[offset + 2] = UInt8(value >> 16 & 0xFF)
        self[offset + 3] = UInt8(value >> 24 & 0xFF)
    }

    mutating func setU64(_ value: UInt64, at offset: Int) {
        for i in 0..<8 {
            self[offset + i] = UInt8((value >> (8 * i)) & 0xFF)
        }
    }
}
