import Foundation

// MARK: - ObjC Method

@objc class ObjCMethod: NSObject, Codable {
    @objc let name: String
    @objc let types: String
    @objc let implementation: UInt64
    @objc let isClassMethod: Bool
    
    init(name: String, types: String, implementation: UInt64, isClassMethod: Bool) {
        self.name = name
        self.types = types
        self.implementation = implementation
        self.isClassMethod = isClassMethod
        super.init()
    }
    
    @objc var displayName: String {
        return "\(isClassMethod ? "+" : "-") \(name)"
    }
    
    @objc var readableTypes: String {
        return decodeTypeEncoding(types)
    }
    
    private func decodeTypeEncoding(_ encoding: String) -> String {
        var result = encoding
        result = result.replacingOccurrences(of: "v", with: "void")
        result = result.replacingOccurrences(of: "@", with: "id")
        result = result.replacingOccurrences(of: ":", with: "SEL")
        result = result.replacingOccurrences(of: "c", with: "char")
        result = result.replacingOccurrences(of: "i", with: "int")
        result = result.replacingOccurrences(of: "s", with: "short")
        result = result.replacingOccurrences(of: "l", with: "long")
        result = result.replacingOccurrences(of: "q", with: "long long")
        result = result.replacingOccurrences(of: "C", with: "unsigned char")
        result = result.replacingOccurrences(of: "I", with: "unsigned int")
        result = result.replacingOccurrences(of: "S", with: "unsigned short")
        result = result.replacingOccurrences(of: "L", with: "unsigned long")
        result = result.replacingOccurrences(of: "Q", with: "unsigned long long")
        result = result.replacingOccurrences(of: "f", with: "float")
        result = result.replacingOccurrences(of: "d", with: "double")
        result = result.replacingOccurrences(of: "B", with: "BOOL")
        result = result.replacingOccurrences(of: "*", with: "char*")
        result = result.replacingOccurrences(of: "#", with: "Class")
        return result
    }
}

// MARK: - ObjC Property

@objc class ObjCProperty: NSObject, Codable {
    @objc let name: String
    @objc let attributes: String
    
    init(name: String, attributes: String) {
        self.name = name
        self.attributes = attributes
        super.init()
    }
    
    @objc var displayAttributes: String {
        var attrs: [String] = []
        
        if attributes.contains("N") {
            attrs.append("nonatomic")
        } else {
            attrs.append("atomic")
        }
        
        if attributes.contains("&") {
            attrs.append("strong")
        } else if attributes.contains("W") {
            attrs.append("weak")
        } else if attributes.contains("C") {
            attrs.append("copy")
        }
        
        if attributes.contains("R") {
            attrs.append("readonly")
        }
        
        if attributes.contains("D") {
            attrs.append("dynamic")
        }
        
        return attrs.joined(separator: ", ")
    }
    
    @objc var propertyType: String {
        if let typeMatch = attributes.range(of: "T@\"([^\"]+)\"", options: .regularExpression) {
            let type = String(attributes[typeMatch]).replacingOccurrences(of: "T@\"", with: "").replacingOccurrences(of: "\"", with: "")
            return type
        } else if attributes.hasPrefix("T@") {
            return "id"
        } else if attributes.hasPrefix("Tq") {
            return "NSInteger"
        } else if attributes.hasPrefix("TQ") {
            return "NSUInteger"
        } else if attributes.hasPrefix("Td") {
            return "double"
        } else if attributes.hasPrefix("Tf") {
            return "float"
        } else if attributes.hasPrefix("TB") {
            return "BOOL"
        }
        return "id"
    }
}

// MARK: - ObjC Ivar

@objc class ObjCIvar: NSObject, Codable {
    @objc let name: String
    @objc let type: String
    @objc let offset: UInt64
    
    init(name: String, type: String, offset: UInt64) {
        self.name = name
        self.type = type
        self.offset = offset
        super.init()
    }
}

// MARK: - ObjC Protocol

@objc class ObjCProtocol: NSObject, Codable {
    @objc let name: String
    @objc let protocols: [String]     
    @objc let methods: [ObjCMethod]
    
    init(name: String, protocols: [String], methods: [ObjCMethod]) {
        self.name = name
        self.protocols = protocols
        self.methods = methods
        super.init()
    }
    
    @objc var adoptedProtocolsString: String {
        return protocols.isEmpty ? "" : "<\(protocols.joined(separator: ", "))>"
    }
}

// MARK: - ObjC Category

@objc class ObjCCategory: NSObject, Codable {
    @objc let name: String
    @objc let className: String
    @objc let instanceMethods: [ObjCMethod]
    @objc let classMethods: [ObjCMethod]
    @objc let properties: [ObjCProperty]
    @objc let protocols: [String]
    
