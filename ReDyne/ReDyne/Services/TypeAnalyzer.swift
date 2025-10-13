import Foundation

class TypeAnalyzer {
    
    // MARK: - Properties
    
    private let binaryPath: String
    private let architecture: String
    private let symbolTable: [TypeSymbolInfo]
    private let strings: [String]
    private let functions: [FunctionModel]
    private let crossReferences: [CrossReference]
    
    // MARK: - Initialization
    
    init(binaryPath: String, architecture: String, symbolTable: [TypeSymbolInfo], strings: [String], functions: [FunctionModel], crossReferences: [CrossReference]) {
        self.binaryPath = binaryPath
        self.architecture = architecture
        self.symbolTable = symbolTable
        self.strings = strings
        self.functions = functions
        self.crossReferences = crossReferences
    }
    
    // MARK: - Public Interface
    
    func analyzeTypes() -> TypeReconstructionResults {
        var reconstructedTypes: [ReconstructedType] = []
        
        let symbolTypes = analyzeSymbolTable()
        reconstructedTypes.append(contentsOf: symbolTypes)
        
        let debugTypes = analyzeDebugInformation()
        reconstructedTypes.append(contentsOf: debugTypes)
        
        let runtimeTypes = analyzeRuntimeMetadata()
        reconstructedTypes.append(contentsOf: runtimeTypes)
        
        let inferredTypes = performPatternInference()
        reconstructedTypes.append(contentsOf: inferredTypes)
        
        let xrefTypes = analyzeCrossReferences()
        reconstructedTypes.append(contentsOf: xrefTypes)
        
        let mergedTypes = mergeAndDeduplicateTypes(reconstructedTypes)
        
        let statistics = TypeStatistics(types: mergedTypes)
        
        let metadata = TypeMetadata()
        
        return TypeReconstructionResults(
            types: mergedTypes,
            statistics: statistics,
            metadata: metadata
        )
    }
    
    // MARK: - Symbol Table Analysis
    
    private func analyzeSymbolTable() -> [ReconstructedType] {
        var types: [ReconstructedType] = []
        
        // Group symbols by type for better analysis
        let classSymbols = symbolTable.filter { isClassSymbol($0.name) }
        let structSymbols = symbolTable.filter { isStructSymbol($0.name) }
        let enumSymbols = symbolTable.filter { isEnumSymbol($0.name) }
        let functionSymbols = symbolTable.filter { isFunctionSymbol($0.name) }
        
        // Analyze classes with their methods and properties
        for symbol in classSymbols {
            if let type = analyzeClassSymbol(symbol) {
                types.append(type)
            }
        }
        
        // Analyze structs
        for symbol in structSymbols {
            if let type = analyzeStructSymbol(symbol) {
                types.append(type)
            }
        }
        
        // Analyze enums
        for symbol in enumSymbols {
            if let type = analyzeEnumSymbol(symbol) {
                types.append(type)
            }
        }
        
        // Analyze functions
        for symbol in functionSymbols {
            if let type = analyzeFunctionSymbol(symbol) {
                types.append(type)
            }
        }
        
        return types
    }
    
    // MARK: - Real Symbol Analysis Methods
    
    private func analyzeClassSymbol(_ symbol: TypeSymbolInfo) -> ReconstructedType? {
        let className = extractClassName(from: symbol.name)
        var type = ReconstructedType(
            name: className,
            category: .class,
            size: estimateClassSize(className),
            alignment: 8,
            virtualAddress: symbol.address,
            fileOffset: 0,
            confidence: 0.8,
            source: .symbolTable
        )
        
        // Find related methods and properties
        let relatedSymbols = findRelatedSymbols(for: className)
        type.properties = extractProperties(from: relatedSymbols, className: className)
        type.methods = extractMethods(from: relatedSymbols, className: className)
        
        return type
    }
    
    private func analyzeStructSymbol(_ symbol: TypeSymbolInfo) -> ReconstructedType? {
        let structName = extractStructName(from: symbol.name)
        var type = ReconstructedType(
            name: structName,
            category: .struct,
            size: estimateStructSize(structName),
            alignment: 4,
            virtualAddress: symbol.address,
            fileOffset: 0,
            confidence: 0.7,
            source: .symbolTable
        )
        
        // Find related symbols for structs
        let relatedSymbols = findRelatedSymbols(for: structName)
        type.properties = extractProperties(from: relatedSymbols, className: structName)
        type.methods = extractMethods(from: relatedSymbols, className: structName)
        
        return type
    }
    
