import Foundation

struct MachOUtilities {
    enum Error: Swift.Error {
        case invalidFile
        case notMachO
        case cannotRead
        case noUUID
        case noArchitecture
    }
    
    static func uuidForBinary(at path: String) throws -> UUID {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Error.invalidFile
        }
        
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw Error.cannotRead
        }
        defer { try? handle.close() }
        
        // Read magic number
        let magicData = handle.readData(ofLength: 4)
        guard magicData.count == 4 else {
            throw Error.notMachO
        }
        
        let magic = magicData.withUnsafeBytes { $0.load(as: UInt32.self) }
        let isMachO = magic == 0xfeedface || magic == 0xfeedfacf || 
                      magic == 0xcefaedfe || magic == 0xcffaedfe
        
        guard isMachO else {
            throw Error.notMachO
        }
        
        // Try to extract UUID via BinaryParserService
        if let output = try? BinaryParserService.parseBinary(atPath: path, progressBlock: nil),
           let uuidString = output.header.uuid,
           let uuid = UUID(uuidString: uuidString) {
            return uuid
        }
        
        throw Error.noUUID
    }
    
    static func architectureForBinary(at path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Error.invalidFile
        }
        
        guard let output = try? BinaryParserService.parseBinary(atPath: path, progressBlock: nil) else {
            throw Error.cannotRead
        }
        
        return output.header.cpuType
    }
    
    static func checksumForBinary(at path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        
        // Simple CRC32-like checksum (for now)
        var hash: UInt32 = 0
        data.withUnsafeBytes { bytes in
            for byte in bytes {
                hash = hash &+ UInt32(byte)
                hash = hash &+ (hash << 10)
                hash = hash ^ (hash >> 6)
            }
        }
        hash = hash &+ (hash << 3)
        hash = hash ^ (hash >> 11)
        hash = hash &+ (hash << 15)
        
        return String(format: "%08X", hash)
    }
}