    init(name: String, className: String, instanceMethods: [ObjCMethod], classMethods: [ObjCMethod], properties: [ObjCProperty], protocols: [String]) {
        self.name = name
        self.className = className
        self.instanceMethods = instanceMethods
        self.classMethods = classMethods
        self.properties = properties
        self.protocols = protocols
        super.init()
    }
    
    @objc var displayName: String {
        return "\(className) (\(name))"
    }
}

// MARK: - ObjC Class

@objc class ObjCClass: NSObject, Codable {
    @objc let name: String
    @objc let superclassName: String
    @objc let address: UInt64
    @objc let instanceMethods: [ObjCMethod]
    @objc let classMethods: [ObjCMethod]
    @objc let properties: [ObjCProperty]
    @objc let ivars: [ObjCIvar]
    @objc let protocols: [String]
    @objc let isSwift: Bool
    @objc let isMetaClass: Bool
    
    init(name: String, superclassName: String, address: UInt64, instanceMethods: [ObjCMethod], classMethods: [ObjCMethod], properties: [ObjCProperty], ivars: [ObjCIvar], protocols: [String], isSwift: Bool, isMetaClass: Bool) {
        self.name = name
        self.superclassName = superclassName
        self.address = address
        self.instanceMethods = instanceMethods
        self.classMethods = classMethods
        self.properties = properties
        self.ivars = ivars
        self.protocols = protocols
        self.isSwift = isSwift
        self.isMetaClass = isMetaClass
        super.init()
    }
    
    @objc var displayName: String {
        let prefix = isSwift ? "🔷 " : "🔶 "
        return "\(prefix)\(name)"
    }
    
    @objc var hierarchy: String {
        return superclassName.isEmpty ? name : "\(name) : \(superclassName)"
    }
    
    @objc var adoptedProtocols: String {
        return protocols.isEmpty ? "" : "<\(protocols.joined(separator: ", "))>"
    }
    
    @objc var totalMethods: Int {
        return instanceMethods.count + classMethods.count
    }
    
    @objc var interfaceDeclaration: String {
        var decl = "@interface \(name)"
        if !superclassName.isEmpty {
            decl += " : \(superclassName)"
        }
        if !protocols.isEmpty {
            decl += " <\(protocols.joined(separator: ", "))>"
        }
        return decl
    }
}

// MARK: - ObjC Analysis Result

@objc class ObjCAnalysisResult: NSObject {
    @objc let classes: [ObjCClass]
    @objc let categories: [ObjCCategory]
    @objc let protocols: [ObjCProtocol]
    @objc let totalClasses: Int
    @objc let totalMethods: Int
    @objc let totalProperties: Int
    @objc let totalIvars: Int
    @objc let swiftClassCount: Int
    @objc let objcClassCount: Int
    
    init(classes: [ObjCClass], categories: [ObjCCategory], protocols: [ObjCProtocol]) {
        self.classes = classes
        self.categories = categories
        self.protocols = protocols
        self.totalClasses = classes.count
        
        var methodCount = 0
        var propertyCount = 0
        var ivarCount = 0
        var swiftCount = 0
        var objcCount = 0
        
        for cls in classes {
            methodCount += cls.totalMethods
            propertyCount += cls.properties.count
            ivarCount += cls.ivars.count
            
            if cls.isSwift {
                swiftCount += 1
            } else {
                objcCount += 1
            }
        }
        
        for category in categories {
            methodCount += category.instanceMethods.count + category.classMethods.count
            propertyCount += category.properties.count
        }
        
        for proto in protocols {
            methodCount += proto.methods.count
        }
        
        self.totalMethods = methodCount
        self.totalProperties = propertyCount
        self.totalIvars = ivarCount
        self.swiftClassCount = swiftCount
        self.objcClassCount = objcCount
        
        super.init()
    }
    
    @objc func findClass(named name: String) -> ObjCClass? {
        return classes.first { $0.name == name }
    }
    
    @objc func classesInheriting(from superclass: String) -> [ObjCClass] {
        return classes.filter { $0.superclassName == superclass }
    }
    
    @objc func classesConforming(toProtocol protocolName: String) -> [ObjCClass] {
        return classes.filter { $0.protocols.contains(protocolName) }
    }
}

// MARK: - Array Extensions

extension Array where Element == ObjCClass {
    func sortedByName() -> [ObjCClass] {
        return sorted { $0.name < $1.name }
    }
    
    func filterByName(_ query: String) -> [ObjCClass] {
        guard !query.isEmpty else { return self }
        return filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    
    func swiftClasses() -> [ObjCClass] {
        return filter { $0.isSwift }
    }
    
    func objcClasses() -> [ObjCClass] {
        return filter { !$0.isSwift }
    }
}

extension Array where Element == ObjCMethod {
    func sortedByName() -> [ObjCMethod] {
        return sorted { $0.name < $1.name }
    }
    
    func filterByName(_ query: String) -> [ObjCMethod] {
        guard !query.isEmpty else { return self }
        return filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

