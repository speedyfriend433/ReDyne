import XCTest
@testable import ReDyne

/// Regression tests for the issues found in the security audit. The parser tests build
/// minimal malformed 64-bit Mach-O files; before the fixes these caused heap over-reads
/// (visible under AddressSanitizer — enable it in the test scheme for full value).
final class SecurityHardeningTests: XCTestCase {

    private var tempFiles: [URL] = []

    override func tearDownWithError() throws {
        tempFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        tempFiles = []
    }

    // MARK: - Helpers

    private func le<T: FixedWidthInteger>(_ value: T) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: MemoryLayout<T>.size)
    }

    private func machO64(loadCommands: [Data]) -> Data {
        let body = loadCommands.reduce(Data(), +)
        var data = Data()
        data += le(UInt32(0xfeedfacf))          // MH_MAGIC_64
        data += le(UInt32(0x0100000c))          // CPU_TYPE_ARM64
        data += le(UInt32(0))                   // cpusubtype
        data += le(UInt32(2))                   // MH_EXECUTE
        data += le(UInt32(loadCommands.count))  // ncmds
        data += le(UInt32(body.count))          // sizeofcmds
        data += le(UInt32(0))                   // flags
        data += le(UInt32(0))                   // reserved
        data += body
        data += Data(count: 64)                 // trailing padding so reads stay inside the file
        return data
    }

    private func segment64(nsects: UInt32) -> Data {
        var d = Data()
        d += le(UInt32(0x19)); d += le(UInt32(72))                 // LC_SEGMENT_64, no section records
        var name = Data("__TEXT".utf8); name += Data(count: 10); d += name
        d += le(UInt64(0)); d += le(UInt64(0x1000))                // vmaddr, vmsize
        d += le(UInt64(0)); d += le(UInt64(0x1000))                // fileoff, filesize
        d += le(Int32(7)); d += le(Int32(5))                       // maxprot, initprot
        d += le(nsects); d += le(UInt32(0))                        // nsects, flags
        return d
    }

    private func write(_ data: Data, name: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        tempFiles.append(url)
        return url.path
    }

    /// Parsing must finish (success or error) without crashing.
    private func assertParsesWithoutCrashing(_ data: Data, name: String,
                                             file: StaticString = #filePath, line: UInt = #line) throws {
        let path = try write(data, name: name)
        do {
            _ = try BinaryParserService.parseBinary(atPath: path, progressBlock: nil)
        } catch {
            // Rejecting a malformed binary is the expected outcome.
        }
    }

    // MARK: - Malformed Mach-O input

    func testTruncatedSymtabCommandDoesNotOverRead() throws {
        // LC_SYMTAB with cmdsize 8: only the 8-byte header exists, the struct is 24 bytes.
        let cmd = le(UInt32(0x2)) + le(UInt32(8))
        try assertParsesWithoutCrashing(machO64(loadCommands: [cmd]), name: "short_symtab")
    }

    func testTruncatedUUIDCommandDoesNotOverRead() throws {
        let cmd = le(UInt32(0x1b)) + le(UInt32(8))
        try assertParsesWithoutCrashing(machO64(loadCommands: [cmd]), name: "short_uuid")
    }

    func testTruncatedDyldInfoCommandDoesNotOverRead() throws {
        let cmd = le(UInt32(0x80000022)) + le(UInt32(8))   // LC_DYLD_INFO_ONLY
        try assertParsesWithoutCrashing(machO64(loadCommands: [cmd]), name: "short_dyldinfo")
    }

    func testSegmentClaimingMoreSectionsThanItContainsDoesNotOverRead() throws {
        try assertParsesWithoutCrashing(machO64(loadCommands: [segment64(nsects: 4000)]), name: "big_nsects")
    }

    func testSegmentWithFullLengthNameDoesNotOverRead() throws {
        var seg = segment64(nsects: 0)
        seg.replaceSubrange(8..<24, with: Data(repeating: 0x41, count: 16))   // 16 chars, no NUL
        try assertParsesWithoutCrashing(machO64(loadCommands: [seg]), name: "unterminated_segname")
    }

    func testUnterminatedStringTableDoesNotOverRead() throws {
        // LC_SYMTAB pointing at one nlist_64 whose strx lands on a string with no NUL terminator.
        let headerSize = 32
        let cmdSize = 24
        let symoff = UInt32(headerSize + cmdSize)
        let stroff = symoff + 16
        var symtab = le(UInt32(0x2)) + le(UInt32(cmdSize))
        symtab += le(symoff) + le(UInt32(1)) + le(stroff) + le(UInt32(4))
        var data = machO64(loadCommands: [symtab]).prefix(headerSize + cmdSize)
        data += le(UInt32(0)) + Data([0x0f, 1]) + le(UInt16(0)) + le(UInt64(0x1000))  // nlist_64, strx = 0
        data += Data("AAAA".utf8)                                                      // no trailing NUL
        try assertParsesWithoutCrashing(Data(data), name: "unterminated_strtab")
    }

    // MARK: - Patch engine

    func testPatchWithOverflowingOffsetIsRejectedNotTrapped() throws {
        let path = try write(Data(count: 64), name: "target.bin")
        let patch = BinaryPatch(
            name: "overflow",
            fileOffset: UInt64.max - 1,
            originalBytes: Data([0, 0, 0, 0]),
            patchedBytes: Data([1, 1, 1, 1])
        )
        XCTAssertThrowsError(try BinaryPatchEngine.shared.verify(patch: patch, inBinaryAt: path))
        XCTAssertThrowsError(try BinaryPatchEngine.shared.apply(patches: [patch], toBinaryAt: path))
    }

    func testInPlacePatchCreatesRequestedBackup() throws {
        let original = Data(repeating: 0xAA, count: 32)
        let path = try write(original, name: "inplace.bin")
        let patch = BinaryPatch(
            name: "nop",
            fileOffset: 4,
            originalBytes: Data([0xAA, 0xAA]),
            patchedBytes: Data([0x90, 0x90])
        )
        var options = BinaryPatchEngine.ApplyOptions.default
        options.allowInPlaceWrite = true
        options.createBackup = true

        let result = try BinaryPatchEngine.shared.apply(patches: [patch], toBinaryAt: path, options: options)

        let backupPath = try XCTUnwrap(result.backupPath, "in-place writes must honor createBackup")
        tempFiles.append(URL(fileURLWithPath: backupPath))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: backupPath)), original)
        XCTAssertNotEqual(try Data(contentsOf: URL(fileURLWithPath: path)), original)
    }

    // MARK: - Saved binary storage

    func testSiblingDirectoryWithSharedPrefixIsNotInStorage() throws {
        let storage = SavedBinaryStorage.shared
        let root = try storage.storageDirectoryURL()
        let sibling = root.deletingLastPathComponent()
            .appendingPathComponent(root.lastPathComponent + "-evil/file.dylib")

        XCTAssertFalse(storage.isFileInStorage(sibling))
        XCTAssertTrue(storage.isFileInStorage(root.appendingPathComponent("file.dylib")))
    }
}
