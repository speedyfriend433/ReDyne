import Foundation

// MARK: - Binary Patch Models

struct BinaryPatch: Codable, Identifiable, Equatable {
    enum Severity: String, Codable {
        case info
        case low
        case medium
        case high
        case critical
    }

    enum Status: String, Codable {
        case draft
        case ready
        case applied
        case reverted
    }

    let id: UUID
    var name: String
    var description: String?
    var severity: Severity
    var status: Status
    var enabled: Bool
    var virtualAddress: UInt64
    var fileOffset: UInt64
    var originalBytes: Data
    var patchedBytes: Data
    var author: String?
    var createdAt: Date
    var updatedAt: Date
    var tags: [String]
    var checksum: String
    var requiredSymbols: [String]
    var notes: String?
    var expectedUUID: UUID?
    var expectedArchitecture: String?
    var minAppVersion: String?
    var maxAppVersion: String?
    var verified: Bool
    var verificationMessage: String?

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        severity: Severity = .medium,
        status: Status = .draft,
        enabled: Bool = true,
        virtualAddress: UInt64,
        fileOffset: UInt64,
        originalBytes: Data,
        patchedBytes: Data,
        author: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        tags: [String] = [],
        checksum: String,
        requiredSymbols: [String] = [],
        notes: String? = nil,
        expectedUUID: UUID? = nil,
        expectedArchitecture: String? = nil,
        minAppVersion: String? = nil,
        maxAppVersion: String? = nil,
        verified: Bool = false,
        verificationMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.severity = severity
        self.status = status
        self.enabled = enabled
        self.virtualAddress = virtualAddress
        self.fileOffset = fileOffset
        self.originalBytes = originalBytes
        self.patchedBytes = patchedBytes
        self.author = author
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.checksum = checksum
        self.requiredSymbols = requiredSymbols
        self.notes = notes
        self.expectedUUID = expectedUUID
        self.expectedArchitecture = expectedArchitecture
        self.minAppVersion = minAppVersion
        self.maxAppVersion = maxAppVersion
        self.verified = verified
        self.verificationMessage = verificationMessage
    }
}

struct BinaryPatchAuditEntry: Codable, Identifiable {
    enum EventType: String, Codable {
        case created
        case updated
        case applied
        case reverted
        case deleted
        case verified
        case error
    }

    let id: UUID
    let timestamp: Date
    let user: String?
    let event: EventType
    let patchID: UUID?
    let details: String
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        user: String? = nil,
        event: EventType,
        patchID: UUID? = nil,
        details: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.user = user
        self.event = event
        self.patchID = patchID
        self.details = details
        self.metadata = metadata
    }
}

struct BinaryPatchSet: Codable, Identifiable {
    enum Status: String, Codable {
        case draft
        case ready
        case applied
        case archived
    }

    let id: UUID
    var name: String
    var description: String?
    var status: Status
    var createdAt: Date
    var updatedAt: Date
    var author: String?

    var targetUUID: UUID?
    var targetArchitecture: String?
    var targetPath: String?

    var patchCount: Int {
        patches.count
    }

    var enabledPatchCount: Int {
        patches.filter { $0.enabled }.count
    }

    var tags: [String]
    var version: Int
    var revision: Int

    var patches: [BinaryPatch]
    var auditLog: [BinaryPatchAuditEntry]

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        status: Status = .draft,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        author: String? = nil,
        targetUUID: UUID? = nil,
        targetArchitecture: String? = nil,
        targetPath: String? = nil,
        tags: [String] = [],
        version: Int = 1,
        revision: Int = 0,
        patches: [BinaryPatch] = [],
        auditLog: [BinaryPatchAuditEntry] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.author = author
        self.targetUUID = targetUUID
        self.targetArchitecture = targetArchitecture
        self.targetPath = targetPath
        self.tags = tags
        self.version = version
        self.revision = revision
        self.patches = patches
        self.auditLog = auditLog
    }
}

// MARK: - Metadata

struct BinarySnapshot: Codable {
    let filePath: String
    let fileSize: UInt64
    let checksum: String
    let machoUUID: UUID?
    let architecture: String?
    let segments: [MachOSegmentSnapshot]
    let creationDate: Date
}

struct MachOSegmentSnapshot: Codable {
    let name: String
    let vmAddress: UInt64
    let vmSize: UInt64
    let fileOffset: UInt64
    let fileSize: UInt64
}
