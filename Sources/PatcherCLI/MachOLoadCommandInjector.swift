// 文件说明：给 Mach-O 主可执行文件追加补丁 dylib 加载命令

import Foundation

struct MachOInjectionResult {
    let patchedSlices: Int
    let alreadyPatchedSlices: Int
}

struct MachOLoadCommandInjector {
    private let lcLoadDylib: UInt32 = 0x0c
    private let lcSegment64: UInt32 = 0x19
    private let mhMagic64: UInt32 = 0xfeedfacf
    private let fatMagic: UInt32 = 0xcafebabe
    private let fatMagic64: UInt32 = 0xcafebabf

    func containsDylib(executableURL: URL, dylibPath: String) throws -> Bool {
        let data = try Data(contentsOf: executableURL)
        return try machoSlices(in: data).contains { slice in
            try sliceContainsDylib(data: data, slice: slice, dylibPath: dylibPath)
        }
    }

    // 只追加 LC_LOAD_DYLIB，不调整 segment 偏移；header padding 不足时直接失败
    func injectDylib(executableURL: URL, dylibPath: String) throws -> MachOInjectionResult {
        var data = try Data(contentsOf: executableURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: executableURL.path)
        let slices = try machoSlices(in: data)
        var patchedCount = 0
        var alreadyCount = 0

        for slice in slices {
            let result = try patchSlice(data: &data, slice: slice, dylibPath: dylibPath)
            if result.didPatch {
                patchedCount += 1
            }
            if result.alreadyPatched {
                alreadyCount += 1
            }
        }

        if patchedCount > 0 {
            try data.write(to: executableURL)
            if let permissions = attributes[.posixPermissions] {
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: executableURL.path)
            }
        }

