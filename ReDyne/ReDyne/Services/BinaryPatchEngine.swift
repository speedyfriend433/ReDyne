import Foundation

final class BinaryPatchEngine {
    static let shared = BinaryPatchEngine()

    struct ApplyOptions {
        var allowInPlaceWrite: Bool
        var forceApplyOnMismatch: Bool
        var outputDirectory: URL?
        var suffix: String
        var createBackup: Bool
        var backupSuffix: String
        var user: String?

        static var `default`: ApplyOptions {
            ApplyOptions(
                allowInPlaceWrite: false,
                forceApplyOnMismatch: false,
                outputDirectory: nil,
                suffix: "_patched",
                createBackup: true,
                backupSuffix: "_backup",
                user: nil
            )
        }
    }

    struct ApplyResult {
        let originalPath: String
        let outputPath: String
        let appliedPatchIDs: [UUID]
        let warnings: [String]
        let duration: TimeInterval
        let backupPath: String?
        let mismatchedPatches: [UUID]
    }

    struct VerificationResult {
        let isMatch: Bool
        let mismatches: [PatchMismatch]
    }

    struct PatchMismatch {
        let patchID: UUID
        let offset: UInt64
        let expected: Data
        let actual: Data
    }

    enum Error: Swift.Error {
        case fileNotFound(path: String)
        case cannotRead(path: String, underlying: Swift.Error)
        case cannotWrite(path: String, underlying: Swift.Error)
        case patchOutsideBounds(patchID: UUID, offset: UInt64, length: Int, fileSize: Int)
        case originalBytesMismatch(patchID: UUID, offset: UInt64, expected: Data, actual: Data)
        case overlappingPatches(patchID: UUID, overlappingWith: UUID, range: Range<UInt64>)
        case invalidPatchSet(reason: String)
        case uuidMismatch(expected: UUID, actual: UUID)
        case architectureMismatch(expected: String, actual: String)
    }

    // MARK: - Public API

    func apply(patchSet: BinaryPatchSet, toBinaryAt path: String, options: ApplyOptions = .default) throws -> ApplyResult {
        let enabledPatches = patchSet.patches.filter { $0.enabled }
        guard !enabledPatches.isEmpty else {
            throw Error.invalidPatchSet(reason: "Patch set contains no enabled patches")
        }

        try validatePatchSetConstraints(patchSet: patchSet, binaryPath: path)
        return try apply(patches: enabledPatches, toBinaryAt: path, options: options)
    }

    func apply(patches: [BinaryPatch], toBinaryAt path: String, options: ApplyOptions = .default) throws -> ApplyResult {
        guard !patches.isEmpty else {
            throw Error.invalidPatchSet(reason: "No patches to apply")
        }

        let resolvedURL = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            throw Error.fileNotFound(path: resolvedURL.path)
        }

        let startTime = CACurrentMediaTime()

        let originalData: Data
        do {
            originalData = try Data(contentsOf: resolvedURL, options: [.mappedIfSafe])
        } catch {
            throw Error.cannotRead(path: resolvedURL.path, underlying: error)
        }

        try validateNoOverlaps(in: patches)

        var mutableData = originalData
        var warnings: [String] = []
        var mismatchedPatches: [UUID] = []

        for patch in patches {
            let rangeStart = patch.fileOffset
            let length = patch.originalBytes.count
            let rangeEnd = rangeStart + UInt64(length)

            guard rangeEnd <= UInt64(mutableData.count) else {
                throw Error.patchOutsideBounds(
                    patchID: patch.id,
                    offset: rangeStart,
                    length: length,
                    fileSize: mutableData.count
                )
            }

            let intStart = Int(rangeStart)
            let currentBytes = mutableData.subdata(in: intStart ..< (intStart + length))

            if currentBytes != patch.originalBytes {
                if options.forceApplyOnMismatch {
                    warnings.append("Original bytes mismatch for patch \(patch.name); applying due to force option")
                    mismatchedPatches.append(patch.id)
                } else {
                    throw Error.originalBytesMismatch(
                        patchID: patch.id,
                        offset: patch.fileOffset,
                        expected: patch.originalBytes,
                        actual: currentBytes
                    )
                }
            }

            mutableData.replaceSubrange(intStart ..< (intStart + length), with: patch.patchedBytes)
        }

        let destinationURL = try resolveOutputURL(for: resolvedURL, options: options)
        var backupPath: String?

        if options.createBackup && destinationURL != resolvedURL {
            let backupURL = try createBackupIfNeeded(for: resolvedURL, suffix: options.backupSuffix)
            backupPath = backupURL?.path
        }

        do {
            try mutableData.write(to: destinationURL, options: .atomic)
        } catch {
            throw Error.cannotWrite(path: destinationURL.path, underlying: error)
        }