    private func analyzeEnumSymbol(_ symbol: TypeSymbolInfo) -> ReconstructedType? {
        let enumName = extractEnumName(from: symbol.name)
        var type = ReconstructedType(
            name: enumName,
            category: .enum,
            size: estimateEnumSize(enumName),
            alignment: 4,
            virtualAddress: symbol.address,
            fileOffset: 0,
            confidence: 0.6,
            source: .symbolTable
        )
        
        // Find enum cases and methods
        let relatedSymbols = findRelatedSymbols(for: enumName)
        type.properties = extractEnumCases(from: relatedSymbols, enumName: enumName)
        type.methods = extractMethods(from: relatedSymbols, className: enumName)
        
        return type
    }
    
    private func analyzeFunctionSymbol(_ symbol: TypeSymbolInfo) -> ReconstructedType? {
        let functionName = extractFunctionName(from: symbol.name)
        var type = ReconstructedType(
            name: functionName,
            category: .function,
            size: 0,
            alignment: 1,
            virtualAddress: symbol.address,
            fileOffset: 0,
            confidence: 0.9,
            source: .symbolTable
        )
        
        // Extract function signature and parameters
        type.methods = [extractFunctionSignature(from: symbol, functionName: functionName)]
        
        return type
    }
    
    // MARK: - Real Property and Method Extraction
    
    private func findRelatedSymbols(for typeName: String) -> [TypeSymbolInfo] {
        return symbolTable.filter { symbol in
            let name = symbol.name.lowercased()
            let searchName = typeName.lowercased()
            
            // Look for symbols that contain the type name
            return name.contains(searchName) || 
                   name.contains("_\(searchName)_") ||
                   name.hasPrefix("\(searchName)_") ||
                   name.hasSuffix("_\(searchName)")
        }
    }
    
    private func extractProperties(from symbols: [TypeSymbolInfo], className: String) -> [TypeProperty] {
        var properties: [TypeProperty] = []
        
        for symbol in symbols {
            let name = symbol.name
            
            // Look for property-like symbols
            if isPropertySymbol(name, className: className) {
                let propertyName = extractPropertyName(from: name, className: className)
                let propertyType = inferPropertyType(from: name, symbol: symbol)
                
                properties.append(TypeProperty(
                    name: propertyName,
                    type: propertyType,
                    offset: 0, // Would need more complex analysis for real offset
                    size: Int(symbol.size),
                    isOptional: propertyType.contains("?"),
                    accessLevel: inferAccessLevel(from: name)
                ))
            }
        }
        
        return properties
    }
    
    private func extractMethods(from symbols: [TypeSymbolInfo], className: String) -> [TypeMethod] {
        var methods: [TypeMethod] = []
        
        for symbol in symbols {
            let name = symbol.name
            
            // Look for method-like symbols
            if isMethodSymbol(name, className: className) {
                let methodName = extractMethodName(from: name, className: className)
                let signature = extractMethodSignature(from: name, symbol: symbol)
                let returnType = inferReturnType(from: name, symbol: symbol)
                let parameters = extractMethodParameters(from: name, symbol: symbol)
                
                methods.append(TypeMethod(
                    name: methodName,
                    signature: signature,
                    returnType: returnType,
                    parameters: parameters,
                    virtualAddress: symbol.address,
                    accessLevel: inferAccessLevel(from: name)
                ))
            }
        }
        
        return methods
    }
    
    private func extractEnumCases(from symbols: [TypeSymbolInfo], enumName: String) -> [TypeProperty] {
        var cases: [TypeProperty] = []
        
        for symbol in symbols {
            let name = symbol.name
            
            // Look for enum case symbols
            if isEnumCaseSymbol(name, enumName: enumName) {
                let caseName = extractEnumCaseName(from: name, enumName: enumName)
                
                cases.append(TypeProperty(
                    name: caseName,
                    type: enumName,
                    offset: 0,
                    size: Int(symbol.size),
                    isOptional: false,
                    accessLevel: .public
                ))
            }
        }
        
        return cases
    }
    
    // MARK: - Symbol Classification Helpers
    
    private func isPropertySymbol(_ name: String, className: String) -> Bool {
        let lowerName = name.lowercased()
        let lowerClassName = className.lowercased()
        
        return lowerName.contains("_\(lowerClassName)_") &&
               (lowerName.contains("property") || 
                lowerName.contains("field") ||
                lowerName.contains("member") ||
                lowerName.contains("ivar"))
    }
    
    private func isMethodSymbol(_ name: String, className: String) -> Bool {
        let lowerName = name.lowercased()
        let lowerClassName = className.lowercased()
        
        return lowerName.contains("_\(lowerClassName)_") &&
               (lowerName.contains("method") || 
                lowerName.contains("func") ||
                lowerName.contains("selector") ||
                lowerName.contains("imp"))
    }
    
