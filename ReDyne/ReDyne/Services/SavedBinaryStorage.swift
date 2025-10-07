import Foundation

final class SavedBinaryStorage {
    static let shared = SavedBinaryStorage()
    
    private let fileManager = FileManager.default
    private init() {
        try? createStorageDirectoryIfNeeded()
    }
    
    // MARK: - Public API
    
    func storageDirectoryURL() throws -> URL {
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documentsURL.appendingPathComponent(Constants.File.savedBinariesDirectoryName, isDirectory: true)
    }
    
    @discardableResult
    func importBinary(from sourceURL: URL, preferredName: String? = nil) throws -> URL {
        try createStorageDirectoryIfNeeded()
        
        let storageURL = try storageDirectoryURL()
        let standardizedSource = sourceURL.standardizedFileURL
        
        if isFileInStorage(standardizedSource) {
            return standardizedSource
        }
        
        let fileName = sanitizeFileName(preferredName ?? standardizedSource.lastPathComponent)
        var destinationURL = storageURL.appendingPathComponent(fileName)
        destinationURL = makeUniqueURL(for: destinationURL)
        
        try fileManager.copyItem(at: standardizedSource, to: destinationURL)
        try excludeFromBackup(destinationURL)
        
        cleanupTemporaryCopyIfNeeded(at: standardizedSource)
        
        return destinationURL
    }
    
    func deleteBinary(at url: URL) throws {
        guard isFileInStorage(url) else { return }
        try fileManager.removeItem(at: url)
    }
    
    func listSavedBinaries() -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: (try? storageDirectoryURL()) ?? URL(fileURLWithPath: "/"),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        
        return urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
    }
    
    func isFileInStorage(_ url: URL) -> Bool {
        guard let storageURL = try? storageDirectoryURL() else { return false }
        let standardizedStoragePath = storageURL.standardizedFileURL.path
        let standardizedPath = url.standardizedFileURL.path
        return standardizedPath.hasPrefix(standardizedStoragePath)
    }
    
    // MARK: - Private Helpers
    
    private func createStorageDirectoryIfNeeded() throws {
        let storageURL = try storageDirectoryURL()
        if !fileManager.fileExists(atPath: storageURL.path) {
            try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        }
    }
    
    private func makeUniqueURL(for url: URL) -> URL {
        var candidateURL = url
        let pathExtension = candidateURL.pathExtension
        let baseName = candidateURL.deletingPathExtension().lastPathComponent
        var attempt = 1
        
        while fileManager.fileExists(atPath: candidateURL.path) {
            let newName: String
            if pathExtension.isEmpty {
                newName = "\(baseName)-\(attempt)"
            } else {
                newName = "\(baseName)-\(attempt).\(pathExtension)"
            }
            candidateURL = candidateURL.deletingLastPathComponent().appendingPathComponent(newName)
            attempt += 1
        }
        
        return candidateURL
    }
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        if sanitized.isEmpty {
            return "binary.dylib"
        }
        return sanitized
    }
    
    private func excludeFromBackup(_ url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }
    
    private func cleanupTemporaryCopyIfNeeded(at url: URL) {
        let path = url.standardizedFileURL.path
        guard path.contains("-Inbox/") || path.contains("/tmp/") else { return }
        try? fileManager.removeItem(at: url)
    }
}