        let duration = CACurrentMediaTime() - startTime
        return ApplyResult(
            originalPath: resolvedURL.path,
            outputPath: destinationURL.path,
            appliedPatchIDs: patches.map { $0.id },
            warnings: warnings,
            duration: duration,
            backupPath: backupPath,
            mismatchedPatches: mismatchedPatches
        )
    }

    func verify(patch: BinaryPatch, inBinaryAt path: String) throws -> VerificationResult {
        let resolvedURL = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            throw Error.fileNotFound(path: resolvedURL.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: resolvedURL, options: [.mappedIfSafe])
        } catch {
            throw Error.cannotRead(path: resolvedURL.path, underlying: error)
        }

        let length = patch.originalBytes.count
        let end = patch.fileOffset + UInt64(length)
        guard end <= UInt64(data.count) else {
            throw Error.patchOutsideBounds(
                patchID: patch.id,
                offset: patch.fileOffset,
                length: length,
                fileSize: data.count
            )
        }

        let actual = data.subdata(in: Int(patch.fileOffset) ..< Int(patch.fileOffset) + length)
        if actual == patch.originalBytes {
            return VerificationResult(isMatch: true, mismatches: [])
        }

        let mismatch = PatchMismatch(
            patchID: patch.id,
            offset: patch.fileOffset,
            expected: patch.originalBytes,
            actual: actual
        )
        return VerificationResult(isMatch: false, mismatches: [mismatch])
    }

    func verify(patchSet: BinaryPatchSet, inBinaryAt path: String) throws -> VerificationResult {
        let resolvedURL = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            throw Error.fileNotFound(path: resolvedURL.path)
        }

        try validatePatchSetConstraints(patchSet: patchSet, binaryPath: path)

        let data: Data
        do {
            data = try Data(contentsOf: resolvedURL, options: [.mappedIfSafe])
        } catch {
            throw Error.cannotRead(path: resolvedURL.path, underlying: error)
        }

        var mismatches: [PatchMismatch] = []
        for patch in patchSet.patches where patch.enabled {
            let length = patch.originalBytes.count
            let end = patch.fileOffset + UInt64(length)
            if end > UInt64(data.count) {
                throw Error.patchOutsideBounds(
                    patchID: patch.id,
                    offset: patch.fileOffset,
                    length: length,
                    fileSize: data.count
                )
            }

            let actual = data.subdata(in: Int(patch.fileOffset) ..< Int(patch.fileOffset) + length)
            if actual != patch.originalBytes {
                mismatches.append(
                    PatchMismatch(
                        patchID: patch.id,
                        offset: patch.fileOffset,
                        expected: patch.originalBytes,
                        actual: actual
                    )
                )
            }
        }

        return VerificationResult(isMatch: mismatches.isEmpty, mismatches: mismatches)
    }

    // MARK: - Private Helpers

    private func validatePatchSetConstraints(patchSet: BinaryPatchSet, binaryPath: String) throws {
        if let targetPath = patchSet.targetPath {
            let standardizedTarget = URL(fileURLWithPath: targetPath).standardizedFileURL.path
            let standardizedBinary = URL(fileURLWithPath: binaryPath).standardizedFileURL.path
            guard standardizedTarget == standardizedBinary else {
                throw Error.invalidPatchSet(reason: "Patch set targets a different binary")
            }
        }

        if let expectedUUID = patchSet.targetUUID {
            if let actualUUID = try? MachOUtilities.uuidForBinary(at: binaryPath), expectedUUID != actualUUID {
                throw Error.uuidMismatch(expected: expectedUUID, actual: actualUUID)
            }
        }

        if let expectedArch = patchSet.targetArchitecture {
            if let actualArch = try? MachOUtilities.architectureForBinary(at: binaryPath), expectedArch.caseInsensitiveCompare(actualArch) != .orderedSame {
                throw Error.architectureMismatch(expected: expectedArch, actual: actualArch)
            }
        }
    }

    private func validateNoOverlaps(in patches: [BinaryPatch]) throws {
        let sorted = patches.sorted { lhs, rhs in
            if lhs.fileOffset == rhs.fileOffset {
                return lhs.originalBytes.count < rhs.originalBytes.count
            }
            return lhs.fileOffset < rhs.fileOffset
        }

        for (index, patch) in sorted.enumerated() where index > 0 {
            let previous = sorted[index - 1]
            let previousEnd = previous.fileOffset + UInt64(previous.originalBytes.count)
            if patch.fileOffset < previousEnd {
                let overlapRange = patch.fileOffset ..< previousEnd
                throw Error.overlappingPatches(
                    patchID: patch.id,
                    overlappingWith: previous.id,
                    range: overlapRange
                )
            }
        }
    }

    private func resolveOutputURL(for originalURL: URL, options: ApplyOptions) throws -> URL {
        if options.allowInPlaceWrite {
            return originalURL
        }

        let directory = options.outputDirectory ?? originalURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let extensionName = originalURL.pathExtension

        var candidateName = "\(baseName)\(options.suffix)"
        if !extensionName.isEmpty {
            candidateName += ".\(extensionName)"
        }

        var candidateURL = directory.appendingPathComponent(candidateName)
        var attempt = 1
        while FileManager.default.fileExists(atPath: candidateURL.path) {
            var newName = "\(baseName)\(options.suffix)_\(attempt)"
            if !extensionName.isEmpty {
                newName += ".\(extensionName)"
            }
            candidateURL = directory.appendingPathComponent(newName)
            attempt += 1
        }

        return candidateURL
    }

    private func createBackupIfNeeded(for url: URL, suffix: String) throws -> URL? {
        let backupURL = url.appendingPathExtension("tmp_backup")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }

        do {
            try FileManager.default.copyItem(at: url, to: backupURL)
        } catch {
            return nil
        }

        let finalBackupURL = url.deletingLastPathComponent().appendingPathComponent(
            url.deletingPathExtension().lastPathComponent + suffix + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension)
        )

        if FileManager.default.fileExists(atPath: finalBackupURL.path) {
            try FileManager.default.removeItem(at: finalBackupURL)
        }

        do {
            try FileManager.default.moveItem(at: backupURL, to: finalBackupURL)
            return finalBackupURL
        } catch {
            try? FileManager.default.removeItem(at: backupURL)
            return nil
        }
    }
}