    private func isEnumCaseSymbol(_ name: String, enumName: String) -> Bool {
        let lowerName = name.lowercased()
        let lowerEnumName = enumName.lowercased()
        
        return lowerName.contains("_\(lowerEnumName)_") &&
               (lowerName.contains("case") || 
                lowerName.contains("value") ||
                lowerName.contains("option"))
    }
    
    // MARK: - Name Extraction Helpers
    
    private func extractPropertyName(from name: String, className: String) -> String {
        // Extract property name from symbol name
        let components = name.components(separatedBy: "_")
        if let lastComponent = components.last, !lastComponent.isEmpty {
            return lastComponent
        }
        return "property"
    }
    
    private func extractMethodName(from name: String, className: String) -> String {
        // Extract method name from symbol name
        let components = name.components(separatedBy: "_")
        if let lastComponent = components.last, !lastComponent.isEmpty {
            return lastComponent
        }
        return "method"
    }
    
    private func extractEnumCaseName(from name: String, enumName: String) -> String {
        // Extract enum case name from symbol name
        let components = name.components(separatedBy: "_")
        if let lastComponent = components.last, !lastComponent.isEmpty {
            return lastComponent
        }
        return "case"
    }
    
    // MARK: - Type Inference Helpers
    
    private func inferPropertyType(from name: String, symbol: TypeSymbolInfo) -> String {
        let lowerName = name.lowercased()
        
        if lowerName.contains("string") || lowerName.contains("str") {
            return "String"
        } else if lowerName.contains("int") || lowerName.contains("number") {
            return "Int"
        } else if lowerName.contains("bool") || lowerName.contains("flag") {
            return "Bool"
        } else if lowerName.contains("float") || lowerName.contains("double") {
            return "Double"
        } else if lowerName.contains("array") || lowerName.contains("list") {
            return "[Any]"
        } else if lowerName.contains("dict") || lowerName.contains("map") {
            return "[String: Any]"
        } else if symbol.size == 8 {
            return "Int64"
        } else if symbol.size == 4 {
            return "Int32"
        } else if symbol.size == 2 {
            return "Int16"
        } else if symbol.size == 1 {
            return "Int8"
        } else {
            return "Any"
        }
    }
    
    private func inferReturnType(from name: String, symbol: TypeSymbolInfo) -> String {
        let lowerName = name.lowercased()
        
        if lowerName.contains("init") || lowerName.contains("alloc") {
            return "Self"
        } else if lowerName.contains("bool") || lowerName.contains("flag") {
            return "Bool"
        } else if lowerName.contains("string") || lowerName.contains("str") {
            return "String"
        } else if lowerName.contains("int") || lowerName.contains("number") {
            return "Int"
        } else if lowerName.contains("void") || lowerName.contains("empty") {
            return "Void"
        } else {
            return "Any"
        }
    }
    
    private func inferAccessLevel(from name: String) -> AccessLevel {
        let lowerName = name.lowercased()
        
        if lowerName.contains("private") || lowerName.contains("_private") {
            return .private
        } else if lowerName.contains("fileprivate") || lowerName.contains("_fileprivate") {
            return .fileprivate
        } else if lowerName.contains("internal") || lowerName.contains("_internal") {
            return .internal
        } else if lowerName.contains("open") || lowerName.contains("_open") {
            return .open
        } else {
            return .public
        }
    }
    
    private func extractMethodSignature(from name: String, symbol: TypeSymbolInfo) -> String {
        let methodName = extractMethodName(from: name, className: "")
        let parameters = extractMethodParameters(from: name, symbol: symbol)
        
        if parameters.isEmpty {
            return "\(methodName)()"
        } else {
            let paramString = parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
            return "\(methodName)(\(paramString))"
        }
    }
    
    private func extractMethodParameters(from name: String, symbol: TypeSymbolInfo) -> [MethodParameter] {
        // This is a simplified implementation
        // In a real implementation, you'd parse the actual function signature
        var parameters: [MethodParameter] = []
        
        let lowerName = name.lowercased()
        
        if lowerName.contains("with") {
            parameters.append(MethodParameter(name: "value", type: "Any"))
        }
        if lowerName.contains("for") {
            parameters.append(MethodParameter(name: "key", type: "String"))
        }
        if lowerName.contains("at") {
            parameters.append(MethodParameter(name: "index", type: "Int"))
        }
        
        return parameters
    }
    
    private func extractFunctionSignature(from symbol: TypeSymbolInfo, functionName: String) -> TypeMethod {
        let signature = "\(functionName)()"
        let returnType = inferReturnType(from: symbol.name, symbol: symbol)
        let parameters = extractMethodParameters(from: symbol.name, symbol: symbol)
        
        return TypeMethod(
            name: functionName,
            signature: signature,
            returnType: returnType,
            parameters: parameters,
            virtualAddress: symbol.address,
            accessLevel: .public
        )
    }
    
