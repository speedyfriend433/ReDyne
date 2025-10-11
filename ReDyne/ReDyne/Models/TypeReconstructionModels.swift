import Foundation

// MARK: - Supporting Types

struct TypeSymbolInfo {
    let name: String
    let address: UInt64
    let size: UInt64
    let type: String
    let scope: String
    let isExported: Bool
    let isDefined: Bool
    let isExternal: Bool
    let isFunction: Bool
}

struct FunctionInfo {
    let name: String
    let address: UInt64
    let size: UInt64
    let isExported: Bool
}

// MARK: - Core Type System

struct ReconstructedType: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let category: TypeCategory
    let size: Int
    let alignment: Int
    let virtualAddress: UInt64
    let fileOffset: UInt64
    let confidence: Double
    let source: TypeSource
    var properties: [TypeProperty]
    var methods: [TypeMethod]
    let inheritance: [String]
    let protocols: [String]
    let isGeneric: Bool
    let genericParameters: [String]
    let metadata: TypeMetadata
    let createdAt: Date
    let lastModified: Date
    
    init(name: String, category: TypeCategory, size: Int, alignment: Int, virtualAddress: UInt64, fileOffset: UInt64, confidence: Double, source: TypeSource) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.size = size
        self.alignment = alignment
        self.virtualAddress = virtualAddress
        self.fileOffset = fileOffset
        self.confidence = confidence
        self.source = source
        self.properties = []
        self.methods = []
        self.inheritance = []
        self.protocols = []
        self.isGeneric = false
        self.genericParameters = []
        self.metadata = TypeMetadata()
        self.createdAt = Date()
        self.lastModified = Date()
    }
    
    // MARK: - Equatable
    
    static func == (lhs: ReconstructedType, rhs: ReconstructedType) -> Bool {
        return lhs.id == rhs.id
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum TypeCategory: String, Codable, CaseIterable {
    case `struct`
    case `class`
    case `enum`
    case `protocol`
    case `function`
    case `closure`
    case `primitive`
    case `pointer`
    case `array`
    case `dictionary`
    case `tuple`
    case `union`
    case `bitfield`
    case `opaque`
    case `unknown`
    
    var icon: String {
        switch self {
        case .struct: return "📦"
        case .class: return "🏗️"
        case .enum: return "🔢"
        case .protocol: return "📋"
        case .function: return "⚡"
        case .closure: return "🔗"
        case .primitive: return "🔢"
        case .pointer: return "📍"
        case .array: return "📊"
        case .dictionary: return "🗂️"
        case .tuple: return "📋"
        case .union: return "🔀"
        case .bitfield: return "🔧"
        case .opaque: return "❓"
        case .unknown: return "❔"
        }
    }
    
    var displayName: String {
        return rawValue.capitalized
    }
}

enum TypeSource: String, Codable, CaseIterable {
    case staticAnalysis = "static_analysis"
    case symbolTable = "symbol_table"
    case debugInfo = "debug_info"
    case runtimeMetadata = "runtime_metadata"
    case userDefined = "user_defined"
    case inference = "inference"
    case patternMatching = "pattern_matching"
    case crossReference = "cross_reference"
    
    var displayName: String {
        switch self {
        case .staticAnalysis: return "Static Analysis"
        case .symbolTable: return "Symbol Table"
        case .debugInfo: return "Debug Info"
        case .runtimeMetadata: return "Runtime Metadata"
        case .userDefined: return "User Defined"
        case .inference: return "Type Inference"
        case .patternMatching: return "Pattern Matching"
        case .crossReference: return "Cross Reference"
        }
    }
}

struct TypeProperty: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let type: String
    let offset: Int
    let size: Int
    let isOptional: Bool
    let isComputed: Bool
    let isStatic: Bool
    let accessLevel: AccessLevel
    let defaultValue: String?
    let documentation: String?
    
    init(name: String, type: String, offset: Int, size: Int, isOptional: Bool = false, isComputed: Bool = false, isStatic: Bool = false, accessLevel: AccessLevel = .internal) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.offset = offset
        self.size = size
        self.isOptional = isOptional
        self.isComputed = isComputed
        self.isStatic = isStatic
        self.accessLevel = accessLevel
        self.defaultValue = nil
        self.documentation = nil
    }
}

struct TypeMethod: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let signature: String
    let returnType: String
    let parameters: [MethodParameter]
    let virtualAddress: UInt64
    let isStatic: Bool
    let isVirtual: Bool
    let isAbstract: Bool
    let accessLevel: AccessLevel
    let documentation: String?
    
    init(name: String, signature: String, returnType: String, parameters: [MethodParameter], virtualAddress: UInt64, isStatic: Bool = false, isVirtual: Bool = false, isAbstract: Bool = false, accessLevel: AccessLevel = .internal) {
        self.id = UUID()
        self.name = name
        self.signature = signature
        self.returnType = returnType
        self.parameters = parameters
        self.virtualAddress = virtualAddress
        self.isStatic = isStatic
        self.isVirtual = isVirtual
        self.isAbstract = isAbstract
        self.accessLevel = accessLevel
        self.documentation = nil
    }
}

struct MethodParameter: Codable, Hashable {
    let name: String
    let type: String
    let isOptional: Bool
    let hasDefaultValue: Bool
    let defaultValue: String?
    
