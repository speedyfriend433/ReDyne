import Foundation

class FunctionDatabase {
    
    // MARK: - Models
    
    struct FunctionMetadata: Codable {
        let address: UInt64
        var customName: String?
        var comment: String?
        var tags: [String]
        var lastModified: Date
        
        init(address: UInt64, customName: String? = nil, comment: String? = nil) {
            self.address = address
            self.customName = customName
            self.comment = comment
            self.tags = []
            self.lastModified = Date()
        }
    }
    
    struct BinaryDatabase: Codable {
        let binaryPath: String
        let binaryHash: String
        var functions: [UInt64: FunctionMetadata]
        var lastModified: Date
        
        init(binaryPath: String, binaryHash: String) {
            self.binaryPath = binaryPath
            self.binaryHash = binaryHash
            self.functions = [:]
            self.lastModified = Date()
        }
    }
    
    // MARK: - Properties
    
    private var databases: [String: BinaryDatabase] = [:]
    private let persistenceKey = "com.redyne.functionDatabase"
    private let fileManager = FileManager.default
    
    static let shared = FunctionDatabase()
    
    // MARK: - Initialization
    
    private init() {
        loadFromDisk()
    }
    
    // MARK: - Public API
    
    func getDatabase(for binaryPath: String) -> BinaryDatabase {
        let hash = computeHash(for: binaryPath)
        
        if let existing = databases[hash] {
            return existing
        }
        
        let new = BinaryDatabase(binaryPath: binaryPath, binaryHash: hash)
        databases[hash] = new
        saveToDisk()
        return new
    }
    
    func rename(binaryPath: String, address: UInt64, newName: String) {
        let hash = computeHash(for: binaryPath)
        
        if databases[hash] == nil {
            databases[hash] = BinaryDatabase(binaryPath: binaryPath, binaryHash: hash)
        }
        
        var metadata = databases[hash]!.functions[address] ?? FunctionMetadata(address: address)
        metadata.customName = newName.isEmpty ? nil : newName
        metadata.lastModified = Date()
        
        databases[hash]!.functions[address] = metadata
        databases[hash]!.lastModified = Date()
        
        saveToDisk()
    }
    
    func getName(binaryPath: String, address: UInt64) -> String? {
        let hash = computeHash(for: binaryPath)
        return databases[hash]?.functions[address]?.customName
    }
    
    func addComment(binaryPath: String, address: UInt64, comment: String) {
        let hash = computeHash(for: binaryPath)
        
        if databases[hash] == nil {
            databases[hash] = BinaryDatabase(binaryPath: binaryPath, binaryHash: hash)
        }
        
        var metadata = databases[hash]!.functions[address] ?? FunctionMetadata(address: address)
        metadata.comment = comment.isEmpty ? nil : comment
        metadata.lastModified = Date()
        
        databases[hash]!.functions[address] = metadata
        databases[hash]!.lastModified = Date()
        
        saveToDisk()
    }
    
    func getComment(binaryPath: String, address: UInt64) -> String? {
        let hash = computeHash(for: binaryPath)
        return databases[hash]?.functions[address]?.comment
    }
    
    func addTag(binaryPath: String, address: UInt64, tag: String) {
        let hash = computeHash(for: binaryPath)
        
        if databases[hash] == nil {
            databases[hash] = BinaryDatabase(binaryPath: binaryPath, binaryHash: hash)
        }
        
        var metadata = databases[hash]!.functions[address] ?? FunctionMetadata(address: address)
        if !metadata.tags.contains(tag) {
            metadata.tags.append(tag)
            metadata.lastModified = Date()
            
            databases[hash]!.functions[address] = metadata
            databases[hash]!.lastModified = Date()
            
            saveToDisk()
        }
    }
    
    func getMetadata(binaryPath: String, address: UInt64) -> FunctionMetadata? {
        let hash = computeHash(for: binaryPath)
        return databases[hash]?.functions[address]
    }
    
    func getAllRenamedFunctions(binaryPath: String) -> [UInt64: String] {
        let hash = computeHash(for: binaryPath)
        guard let db = databases[hash] else { return [:] }
        
        var result: [UInt64: String] = [:]
        for (address, metadata) in db.functions {
            if let name = metadata.customName {
                result[address] = name
            }
        }
        return result
    }
    
    func deleteName(binaryPath: String, address: UInt64) {
        let hash = computeHash(for: binaryPath)
        
        guard var metadata = databases[hash]?.functions[address] else { return }
        metadata.customName = nil
        metadata.lastModified = Date()
        
        databases[hash]!.functions[address] = metadata
        databases[hash]!.lastModified = Date()
        
        saveToDisk()
    }
    
    func clearDatabase(for binaryPath: String) {
        let hash = computeHash(for: binaryPath)
        databases.removeValue(forKey: hash)
        saveToDisk()
    }
    
    func clearAll() {
        databases.removeAll()
        saveToDisk()
    }
    
    // MARK: - Import/Export
    
    func exportDatabase(for binaryPath: String) -> Data? {
        let hash = computeHash(for: binaryPath)
        guard let db = databases[hash] else { return nil }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        return try? encoder.encode(db)
    }
    
    func importDatabase(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let db = try decoder.decode(BinaryDatabase.self, from: data)
        databases[db.binaryHash] = db
        saveToDisk()
    }
    
    func exportAll() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        return try? encoder.encode(databases)
    }
    
    func importAll(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let imported = try decoder.decode([String: BinaryDatabase].self, from: data)
        
        for (hash, db) in imported {
            databases[hash] = db
        }
        
        saveToDisk()
    }
    
    // MARK: - Persistence
    
    private func saveToDisk() {
        guard let url = databaseURL else { return }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(databases)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save function database: \(error)")
        }
    }
    
    private func loadFromDisk() {
        guard let url = databaseURL,
              fileManager.fileExists(atPath: url.path) else {
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let data = try Data(contentsOf: url)
            databases = try decoder.decode([String: BinaryDatabase].self, from: data)
            print("Loaded function database with \(databases.count) binaries")
        } catch {
            print("Failed to load function database: \(error)")
        }
    }
    
    private var databaseURL: URL? {
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let redyneDir = documentsDir.appendingPathComponent("ReDyne", isDirectory: true)
        try? fileManager.createDirectory(at: redyneDir, withIntermediateDirectories: true)
        
        return redyneDir.appendingPathComponent("FunctionDatabase.json")
    }
    
    // MARK: - Hashing
    
    private func computeHash(for binaryPath: String) -> String {
        // use MD5/SHA256 hash of path + file size for identification but maybe later
        guard let attributes = try? fileManager.attributesOfItem(atPath: binaryPath),
              let size = attributes[.size] as? UInt64 else {
            return binaryPath.hashValue.description
        }
        
        let combined = "\(binaryPath)_\(size)"
        return String(combined.hashValue)
    }
    
    // MARK: - Statistics
    
    /// Get statistics for a binary
    func getStatistics(for binaryPath: String) -> (renamedCount: Int, commentCount: Int, tagCount: Int) {
        let hash = computeHash(for: binaryPath)
        guard let db = databases[hash] else { return (0, 0, 0) }
        
        var renamedCount = 0
        var commentCount = 0
        var totalTags = 0
        
        for metadata in db.functions.values {
            if metadata.customName != nil { renamedCount += 1 }
            if metadata.comment != nil { commentCount += 1 }
            totalTags += metadata.tags.count
        }
        
        return (renamedCount, commentCount, totalTags)
    }
}