        return MachOInjectionResult(patchedSlices: patchedCount, alreadyPatchedSlices: alreadyCount)
    }

    private struct MachOSlice {
        let offset: Int
        let size: Int
    }

    private struct PatchSliceResult {
        let didPatch: Bool
        let alreadyPatched: Bool
    }

    private func machoSlices(in data: Data) throws -> [MachOSlice] {
        guard data.count >= 4 else {
            throw PatchCLIError.message("Mach-O 文件过小")
        }

        let magicBE = data.uint32BE(at: 0)
        if magicBE == fatMagic {
            return try fat32Slices(in: data)
        }
        if magicBE == fatMagic64 {
            return try fat64Slices(in: data)
        }

        return [MachOSlice(offset: 0, size: data.count)]
    }

    private func fat32Slices(in data: Data) throws -> [MachOSlice] {
        guard data.count >= 8 else {
            throw PatchCLIError.message("Fat Mach-O 头不完整")
        }

        let count = Int(data.uint32BE(at: 4))
        var slices: [MachOSlice] = []

        for index in 0..<count {
            let offset = 8 + index * 20
            guard offset + 20 <= data.count else {
                throw PatchCLIError.message("Fat Mach-O 架构表不完整")
            }

            let sliceOffset = Int(data.uint32BE(at: offset + 8))
            let sliceSize = Int(data.uint32BE(at: offset + 12))
            try validateSlice(offset: sliceOffset, size: sliceSize, dataCount: data.count)
            slices.append(MachOSlice(offset: sliceOffset, size: sliceSize))
        }

        return slices
    }

    private func fat64Slices(in data: Data) throws -> [MachOSlice] {
        guard data.count >= 8 else {
            throw PatchCLIError.message("Fat64 Mach-O 头不完整")
        }

        let count = Int(data.uint32BE(at: 4))
        var slices: [MachOSlice] = []

        for index in 0..<count {
            let offset = 8 + index * 32
            guard offset + 32 <= data.count else {
                throw PatchCLIError.message("Fat64 Mach-O 架构表不完整")
            }

            let sliceOffset = Int(data.uint64BE(at: offset + 8))
            let sliceSize = Int(data.uint64BE(at: offset + 16))
            try validateSlice(offset: sliceOffset, size: sliceSize, dataCount: data.count)
            slices.append(MachOSlice(offset: sliceOffset, size: sliceSize))
        }

        return slices
    }

    private func validateSlice(offset: Int, size: Int, dataCount: Int) throws {
        guard offset >= 0, size > 0, offset + size <= dataCount else {
            throw PatchCLIError.message("Fat Mach-O slice 越界")
        }
    }

    private func sliceContainsDylib(data: Data, slice: MachOSlice, dylibPath: String) throws -> Bool {
        let header = try headerInfo(data: data, slice: slice)
        var commandOffset = header.commandsOffset

        for _ in 0..<header.ncmds {
            let command = try loadCommandInfo(data: data, offset: commandOffset, slice: slice)
            if command.cmd == lcLoadDylib,
               let name = dylibName(data: data, commandOffset: commandOffset, commandSize: command.cmdsize),
               name == dylibPath {
                return true
            }
            commandOffset += command.cmdsize
        }

        return false
    }

    private func patchSlice(data: inout Data, slice: MachOSlice, dylibPath: String) throws -> PatchSliceResult {
        let header = try headerInfo(data: data, slice: slice)
        var commandOffset = header.commandsOffset
        var earliestContentOffset = slice.offset + slice.size

        for _ in 0..<header.ncmds {
            let command = try loadCommandInfo(data: data, offset: commandOffset, slice: slice)
            if command.cmd == lcLoadDylib,
               let name = dylibName(data: data, commandOffset: commandOffset, commandSize: command.cmdsize),
               name == dylibPath {
                return PatchSliceResult(didPatch: false, alreadyPatched: true)
            }

            if command.cmd == lcSegment64 {
                earliestContentOffset = min(
                    earliestContentOffset,
                    firstSectionOffset(data: data, commandOffset: commandOffset, commandSize: command.cmdsize, sliceOffset: slice.offset)
                )
            }

            commandOffset += command.cmdsize
        }

        let newCommand = makeDylibCommand(path: dylibPath)
        let loadCommandsEnd = header.commandsOffset + header.sizeofcmds
        let newEnd = loadCommandsEnd + newCommand.count

        guard newEnd <= earliestContentOffset else {
            let missingBytes = newEnd - earliestContentOffset
            throw PatchCLIError.message("主可执行文件 header padding 不足，缺少 \(missingBytes) 字节，无法安全追加 LC_LOAD_DYLIB")
        }

        data.replaceSubrange(loadCommandsEnd..<newEnd, with: newCommand)
        data.writeUInt32LE(UInt32(header.ncmds + 1), at: header.ncmdsOffset)
        data.writeUInt32LE(UInt32(header.sizeofcmds + newCommand.count), at: header.sizeofcmdsOffset)

        return PatchSliceResult(didPatch: true, alreadyPatched: false)
    }

    private struct HeaderInfo {
        let ncmds: Int
        let sizeofcmds: Int
        let ncmdsOffset: Int
        let sizeofcmdsOffset: Int
        let commandsOffset: Int
    }

    private func headerInfo(data: Data, slice: MachOSlice) throws -> HeaderInfo {
        guard slice.offset + 32 <= data.count else {
            throw PatchCLIError.message("Mach-O 64 位头不完整")
        }

        guard data.uint32LE(at: slice.offset) == mhMagic64 else {
            throw PatchCLIError.message("仅支持 64 位 little-endian Mach-O")
        }

        let ncmdsOffset = slice.offset + 16
        let sizeofcmdsOffset = slice.offset + 20
        let ncmds = Int(data.uint32LE(at: ncmdsOffset))
        let sizeofcmds = Int(data.uint32LE(at: sizeofcmdsOffset))
        let commandsOffset = slice.offset + 32

        guard commandsOffset + sizeofcmds <= slice.offset + slice.size else {
            throw PatchCLIError.message("Mach-O load commands 越界")
        }

        return HeaderInfo(
            ncmds: ncmds,
            sizeofcmds: sizeofcmds,
            ncmdsOffset: ncmdsOffset,
            sizeofcmdsOffset: sizeofcmdsOffset,
            commandsOffset: commandsOffset
        )
    }

    private struct LoadCommandInfo {
        let cmd: UInt32
        let cmdsize: Int
    }

    private func loadCommandInfo(data: Data, offset: Int, slice: MachOSlice) throws -> LoadCommandInfo {
        guard offset + 8 <= slice.offset + slice.size else {
            throw PatchCLIError.message("Mach-O load command 头越界")
        }

        let cmd = data.uint32LE(at: offset)
        let cmdsize = Int(data.uint32LE(at: offset + 4))
        guard cmdsize >= 8, offset + cmdsize <= slice.offset + slice.size else {
            throw PatchCLIError.message("Mach-O load command 长度异常")
        }

        return LoadCommandInfo(cmd: cmd, cmdsize: cmdsize)
    }

    private func dylibName(data: Data, commandOffset: Int, commandSize: Int) -> String? {
        guard commandSize >= 24 else {
            return nil
        }

        let nameOffset = Int(data.uint32LE(at: commandOffset + 8))
        let absoluteOffset = commandOffset + nameOffset
        let commandEnd = commandOffset + commandSize
        guard absoluteOffset < commandEnd else {
            return nil
        }

        var bytes: [UInt8] = []
        var cursor = absoluteOffset
        while cursor < commandEnd {
            let byte = data[cursor]
            if byte == 0 {
                break
            }
            bytes.append(byte)
            cursor += 1
        }

        return String(bytes: bytes, encoding: .utf8)
    }

    private func firstSectionOffset(data: Data, commandOffset: Int, commandSize: Int, sliceOffset: Int) -> Int {
        let sectionHeaderSize = 80
        let firstSectionOffset = commandOffset + 72
        guard commandSize >= 72 else {
            return Int.max
        }

        let sectionCount = Int(data.uint32LE(at: commandOffset + 64))
        var minOffset = Int.max

        for index in 0..<sectionCount {
            let sectionOffset = firstSectionOffset + index * sectionHeaderSize
            guard sectionOffset + sectionHeaderSize <= commandOffset + commandSize else {
                break
            }

            let fileOffset = Int(data.uint32LE(at: sectionOffset + 48))
            if fileOffset > 0 {
                minOffset = min(minOffset, sliceOffset + fileOffset)
            }
        }

        return minOffset
    }

    private func makeDylibCommand(path: String) -> [UInt8] {
        let rawPath = Array(path.utf8) + [0]
        let unpaddedSize = 24 + rawPath.count
        let commandSize = align(unpaddedSize, to: 8)
        var bytes = [UInt8](repeating: 0, count: commandSize)

        bytes.writeUInt32LE(lcLoadDylib, at: 0)
        bytes.writeUInt32LE(UInt32(commandSize), at: 4)
        bytes.writeUInt32LE(24, at: 8)
        bytes.writeUInt32LE(2, at: 16)
        bytes.writeUInt32LE(1, at: 20)

        for (index, byte) in rawPath.enumerated() {
            bytes[24 + index] = byte
        }

        return bytes
    }

    private func align(_ value: Int, to alignment: Int) -> Int {
        let remainder = value % alignment
        return remainder == 0 ? value : value + alignment - remainder
    }
}

private extension Data {
    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }

    func uint32BE(at offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24
            | UInt32(self[offset + 1]) << 16
            | UInt32(self[offset + 2]) << 8
            | UInt32(self[offset + 3])
    }

    func uint64BE(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = value << 8 | UInt64(self[offset + index])
        }
        return value
    }

    mutating func writeUInt32LE(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(value & 0xff)
        self[offset + 1] = UInt8((value >> 8) & 0xff)
        self[offset + 2] = UInt8((value >> 16) & 0xff)
        self[offset + 3] = UInt8((value >> 24) & 0xff)
    }
}

private extension Array where Element == UInt8 {
    mutating func writeUInt32LE(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(value & 0xff)
        self[offset + 1] = UInt8((value >> 8) & 0xff)
        self[offset + 2] = UInt8((value >> 16) & 0xff)
        self[offset + 3] = UInt8((value >> 24) & 0xff)
    }
}