    init(name: String, type: String, isOptional: Bool = false, hasDefaultValue: Bool = false, defaultValue: String? = nil) {
        self.name = name
        self.type = type
        self.isOptional = isOptional
        self.hasDefaultValue = hasDefaultValue
        self.defaultValue = defaultValue
    }
}

enum AccessLevel: String, Codable, CaseIterable {
    case `public` = "public"
    case `internal` = "internal"
    case `private` = "private"
    case `fileprivate` = "fileprivate"
    case `open` = "open"
    
    var displayName: String {
        return rawValue.capitalized
    }
    
    var icon: String {
        switch self {
        case .public: return "🌐"
        case .internal: return "🏠"
        case .private: return "🔒"
        case .fileprivate: return "📁"
        case .open: return "🔓"
        }
    }
}

struct TypeMetadata: Codable {
    let isFinal: Bool
    let isAbstract: Bool
    let isSealed: Bool
    let isImmutable: Bool
    let memoryLayout: MemoryLayout
    let annotations: [String: String]
    let tags: [String]
    let complexity: TypeComplexity
    let estimatedLinesOfCode: Int
    
    init() {
        self.isFinal = false
        self.isAbstract = false
        self.isSealed = false
        self.isImmutable = false
        self.memoryLayout = MemoryLayout()
        self.annotations = [:]
        self.tags = []
        self.complexity = .simple
        self.estimatedLinesOfCode = 0
    }
}

struct MemoryLayout: Codable {
    let totalSize: Int
    let alignment: Int
    let padding: Int
    let fields: [FieldLayout]
    
    init() {
        self.totalSize = 0
        self.alignment = 1
        self.padding = 0
        self.fields = []
    }
}

struct FieldLayout: Codable {
    let name: String
    let offset: Int
    let size: Int
    let alignment: Int
    let isPacked: Bool
}

enum TypeComplexity: String, Codable, CaseIterable {
    case simple = "simple"
    case moderate = "moderate"
    case complex = "complex"
    case veryComplex = "very_complex"
    
    var displayName: String {
        switch self {
        case .simple: return "Simple"
        case .moderate: return "Moderate"
        case .complex: return "Complex"
        case .veryComplex: return "Very Complex"
        }
    }
    
    var icon: String {
        switch self {
        case .simple: return "🟢"
        case .moderate: return "🟡"
        case .complex: return "🟠"
        case .veryComplex: return "🔴"
        }
    }
}

// MARK: - Type Analysis Results

struct TypeReconstructionResults: Codable {
    let types: [ReconstructedType]
    let statistics: TypeStatistics
    let metadata: TypeMetadata
    
    init(types: [ReconstructedType], statistics: TypeStatistics, metadata: TypeMetadata) {
        self.types = types
        self.statistics = statistics
        self.metadata = metadata
    }
}

struct TypeStatistics: Codable {
    let totalTypes: Int
    let byCategory: [TypeCategory: Int]
    let bySource: [TypeSource: Int]
    let averageConfidence: Double
    let totalProperties: Int
    let totalMethods: Int
    let averageSize: Double
    let largestType: String?
    let mostComplexType: String?
    
    init(types: [ReconstructedType]) {
        self.totalTypes = types.count
        self.byCategory = Dictionary(grouping: types, by: { $0.category }).mapValues { $0.count }
        self.bySource = Dictionary(grouping: types, by: { $0.source }).mapValues { $0.count }
        self.averageConfidence = types.isEmpty ? 0.0 : types.map { $0.confidence }.reduce(0, +) / Double(types.count)
        self.totalProperties = types.flatMap { $0.properties }.count
        self.totalMethods = types.flatMap { $0.methods }.count
        self.averageSize = types.isEmpty ? 0.0 : Double(types.map { $0.size }.reduce(0, +)) / Double(types.count)
        self.largestType = types.max(by: { $0.size < $1.size })?.name
        self.mostComplexType = types.max(by: { $0.metadata.complexity.rawValue < $1.metadata.complexity.rawValue })?.name
    }
}

// MARK: - Type Inference Patterns

struct TypeInferencePattern: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let pattern: String
    let confidence: Double
    let category: TypeCategory
    let examples: [String]
    let isEnabled: Bool
    
    init(name: String, description: String, pattern: String, confidence: Double, category: TypeCategory, examples: [String] = []) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.pattern = pattern
        self.confidence = confidence
        self.category = category
        self.examples = examples
        self.isEnabled = true
    }
}

// MARK: - Type Export/Import

enum TypeExportFormat: String, CaseIterable, Codable {
    case swift = "swift"
    case objectiveC = "objectivec"
    case c = "c"
    case cpp = "cpp"
    case json = "json"
    case xml = "xml"
    
    var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .objectiveC: return "Objective-C"
        case .c: return "C"
        case .cpp: return "C++"
        case .json: return "JSON"
        case .xml: return "XML"
        }
    }
    
    var fileExtension: String {
        return rawValue
    }
}

struct TypeDefinitionExport: Codable {
    let format: TypeExportFormat
    let types: [ReconstructedType]
    let exportDate: Date
    let version: String
    let metadata: [String: String]
    
    init(format: TypeExportFormat, types: [ReconstructedType]) {
        self.format = format
        self.types = types
        self.exportDate = Date()
        self.version = "1.0"
        self.metadata = [:]
    }
}
