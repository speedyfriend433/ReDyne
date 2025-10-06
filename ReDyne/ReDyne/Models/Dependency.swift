import Foundation

// MARK: - Dependency Model

@objc class LinkedLibrary: NSObject {
    @objc let path: String
    @objc let timestamp: UInt32
    @objc let currentVersion: UInt32
    @objc let compatibilityVersion: UInt32
    @objc let isWeak: Bool
    @objc let isReexport: Bool
    
    init(path: String, timestamp: UInt32, currentVersion: UInt32, 
         compatibilityVersion: UInt32, isWeak: Bool = false, isReexport: Bool = false) {
        self.path = path
        self.timestamp = timestamp
        self.currentVersion = currentVersion
        self.compatibilityVersion = compatibilityVersion
        self.isWeak = isWeak
        self.isReexport = isReexport
        super.init()
    }
    
    @objc var name: String {
        return path.components(separatedBy: "/").last ?? path
    }
    
    @objc var currentVersionString: String {
        let major = (currentVersion >> 16) & 0xFFFF
        let minor = (currentVersion >> 8) & 0xFF
        let patch = currentVersion & 0xFF
        return "\(major).\(minor).\(patch)"
    }
    
    @objc var compatibilityVersionString: String {
        let major = (compatibilityVersion >> 16) & 0xFFFF
        let minor = (compatibilityVersion >> 8) & 0xFF
        let patch = compatibilityVersion & 0xFF
        return "\(major).\(minor).\(patch)"
    }
    
    @objc var timestampDate: Date? {
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    
    @objc var timestampString: String {
        guard let date = timestampDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    @objc var libraryType: String {
        if isWeak { return "Weak" }
        if isReexport { return "Re-export" }
        return "Regular"
    }
    
    @objc var isSystemLibrary: Bool {
        return path.hasPrefix("/usr/lib/") || 
               path.hasPrefix("/System/Library/") ||
               path.contains("Frameworks")
    }
    
    @objc var framework: String? {
        if path.contains(".framework/") {
            let components = path.components(separatedBy: ".framework/")
            if let frameworkPath = components.first {
                return frameworkPath.components(separatedBy: "/").last
            }
        }
        return nil
    }
}

// MARK: - Dependency Analysis Result

@objc class DependencyAnalysis: NSObject {
    @objc let libraries: [LinkedLibrary]
    
    init(libraries: [LinkedLibrary]) {
        self.libraries = libraries
        super.init()
    }
    
    @objc var totalLibraries: Int { libraries.count }
    
    @objc var systemLibraries: [LinkedLibrary] {
        return libraries.filter { $0.isSystemLibrary }
    }
    
    @objc var customLibraries: [LinkedLibrary] {
        return libraries.filter { !$0.isSystemLibrary }
    }
    
    @objc var weakLibraries: [LinkedLibrary] {
        return libraries.filter { $0.isWeak }
    }
    
    @objc var reexportLibraries: [LinkedLibrary] {
        return libraries.filter { $0.isReexport }
    }
    
    @objc var frameworks: [LinkedLibrary] {
        return libraries.filter { $0.framework != nil }
    }
    
    @objc func libraries(matching query: String) -> [LinkedLibrary] {
        guard !query.isEmpty else { return libraries }
        let lowercased = query.lowercased()
        return libraries.filter { 
            $0.path.lowercased().contains(lowercased) || 
            $0.name.lowercased().contains(lowercased)
        }
    }
}

// MARK: - Helper Extensions

extension Array where Element == LinkedLibrary {
    func sortedByName() -> [LinkedLibrary] {
        return sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    func sortedByPath() -> [LinkedLibrary] {
        return sorted { $0.path.lowercased() < $1.path.lowercased() }
    }
    
    func groupedByType() -> [String: [LinkedLibrary]] {
        return Dictionary(grouping: self) { library in
            if library.isWeak { return "Weak" }
            if library.isReexport { return "Re-export" }
            if library.isSystemLibrary { return "System" }
            return "Custom"
        }
    }
}