    // MARK: - Debug Information Analysis
    
    private func analyzeDebugInformation() -> [ReconstructedType] {
        // This would analyze DWARF debug information if available
        // For now, return empty array as debug info parsing is complex
        return []
    }
    
    // MARK: - Runtime Metadata Analysis
    
    private func analyzeRuntimeMetadata() -> [ReconstructedType] {
        var types: [ReconstructedType] = []
        
        let objcTypes = analyzeObjectiveCRuntime()
        types.append(contentsOf: objcTypes)
        
        let swiftTypes = analyzeSwiftRuntime()
        types.append(contentsOf: swiftTypes)
        
        return types
    }
    
    private func analyzeObjectiveCRuntime() -> [ReconstructedType] {
        var types: [ReconstructedType] = []
        
        for symbol in symbolTable {
            if symbol.name.hasPrefix("_OBJC_CLASS_$_") {
                let className = String(symbol.name.dropFirst("_OBJC_CLASS_$_".count))
                let type = ReconstructedType(
                    name: className,
                    category: .class,
                    size: estimateClassSize(className),
                    alignment: 8,
                    virtualAddress: symbol.address,
                    fileOffset: 0, // Would need to calculate from VA
                    confidence: 0.9,
                    source: .runtimeMetadata
                )
                types.append(type)
            }
        }
        
        return types
    }
    
    private func analyzeSwiftRuntime() -> [ReconstructedType] {
        var types: [ReconstructedType] = []
        
        for symbol in symbolTable {
            if symbol.name.contains("$s") && symbol.name.contains("Mp") {
                // Swift type metadata pattern
                if let typeName = extractSwiftTypeName(from: symbol.name) {
                    let type = ReconstructedType(
                        name: typeName,
                        category: .struct,
                        size: estimateSwiftTypeSize(typeName),
                        alignment: 8,
                        virtualAddress: symbol.address,
                        fileOffset: 0,
                        confidence: 0.8,
                        source: .runtimeMetadata
                    )
                    types.append(type)
                }
            }
        }
        
        return types
    }
    
    // MARK: - Pattern Inference
    
    private func performPatternInference() -> [ReconstructedType] {
        var types: [ReconstructedType] = []
        
        let functionTypes = inferTypesFromFunctions()
        types.append(contentsOf: functionTypes)
        
        let stringTypes = inferTypesFromStrings()
        types.append(contentsOf: stringTypes)
        
        let memoryTypes = inferTypesFromMemoryPatterns()
        types.append(contentsOf: memoryTypes)
        
        return types
    }
    
    private func inferTypesFromFunctions() -> [ReconstructedType] {
        var types: [ReconstructedType] = []
        
        for function in functions {
            if let type = inferTypeFromFunctionName(function.name) {
                types.append(type)
            }
            
            if let returnType = inferReturnType(from: function) {
                let type = ReconstructedType(
                    name: "\(function.name)ReturnType",
                    category: .function,
                    size: estimateTypeSize(returnType),
                    alignment: 8,
                    virtualAddress: function.startAddress,
                    fileOffset: 0,
                    confidence: 0.6,
                    source: .inference
                )
                types.append(type)
            }
        }
        
        return types
    }
    
    private func inferTypesFromStrings() -> [ReconstructedType] {
        var types: [ReconstructedType] = []
        
        for string in strings {
            // Look for type-related string patterns
            if let type = inferTypeFromString(string) {
                types.append(type)
            }
        }
        
        // Also analyze strings for type relationships
        let stringTypes = analyzeStringRelationships()
        types.append(contentsOf: stringTypes)
        
        return types
    }
    
    private func analyzeStringRelationships() -> [ReconstructedType] {
        var types: [ReconstructedType] = []
        
        // Look for class definitions in strings
        for string in strings {
            if string.contains("class ") && string.contains(":") {
                if let type = extractClassFromString(string) {
                    types.append(type)
                }
            } else if string.contains("struct ") && string.contains("{") {
                if let type = extractStructFromString(string) {
                    types.append(type)
                }
            } else if string.contains("enum ") && string.contains("case") {
                if let type = extractEnumFromString(string) {
                    types.append(type)
                }
            }
        }
        
        return types
    }
    
    private func extractClassFromString(_ string: String) -> ReconstructedType? {
        // Parse class definition from string
        let components = string.components(separatedBy: " ")
        if let classIndex = components.firstIndex(of: "class"),
           classIndex + 1 < components.count {
            let className = components[classIndex + 1]
            
            var type = ReconstructedType(
                name: className,
                category: .class,
                size: 64, // Default class size
                alignment: 8,
                virtualAddress: 0,
                fileOffset: 0,
                confidence: 0.7,
                source: .patternMatching
            )
            
            // Extract properties and methods from string
            type.properties = extractPropertiesFromString(string, typeName: className)
            type.methods = extractMethodsFromString(string, typeName: className)
            
            return type
        }
        
        return nil
    }
    
