import Foundation

// MARK: - Cache Data Structure

struct DecompiledOutputCache: Codable {
    let classDumpOutput: String?
    let dyldInfo: String?
    let imports: String?
    let swiftMetadata: String?
    let objcMetadata: String?
    
    // File metadata
    let filePath: String?
    let fileName: String?
    let fileSize: UInt64?
    let processingDate: Date?
    let processingTime: TimeInterval?
    
    // Statistics
    let totalInstructions: UInt?
    let totalSymbols: UInt?
    let totalStrings: UInt?
    let totalFunctions: UInt?
    let definedSymbols: UInt?
    let undefinedSymbols: UInt?
    let totalXrefs: UInt?
    let totalCalls: UInt?
    let totalObjCClasses: UInt?
    let totalObjCMethods: UInt?
    let totalImports: UInt?
    let totalExports: UInt?
    let totalLinkedLibraries: UInt?
}

// MARK: - AnalysisCache

class AnalysisCache {
    static let shared = AnalysisCache()
    
    private let cacheDirectory: URL
    private let maxCacheSize: Int = 100 * 1024 * 1024
    private var memoryCache: [String: DecompiledOutput] = [:]
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDirectory = documentsPath.appendingPathComponent("AnalysisCache", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        cleanupOldCache()
    }
    
    // MARK: - Public API
    
    func save(_ output: DecompiledOutput, for path: String) {
        memoryCache[path] = output
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.saveToDisk(output, for: path)
        }
    }
    
    func load(for path: String) -> DecompiledOutput? {
        if let cached = memoryCache[path] {
            print("AnalysisCache: Loaded from memory for \(path)")
            return cached
        }
        
        if let output = loadFromDisk(for: path) {
            print("AnalysisCache: Loaded from disk for \(path)")
            memoryCache[path] = output
            return output
        }
        
        print("AnalysisCache: No cache found for \(path)")
        return nil
    }
    
    func remove(for path: String) {
        memoryCache.removeValue(forKey: path)
        
        let cacheFile = cacheURL(for: path)
        try? FileManager.default.removeItem(at: cacheFile)
    }
    
    func clearAll() {
        memoryCache.removeAll()
        
        if let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func cacheURL(for path: String) -> URL {
        let hash = path.hashValue
        return cacheDirectory.appendingPathComponent("cache_\(hash).dat")
    }
    
    private func saveToDisk(_ output: DecompiledOutput, for path: String) {
        let cacheFile = cacheURL(for: path)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            let cacheData = DecompiledOutputCache(
                classDumpOutput: nil, // Not available in DecompiledOutput
                dyldInfo: nil, // Not available in DecompiledOutput
                imports: output.importExportAnalysis as? String,
                swiftMetadata: nil, // Not available in DecompiledOutput
                objcMetadata: output.objcAnalysis as? String,
                filePath: output.filePath,
                fileName: output.fileName,
                fileSize: output.fileSize,
                processingDate: output.processingDate,
                processingTime: output.processingTime,
                totalInstructions: UInt(output.totalInstructions),
                totalSymbols: UInt(output.totalSymbols),
                totalStrings: UInt(output.totalStrings),
                totalFunctions: UInt(output.totalFunctions),
                definedSymbols: UInt(output.definedSymbols),
                undefinedSymbols: UInt(output.undefinedSymbols),
                totalXrefs: UInt(output.totalXrefs),
                totalCalls: UInt(output.totalCalls),
                totalObjCClasses: UInt(output.totalObjCClasses),
                totalObjCMethods: UInt(output.totalObjCMethods),
                totalImports: UInt(output.totalImports),
                totalExports: UInt(output.totalExports),
                totalLinkedLibraries: UInt(output.totalLinkedLibraries)
            )
            
            let data = try encoder.encode(cacheData)
            try data.write(to: cacheFile)
            print("AnalysisCache: Saved to disk for \(path) (\(data.count / 1024) KB)")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.checkCacheSize()
            }
            
        } catch {
            print("AnalysisCache: Failed to save to disk: \(error)")
        }
    }
    
    private func loadFromDisk(for path: String) -> DecompiledOutput? {
        let cacheFile = cacheURL(for: path)
        
        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            let cacheData = try decoder.decode(DecompiledOutputCache.self, from: data)
            
            let output = DecompiledOutput()
            
            // Note: Complex Objective-C objects (header, segments, etc.) are not cached
            // They will be regenerated when needed, but the expensive analysis results are cached
            
            // Restore analysis outputs
            // Note: classDumpOutput, dyldInfo, and swiftMetadata are not available in DecompiledOutput
            output.importExportAnalysis = cacheData.imports as NSString?
            output.objcAnalysis = cacheData.objcMetadata as NSString?
            
            // Restore file metadata
            output.filePath = cacheData.filePath ?? ""
            output.fileName = cacheData.fileName ?? "Unknown"
            output.fileSize = cacheData.fileSize ?? 0
            output.processingDate = cacheData.processingDate ?? Date()
            output.processingTime = cacheData.processingTime ?? 0
            
            // Restore statistics
            output.totalInstructions = UInt(cacheData.totalInstructions ?? 0)
            output.totalSymbols = UInt(cacheData.totalSymbols ?? 0)
            output.totalStrings = UInt(cacheData.totalStrings ?? 0)
            output.totalFunctions = UInt(cacheData.totalFunctions ?? 0)
            output.definedSymbols = UInt(cacheData.definedSymbols ?? 0)
            output.undefinedSymbols = UInt(cacheData.undefinedSymbols ?? 0)
            output.totalXrefs = UInt(cacheData.totalXrefs ?? 0)
            output.totalCalls = UInt(cacheData.totalCalls ?? 0)
            output.totalObjCClasses = UInt(cacheData.totalObjCClasses ?? 0)
            output.totalObjCMethods = UInt(cacheData.totalObjCMethods ?? 0)
            output.totalImports = UInt(cacheData.totalImports ?? 0)
            output.totalExports = UInt(cacheData.totalExports ?? 0)
            output.totalLinkedLibraries = UInt(cacheData.totalLinkedLibraries ?? 0)
            
            print("AnalysisCache: Loaded from disk for \(path) (\(data.count / 1024) KB)")
            return output
            
        } catch {
            print("AnalysisCache: Failed to load from disk: \(error)")
            return nil
        }
    }
    
    private func checkCacheSize() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]) else {
            return
        }
        
        var totalSize: Int64 = 0
        var fileInfos: [(url: URL, size: Int64, date: Date)] = []
        
        for file in files {
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            let size = attributes?[.size] as? Int64 ?? 0
            let date = attributes?[.creationDate] as? Date ?? Date.distantPast
            
            totalSize += size
            fileInfos.append((file, size, date))
        }
        
        if totalSize > maxCacheSize {
            let sorted = fileInfos.sorted { $0.date < $1.date }
            
            for fileInfo in sorted {
                try? FileManager.default.removeItem(at: fileInfo.url)
                totalSize -= fileInfo.size
                
                if totalSize <= maxCacheSize {
                    break
                }
            }
            
            print("AnalysisCache: Cleaned up cache (total: \(totalSize / 1024 / 1024) MB)")
        }
    }
    
    private func cleanupOldCache() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }
        
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        for file in files {
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            let creationDate = attributes?[.creationDate] as? Date ?? Date.distantPast
            
            if creationDate < sevenDaysAgo {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}


