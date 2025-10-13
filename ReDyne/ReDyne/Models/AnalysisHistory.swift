import Foundation

struct AnalysisHistoryEntry: Codable, Identifiable {
    let id: UUID
    let binaryPath: String
    let binaryName: String
    let analysisDate: Date
    let fileSize: UInt64
    var totalInstructions: UInt
    var totalSymbols: UInt
    var totalStrings: UInt
    var totalFunctions: UInt
    var architecture: String
    var uuid: String?
    var hasObjCClasses: Bool
    var hasCodeSignature: Bool
    var totalXrefs: UInt
    var originalFileName: String?
    var fileHash: String?
    
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: analysisDate, relativeTo: Date())
    }
    
    init(id: UUID = UUID(),
         binaryPath: String,
         binaryName: String,
         analysisDate: Date = Date(),
         fileSize: UInt64,
         totalInstructions: UInt = 0,
         totalSymbols: UInt = 0,
         totalStrings: UInt = 0,
         totalFunctions: UInt = 0,
         architecture: String = "Unknown",
         uuid: String? = nil,
         hasObjCClasses: Bool = false,
         hasCodeSignature: Bool = false,
         totalXrefs: UInt = 0,
         originalFileName: String? = nil,
         fileHash: String? = nil) {
        self.id = id
        self.binaryPath = binaryPath
        self.binaryName = binaryName
        self.analysisDate = analysisDate
        self.fileSize = fileSize
        self.totalInstructions = totalInstructions
        self.totalSymbols = totalSymbols
        self.totalStrings = totalStrings
        self.totalFunctions = totalFunctions
        self.architecture = architecture
        self.uuid = uuid
        self.hasObjCClasses = hasObjCClasses
        self.hasCodeSignature = hasCodeSignature
        self.totalXrefs = totalXrefs
        self.originalFileName = originalFileName
        self.fileHash = fileHash
    }
}

class AnalysisHistoryManager {
    static let shared = AnalysisHistoryManager()
    
    private let storageKey = "com.jian.ReDyne.analysisHistory"
    private let maxHistoryEntries = 50
    
    private init() {}
    
    func addAnalysis(from output: DecompiledOutput, binaryPath: String) {
        var history = getHistory()
        
        let originalFileName = (binaryPath as NSString).lastPathComponent
        
        if let existingIndex = history.firstIndex(where: { 
            $0.binaryPath == binaryPath || 
            ($0.binaryName == originalFileName && $0.fileSize == output.fileSize)
        }) {
            var existingEntry = history[existingIndex]
            history.remove(at: existingIndex)
            
            let updatedEntry = AnalysisHistoryEntry(
                id: existingEntry.id,
                binaryPath: binaryPath,
                binaryName: originalFileName,
                analysisDate: Date(),
                fileSize: output.fileSize,
                totalInstructions: output.totalInstructions,
                totalSymbols: output.totalSymbols,
                totalStrings: output.totalStrings,
                totalFunctions: output.totalFunctions,
                architecture: output.header.cpuType,
                uuid: output.header.uuid,
                hasObjCClasses: output.totalObjCClasses > 0,
                hasCodeSignature: output.codeSigningAnalysis != nil,
                totalXrefs: output.totalXrefs,
                originalFileName: existingEntry.originalFileName ?? originalFileName,
                fileHash: existingEntry.fileHash
            )
            
            history.insert(updatedEntry, at: 0)
        } else {
            let entry = AnalysisHistoryEntry(
                binaryPath: binaryPath,
                binaryName: originalFileName,
                fileSize: output.fileSize,
                totalInstructions: output.totalInstructions,
                totalSymbols: output.totalSymbols,
                totalStrings: output.totalStrings,
                totalFunctions: output.totalFunctions,
                architecture: output.header.cpuType,
                uuid: output.header.uuid,
                hasObjCClasses: output.totalObjCClasses > 0,
                hasCodeSignature: output.codeSigningAnalysis != nil,
                totalXrefs: output.totalXrefs,
                originalFileName: originalFileName,
                fileHash: nil // add file hash calculation in the future...........
            )
            
            history.insert(entry, at: 0)
        }
        
        if history.count > maxHistoryEntries {
            history = Array(history.prefix(maxHistoryEntries))
        }
        
        saveHistory(history)
    }
    
    func getHistory() -> [AnalysisHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            return try decoder.decode([AnalysisHistoryEntry].self, from: data)
        } catch {
            ErrorHandler.log(error)
            return []
        }
    }
    
    func removeEntry(with id: UUID) {
        var history = getHistory()
        history.removeAll { $0.id == id }
        saveHistory(history)
    }
    
    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    
    func search(query: String) -> [AnalysisHistoryEntry] {
        guard !query.isEmpty else { return getHistory() }
        
        let lowercased = query.lowercased()
        return getHistory().filter {
            $0.binaryName.lowercased().contains(lowercased) ||
            $0.architecture.lowercased().contains(lowercased)
        }
    }
    
    func findMovedFile(for entry: AnalysisHistoryEntry) -> String? {
        if FileManager.default.fileExists(atPath: entry.binaryPath) {
            return entry.binaryPath
        }
        
        let commonDirectories = [
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path,
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path,
            FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
        ].compactMap { $0 }
        
        let searchName = entry.originalFileName ?? entry.binaryName
        
        for directory in commonDirectories {
            let enumerator = FileManager.default.enumerator(atPath: directory)
            while let filePath = enumerator?.nextObject() as? String {
                if filePath.hasSuffix(searchName) {
                    let fullPath = (directory as NSString).appendingPathComponent(filePath)
                    if FileManager.default.fileExists(atPath: fullPath) {
                        // Verify it's the same file by size & potentially hash in future after 1000 years
                        if let attributes = try? FileManager.default.attributesOfItem(atPath: fullPath),
                           let fileSize = attributes[.size] as? UInt64,
                           fileSize == entry.fileSize {
                            return fullPath
                        }
                    }
                }
            }
        }
        
        if let uuid = entry.uuid {
            for directory in commonDirectories {
                let enumerator = FileManager.default.enumerator(atPath: directory)
                while let filePath = enumerator?.nextObject() as? String {
                    let fullPath = (directory as NSString).appendingPathComponent(filePath)
                    if FileManager.default.fileExists(atPath: fullPath) {
                        //add UUID-based matching in the future idk when will it gonna be lol
                        if let attributes = try? FileManager.default.attributesOfItem(atPath: fullPath),
                           let fileSize = attributes[.size] as? UInt64,
                           fileSize == entry.fileSize {
                            return fullPath
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    private func saveHistory(_ history: [AnalysisHistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(history)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            ErrorHandler.log(error)
        }
    }
}