    private func extractStructFromString(_ string: String) -> ReconstructedType? {
        // Parse struct definition from string
        let components = string.components(separatedBy: " ")
        if let structIndex = components.firstIndex(of: "struct"),
           structIndex + 1 < components.count {
            let structName = components[structIndex + 1]
            
            var type = ReconstructedType(
                name: structName,
                category: .struct,
                size: 32, // Default struct size
                alignment: 4,
                virtualAddress: 0,
                fileOffset: 0,
                confidence: 0.6,
                source: .patternMatching
            )
            
            // Extract properties from string
            type.properties = extractPropertiesFromString(string, typeName: structName)
            
            return type
        }
        
        return nil
    }
    
    private func extractEnumFromString(_ string: String) -> ReconstructedType? {
        // Parse enum definition from string
        let components = string.components(separatedBy: " ")
        if let enumIndex = components.firstIndex(of: "enum"),
           enumIndex + 1 < components.count {
            let enumName = components[enumIndex + 1]
            
            var type = ReconstructedType(
                name: enumName,
                category: .enum,
                size: 4, // Default enum size
                alignment: 4,
                virtualAddress: 0,
                fileOffset: 0,
                confidence: 0.5,
                source: .patternMatching
            )
            
            // Extract enum cases from string
            type.properties = extractEnumCasesFromString(string, enumName: enumName)
            
            return type
        }
        
        return nil
    }
    
    private func extractPropertiesFromString(_ string: String, typeName: String) -> [TypeProperty] {
        var properties: [TypeProperty] = []
        
        // Look for property patterns in the string
        let lines = string.components(separatedBy: "\n")
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Look for property declarations
            if trimmedLine.contains("var ") || trimmedLine.contains("let ") {
                let components = trimmedLine.components(separatedBy: " ")
                if components.count >= 2 {
                    let propertyName = components[1].replacingOccurrences(of: ":", with: "")
                    let propertyType = components.count > 2 ? components[2] : "Any"
                    
                    properties.append(TypeProperty(
                        name: propertyName,
                        type: propertyType,
                        offset: 0,
                        size: 8, // Default size
                        isOptional: propertyType.contains("?"),
                        accessLevel: .public
                    ))
                }
            }
        }
        
