import Foundation

// MARK: - Import/Export Types

@objc enum BindType: Int {
    case pointer = 1
    case textAbsolute32 = 2
    case textPCrel32 = 3
}

@objc enum BindFlags: Int {
    case none = 0
    case weakImport = 0x1
    case nonWeakDefinition = 0x8
}

// MARK: - Import Model

@objc class ImportedSymbol: NSObject {
    @objc let name: String
    @objc let libraryName: String
    @objc let libraryOrdinal: Int
    @objc let address: UInt64
    @objc let bindType: BindType
    @objc let isWeak: Bool
    @objc let addend: Int64
    
    init(name: String, libraryName: String, libraryOrdinal: Int, address: UInt64, 
         bindType: BindType, isWeak: Bool, addend: Int64) {
        self.name = name
        self.libraryName = libraryName
        self.libraryOrdinal = libraryOrdinal
        self.address = address
        self.bindType = bindType
        self.isWeak = isWeak
        self.addend = addend
        super.init()
    }
    
    @objc var displayName: String {
        return name.isEmpty ? "(anonymous)" : name
    }
    
    @objc var bindTypeString: String {
        switch bindType {
        case .pointer: return "Pointer"
        case .textAbsolute32: return "Text Absolute 32"
        case .textPCrel32: return "Text PC-rel 32"
        }
    }
    
    @objc var weakIndicator: String {
        return isWeak ? " [weak]" : ""
    }
}

// MARK: - Export Model

@objc class ExportedSymbol: NSObject {
    @objc let name: String
    @objc let address: UInt64
    @objc let flags: UInt64
    @objc let isReexport: Bool
    @objc let reexportLibraryName: String
    @objc let reexportSymbolName: String
    @objc let isWeakDef: Bool
    @objc let isThreadLocal: Bool
    
    init(name: String, address: UInt64, flags: UInt64, 
         isReexport: Bool = false, reexportLibraryName: String = "", reexportSymbolName: String = "",
         isWeakDef: Bool = false, isThreadLocal: Bool = false) {
        self.name = name
        self.address = address
        self.flags = flags
        self.isReexport = isReexport
        self.reexportLibraryName = reexportLibraryName
        self.reexportSymbolName = reexportSymbolName
        self.isWeakDef = isWeakDef
        self.isThreadLocal = isThreadLocal
        super.init()
    }
    
    @objc var displayName: String {
        return name.isEmpty ? "(anonymous)" : name
    }
    
    @objc var exportType: String {
        if isReexport { return "Re-export" }
        if isWeakDef { return "Weak Definition" }
        if isThreadLocal { return "Thread Local" }
        return "Regular"
    }
    
    @objc var fullDescription: String {
        if isReexport {
            return "\(displayName) → \(reexportLibraryName):\(reexportSymbolName)"
        }
        return displayName
    }
}

// MARK: - Import/Export Analysis Result

@objc class ImportExportAnalysis: NSObject {
    @objc let imports: [ImportedSymbol]
    @objc let exports: [ExportedSymbol]
    @objc let linkedLibraries: [String]
    @objc let dependencyAnalysis: DependencyAnalysis?
    
    init(imports: [ImportedSymbol], exports: [ExportedSymbol], linkedLibraries: [String], dependencyAnalysis: DependencyAnalysis? = nil) {
        self.imports = imports
        self.exports = exports
        self.linkedLibraries = linkedLibraries
        self.dependencyAnalysis = dependencyAnalysis
        super.init()
    }
    
    @objc var totalImports: Int { imports.count }
    @objc var totalExports: Int { exports.count }
    @objc var totalLibraries: Int { linkedLibraries.count }
    
    @objc var weakImports: [ImportedSymbol] {
        imports.filter { $0.isWeak }
    }
    
    @objc var reexports: [ExportedSymbol] {
        exports.filter { $0.isReexport }
    }
    
    @objc func imports(from library: String) -> [ImportedSymbol] {
        return imports.filter { $0.libraryName == library }
    }
    
    @objc func exports(matching query: String) -> [ExportedSymbol] {
        guard !query.isEmpty else { return exports }
        let lowercased = query.lowercased()
        return exports.filter { $0.name.lowercased().contains(lowercased) }
    }
}

// MARK: - Helper Extensions

extension Array where Element == ImportedSymbol {
    func groupedByLibrary() -> [String: [ImportedSymbol]] {
        return Dictionary(grouping: self) { $0.libraryName }
    }
    
    func sortedByAddress() -> [ImportedSymbol] {
        return sorted { $0.address < $1.address }
    }
    
    func sortedByName() -> [ImportedSymbol] {
        return sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}

extension Array where Element == ExportedSymbol {
    func sortedByAddress() -> [ExportedSymbol] {
        return sorted { $0.address < $1.address }
    }
    
    func sortedByName() -> [ExportedSymbol] {
        return sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    func filterByType(isReexport: Bool? = nil, isWeakDef: Bool? = nil) -> [ExportedSymbol] {
        return filter { symbol in
            if let reexport = isReexport, symbol.isReexport != reexport { return false }
            if let weakDef = isWeakDef, symbol.isWeakDef != weakDef { return false }
            return true
        }
    }
}