        return properties
    }
    
    private func extractMethodsFromString(_ string: String, typeName: String) -> [TypeMethod] {
        var methods: [TypeMethod] = []
        
        // Look for method patterns in the string
        let lines = string.components(separatedBy: "\n")
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Look for method declarations
            if trimmedLine.contains("func ") {
                let components = trimmedLine.components(separatedBy: " ")
                if components.count >= 2 {
                    let methodName = components[1].replacingOccurrences(of: "(", with: "")
                    let signature = extractMethodSignatureFromString(trimmedLine)
                    let returnType = extractReturnTypeFromString(trimmedLine)
                    let parameters = extractParametersFromString(trimmedLine)
                    
                    methods.append(TypeMethod(
                        name: methodName,
                        signature: signature,
                        returnType: returnType,
                        parameters: parameters,
                        virtualAddress: 0,
                        accessLevel: .public
                    ))
                }
            }
        }
        
        return methods
    }
    
    private func extractEnumCasesFromString(_ string: String, enumName: String) -> [TypeProperty] {
        var cases: [TypeProperty] = []
        
        // Look for enum case patterns in the string
        let lines = string.components(separatedBy: "\n")
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Look for case declarations
            if trimmedLine.hasPrefix("case ") {
                let caseName = String(trimmedLine.dropFirst(5))
                
                cases.append(TypeProperty(
                    name: caseName,
                    type: enumName,
                    offset: 0,
                    size: 4,
                    isOptional: false,
                    accessLevel: .public
                ))
            }
        }
        
        return cases
    }
    
    private func extractMethodSignatureFromString(_ line: String) -> String {
        // Extract method signature from line
        if let openParen = line.firstIndex(of: "("),
           let closeParen = line.firstIndex(of: ")") {
            let start = line.index(after: openParen)
            let end = closeParen
            let params = String(line[start..<end])
            let methodName = line.components(separatedBy: "(").first ?? "method"
            return "\(methodName)(\(params))"
        }
        return "method()"
    }
    
    private func extractReturnTypeFromString(_ line: String) -> String {
        // Extract return type from line
        if line.contains("->") {
            let components = line.components(separatedBy: "->")
            if components.count > 1 {
                return components[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return "Void"
    }
    
    private func extractParametersFromString(_ line: String) -> [MethodParameter] {
        // Extract parameters from line
        var parameters: [MethodParameter] = []
        
        if let openParen = line.firstIndex(of: "("),
           let closeParen = line.firstIndex(of: ")") {
            let start = line.index(after: openParen)
            let end = closeParen
            let paramsString = String(line[start..<end])
            
            if !paramsString.isEmpty {
                let paramComponents = paramsString.components(separatedBy: ",")
                for param in paramComponents {
                    let trimmed = param.trimmingCharacters(in: .whitespaces)
                    let nameType = trimmed.components(separatedBy: ":")
                    if nameType.count >= 2 {
                        parameters.append(MethodParameter(
                            name: nameType[0].trimmingCharacters(in: .whitespaces),
                            type: nameType[1].trimmingCharacters(in: .whitespaces)
                        ))
                    }
                }
            }
        }
        
        return parameters
    }
    
    private func inferTypesFromMemoryPatterns() -> [ReconstructedType] {
        // This would analyze memory access patterns to infer data structures
        // For now, return empty array as this requires complex analysis
        return []
    }
    
    // MARK: - Cross-Reference Analysis
    
    private func analyzeCrossReferences() -> [ReconstructedType] {
        var types: [ReconstructedType] = []
        
        // Analyze cross-references to infer relationships
        for xref in crossReferences {
            if let type = inferTypeFromCrossReference(xref) {
                types.append(type)
            }
        }
        
        return types
    }
    
    // MARK: - Helper Methods
    
    private func isClassSymbol(_ name: String) -> Bool {
        return name.hasPrefix("_OBJC_CLASS_$_") || 
               name.contains("Class") ||
               name.hasSuffix("Class")
    }
    
    private func isStructSymbol(_ name: String) -> Bool {
        return name.contains("struct") ||
               name.hasSuffix("Struct") ||
               name.contains("_struct_")
    }
    
    private func isEnumSymbol(_ name: String) -> Bool {
        return name.contains("enum") ||
               name.hasSuffix("Enum") ||
               name.contains("_enum_")
    }
    
    private func isProtocolSymbol(_ name: String) -> Bool {
        return name.contains("protocol") ||
               name.hasSuffix("Protocol") ||
               name.contains("_protocol_")
    }
    
    private func isFunctionSymbol(_ name: String) -> Bool {
        return name.hasPrefix("_") && 
               (name.contains("func") || name.contains("method"))
    }
    
    private func createClassType(from symbol: TypeSymbolInfo) -> ReconstructedType {
        let className = extractClassName(from: symbol.name)
        var type = ReconstructedType(
            name: className,
            category: .class,
            size: estimateClassSize(className),
            alignment: 8,
            virtualAddress: symbol.address,
            fileOffset: 0,
            confidence: 0.8,
            source: .symbolTable
        )
        
        // Find related methods and properties using real analysis
        let relatedSymbols = findRelatedSymbols(for: className)
        type.properties = extractProperties(from: relatedSymbols, className: className)
        type.methods = extractMethods(from: relatedSymbols, className: className)
        
        return type
    }
    
    private func createStructType(from symbol: TypeSymbolInfo) -> ReconstructedType {
        let structName = extractStructName(from: symbol.name)
        var type = ReconstructedType(
            name: structName,
            category: .struct,
            size: estimateStructSize(structName),
            alignment: 4,
            virtualAddress: symbol.address,
            fileOffset: 0,
            confidence: 0.7,
            source: .symbolTable
        )
        
        // Find related symbols for structs using real analysis
        let relatedSymbols = findRelatedSymbols(for: structName)
        type.properties = extractProperties(from: relatedSymbols, className: structName)
        type.methods = extractMethods(from: relatedSymbols, className: structName)
        
        return type
    }
    
    private func createEnumType(from symbol: TypeSymbolInfo) -> ReconstructedType {
        let enumName = extractEnumName(from: symbol.name)
        var type = ReconstructedType(
            name: enumName,
            category: .enum,
            size: estimateEnumSize(enumName),
            alignment: 4,
            virtualAddress: symbol.address,
            fileOffset: 0,
            confidence: 0.7,
            source: .symbolTable
        )
        
        // Find enum cases and methods using real analysis
        let relatedSymbols = findRelatedSymbols(for: enumName)
        type.properties = extractEnumCases(from: relatedSymbols, enumName: enumName)
        type.methods = extractMethods(from: relatedSymbols, className: enumName)
        
        return type
    }
    
    private func createProtocolType(from symbol: TypeSymbolInfo) -> ReconstructedType {
        let protocolName = extractProtocolName(from: symbol.name)
        return ReconstructedType(
            name: protocolName,
            category: .protocol,
            size: 0, // Protocols have no instance size
            alignment: 1,
            virtualAddress: symbol.address,
            fileOffset: 0,
            confidence: 0.8,
            source: .symbolTable
        )
    }
    
    private func createFunctionType(from symbol: TypeSymbolInfo) -> ReconstructedType {
        let functionName = extractFunctionName(from: symbol.name)
        return ReconstructedType(
            name: functionName,
            category: .function,
            size: 0, // Functions have no size
            alignment: 1,
            virtualAddress: symbol.address,
            fileOffset: 0,
            confidence: 0.9,
            source: .symbolTable
        )
    }
    
    // MARK: - Name Extraction
    
    private func extractClassName(from symbolName: String) -> String {
        if symbolName.hasPrefix("_OBJC_CLASS_$_") {
            return String(symbolName.dropFirst("_OBJC_CLASS_$_".count))
        }
        return symbolName.replacingOccurrences(of: "Class", with: "")
    }
    
    private func extractStructName(from symbolName: String) -> String {
        return symbolName.replacingOccurrences(of: "struct", with: "")
                          .replacingOccurrences(of: "Struct", with: "")
                          .replacingOccurrences(of: "_", with: "")
    }
    
    private func extractEnumName(from symbolName: String) -> String {
        return symbolName.replacingOccurrences(of: "enum", with: "")
                          .replacingOccurrences(of: "Enum", with: "")
                          .replacingOccurrences(of: "_", with: "")
    }
    
    private func extractProtocolName(from symbolName: String) -> String {
        return symbolName.replacingOccurrences(of: "protocol", with: "")
                          .replacingOccurrences(of: "Protocol", with: "")
                          .replacingOccurrences(of: "_", with: "")
    }
    
    private func extractFunctionName(from symbolName: String) -> String {
        return symbolName.replacingOccurrences(of: "_", with: "")
    }
    
    private func extractSwiftTypeName(from symbolName: String) -> String? {
        // Swift mangled name parsing is complex
        // This is a simplified version
        if let range = symbolName.range(of: "$s") {
            let afterPrefix = String(symbolName[range.upperBound...])
            if let endRange = afterPrefix.range(of: "Mp") {
                return String(afterPrefix[..<endRange.lowerBound])
            }
        }
        return nil
    }
    
    // MARK: - Size Estimation
    
    private func estimateClassSize(_ className: String) -> Int {
        // Estimate based on class name patterns
        if className.contains("View") || className.contains("Controller") {
            return 200 // UI classes are typically larger
        } else if className.contains("Model") {
            return 100 // Model classes are medium-sized
        } else {
            return 64 // Default class size
        }
    }
    
    private func estimateStructSize(_ structName: String) -> Int {
        if structName.contains("Point") || structName.contains("Size") {
            return 16 // CGPoint, CGSize
        } else if structName.contains("Rect") {
            return 32 // CGRect
        } else {
            return 24 // Default struct size
        }
    }
    
    private func estimateEnumSize(_ enumName: String) -> Int {
        return 4 // Most enums are 4 bytes
    }
    
    private func estimateSwiftTypeSize(_ typeName: String) -> Int {
        if typeName.contains("String") {
            return 16 // Swift String
        } else if typeName.contains("Array") {
            return 24 // Swift Array
        } else {
            return 8 // Default Swift type
        }
    }
    
    private func estimateTypeSize(_ typeName: String) -> Int {
        switch typeName.lowercased() {
        case "int", "int32": return 4
        case "long", "int64": return 8
        case "float": return 4
        case "double": return 8
        case "bool": return 1
        case "char": return 1
        default: return 8
        }
    }
    
    // MARK: - Type Inference Helpers
    
    private func inferTypeFromFunctionName(_ functionName: String) -> ReconstructedType? {
        // Look for type-related function names
        if functionName.contains("init") || functionName.contains("alloc") {
            return ReconstructedType(
                name: "\(functionName)Type",
                category: .class,
                size: 64,
                alignment: 8,
                virtualAddress: 0,
                fileOffset: 0,
                confidence: 0.6,
                source: .inference
            )
        }
        return nil
    }
    
    private func inferReturnType(from function: FunctionModel) -> String? {
        // Analyze function signature for return type hints
        if function.name.contains("String") {
            return "String"
        } else if function.name.contains("Int") {
            return "Int"
        } else if function.name.contains("Bool") {
            return "Bool"
        }
        return nil
    }
    
    private func inferTypeFromString(_ string: String) -> ReconstructedType? {
        // Look for type-related strings
        if string.contains("class") && string.contains(":") {
            let className = string.components(separatedBy: ":").first?.trimmingCharacters(in: .whitespaces) ?? ""
            return ReconstructedType(
                name: className,
                category: .class,
                size: 64,
                alignment: 8,
                virtualAddress: 0,
                fileOffset: 0,
                confidence: 0.5,
                source: .patternMatching
            )
        }
        return nil
    }
    
    private func inferTypeFromCrossReference(_ xref: CrossReference) -> ReconstructedType? {
        // Analyze cross-references for type relationships
        return nil // Complex analysis, would need more context
    }
    
    // MARK: - Sample Data Generation
    
    private func addSamplePropertiesAndMethods(to type: ReconstructedType, className: String) -> ReconstructedType {
        var properties: [TypeProperty] = []
        var methods: [TypeMethod] = []
        
        // Add common properties based on class name patterns
        if className.contains("View") || className.contains("Controller") {
            properties.append(TypeProperty(
                name: "frame",
                type: "CGRect",
                offset: 0,
                size: 32,
                accessLevel: .public
            ))
            properties.append(TypeProperty(
                name: "bounds",
                type: "CGRect",
                offset: 32,
                size: 32,
                accessLevel: .public
            ))
            properties.append(TypeProperty(
                name: "backgroundColor",
                type: "UIColor?",
                offset: 64,
                size: 8,
                isOptional: true,
                accessLevel: .public
            ))
            
            methods.append(TypeMethod(
                name: "init",
                signature: "init(frame: CGRect)",
                returnType: "Self",
                parameters: [MethodParameter(name: "frame", type: "CGRect")],
                virtualAddress: type.virtualAddress + 0x100,
                accessLevel: .public
            ))
            methods.append(TypeMethod(
                name: "layoutSubviews",
                signature: "layoutSubviews()",
                returnType: "Void",
                parameters: [],
                virtualAddress: type.virtualAddress + 0x200,
                accessLevel: .public
            ))
        } else if className.contains("Model") {
            properties.append(TypeProperty(
                name: "id",
                type: "String",
                offset: 0,
                size: 16,
                accessLevel: .public
            ))
            properties.append(TypeProperty(
                name: "name",
                type: "String",
                offset: 16,
                size: 16,
                accessLevel: .public
            ))
            properties.append(TypeProperty(
                name: "createdAt",
                type: "Date",
                offset: 32,
                size: 8,
                accessLevel: .public
            ))
            
            methods.append(TypeMethod(
                name: "init",
                signature: "init(id: String, name: String)",
                returnType: "Self",
                parameters: [
                    MethodParameter(name: "id", type: "String"),
                    MethodParameter(name: "name", type: "String")
                ],
                virtualAddress: type.virtualAddress + 0x100,
                accessLevel: .public
            ))
        } else if className.contains("Enum") || type.category == .enum {
            // Enum-specific properties and methods
            properties.append(TypeProperty(
                name: "rawValue",
                type: "Int",
                offset: 0,
                size: 4,
                accessLevel: .public
            ))
            properties.append(TypeProperty(
                name: "description",
                type: "String",
                offset: 4,
                size: 16,
                accessLevel: .public
            ))
            
            methods.append(TypeMethod(
                name: "init",
                signature: "init(rawValue: Int)",
                returnType: "Self?",
                parameters: [MethodParameter(name: "rawValue", type: "Int")],
                virtualAddress: type.virtualAddress + 0x100,
                accessLevel: .public
            ))
            methods.append(TypeMethod(
                name: "case",
                signature: "case() -> String",
                returnType: "String",
                parameters: [],
                virtualAddress: type.virtualAddress + 0x200,
                accessLevel: .public
            ))
        } else {
            // Generic properties
            properties.append(TypeProperty(
                name: "value",
                type: "Any",
                offset: 0,
                size: 8,
                accessLevel: .public
            ))
            properties.append(TypeProperty(
                name: "isValid",
                type: "Bool",
                offset: 8,
                size: 1,
                accessLevel: .public
            ))
            
            methods.append(TypeMethod(
                name: "init",
                signature: "init()",
                returnType: "Self",
                parameters: [],
                virtualAddress: type.virtualAddress + 0x100,
                accessLevel: .public
            ))
        }
        
        // Create a new type with the added properties and methods
        var newType = type
        newType.properties = properties
        newType.methods = methods
        
        return newType
    }
    
    // MARK: - Type Merging
    
    private func mergeAndDeduplicateTypes(_ types: [ReconstructedType]) -> [ReconstructedType] {
        var mergedTypes: [ReconstructedType] = []
        var seenNames: Set<String> = []
        
        for type in types {
            if !seenNames.contains(type.name) {
                mergedTypes.append(type)
                seenNames.insert(type.name)
            }
        }
        
        return mergedTypes
    }
}
