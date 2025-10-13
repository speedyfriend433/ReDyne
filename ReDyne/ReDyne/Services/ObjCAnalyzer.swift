import Foundation

@objc class ObjCAnalyzer: NSObject {
    
    // MARK: - Public Analysis Method
    
    @objc static func analyze(machOContext: OpaquePointer) -> ObjCAnalysisResult? {
        // TEMPORARY: Mock implementation until C functions are linked
        print("ObjC analysis temporarily disabled - C functions not linked")
        return nil
        
        // TODO: Implement proper C function calls
        // For now, we'll use a placeholder path since we need the actual binary path
        let binaryPath = "placeholder_path"
        guard let runtimeInfo = objc_analyze_binary(binaryPath) else {
            return nil
        }
        
        defer {
            objc_free_runtime_info(runtimeInfo)
        }
        
        let info = runtimeInfo.pointee
        
        var classes: [ObjCClass] = []
        if info.class_count > 0, let classesPtr = info.classes {
            let classesBuffer = UnsafeBufferPointer<ObjCClassInfo>(start: classesPtr, count: Int(info.class_count))
            
            for classInfo in classesBuffer {
                if let objcClass = convertClass(classInfo) {
                    classes.append(objcClass)
                }
            }
        }
        
        var categories: [ObjCCategory] = []
        if info.category_count > 0, let categoriesPtr = info.categories {
            let categoriesBuffer = UnsafeBufferPointer<ObjCCategoryInfo>(start: categoriesPtr, count: Int(info.category_count))
            
            for categoryInfo in categoriesBuffer {
                if let category = convertCategory(categoryInfo) {
                    categories.append(category)
                }
            }
        }
        
        var protocols: [ObjCProtocol] = []
        if info.protocol_count > 0, let protocolsPtr = info.protocols {
            let protocolsBuffer = UnsafeBufferPointer<ObjCProtocolInfo>(start: protocolsPtr, count: Int(info.protocol_count))
            
            for protocolInfo in protocolsBuffer {
                if let proto = convertProtocol(protocolInfo) {
                    protocols.append(proto)
                }
            }
        }
        
        let result = ObjCAnalysisResult(classes: classes, categories: categories, protocols: protocols)

        let startTime = CFAbsoluteTimeGetCurrent()
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("✅ ObjC analysis complete in \(String(format: "%.2f", elapsed))s")
        print("   • \(result.totalClasses) classes (\(result.swiftClassCount) Swift, \(result.objcClassCount) ObjC)")
        print("   • \(result.totalMethods) methods")
        print("   • \(result.totalProperties) properties")
        print("   • \(result.totalIvars) ivars")

        // Debug: Print first few class names if any
        if !classes.isEmpty {
            print("   • First few classes: \(classes.prefix(3).map { $0.name }.joined(separator: ", "))")
        } else {
            print("   • No classes found - this may be expected for some binaries")
        }

        return result
    }
    
    // MARK: - Conversion Methods
    
    private static func convertClass(_ classInfo: ObjCClassInfo) -> ObjCClass? {
        var classInfoCopy = classInfo
        let name = withUnsafePointer(to: &classInfoCopy.name.0) { String(cString: $0) }
        guard !name.isEmpty else { return nil }
        
        let superclassName = withUnsafePointer(to: &classInfoCopy.superclass_name.0) { String(cString: $0) }
        
        var instanceMethods: [ObjCMethod] = []
        if classInfo.instance_method_count > 0, let methodsPtr = classInfo.instance_methods {
            let methodsBuffer = UnsafeBufferPointer(start: methodsPtr, count: Int(classInfo.instance_method_count))
            instanceMethods = methodsBuffer.compactMap { convertMethod($0) }
        }
        
        var classMethods: [ObjCMethod] = []
        if classInfo.class_method_count > 0, let methodsPtr = classInfo.class_methods {
            let methodsBuffer = UnsafeBufferPointer(start: methodsPtr, count: Int(classInfo.class_method_count))
            classMethods = methodsBuffer.compactMap { convertMethod($0) }
        }
        
        var properties: [ObjCProperty] = []
        if classInfo.property_count > 0, let propertiesPtr = classInfo.properties {
            let propertiesBuffer = UnsafeBufferPointer(start: propertiesPtr, count: Int(classInfo.property_count))
            properties = propertiesBuffer.compactMap { convertProperty($0) }
        }
        
        var ivars: [ObjCIvar] = []
        if classInfo.ivar_count > 0, let ivarsPtr = classInfo.ivars {
            let ivarsBuffer = UnsafeBufferPointer(start: ivarsPtr, count: Int(classInfo.ivar_count))
            ivars = ivarsBuffer.compactMap { convertIvar($0) }
        }
        
        var protocolNames: [String] = []
        if classInfo.protocol_count > 0, let protocolsPtr = classInfo.protocols {
            let protocolsBuffer = UnsafeBufferPointer(start: protocolsPtr, count: Int(classInfo.protocol_count))
            for protocolPtr in protocolsBuffer {
                if let ptr = protocolPtr {
                    let name = String(cString: ptr)
                    protocolNames.append(name)
                }
            }
        }
        
        return ObjCClass(
            name: name,
            superclassName: superclassName,
            address: classInfo.address,
            instanceMethods: instanceMethods,
            classMethods: classMethods,
            properties: properties,
            ivars: ivars,
            protocols: protocolNames,
            isSwift: classInfo.is_swift,
            isMetaClass: classInfo.is_meta_class
        )
    }
    
    private static func convertMethod(_ methodInfo: ObjCMethodInfo) -> ObjCMethod? {
        var methodInfoCopy = methodInfo
        let name = withUnsafePointer(to: &methodInfoCopy.name.0) { String(cString: $0) }
        guard !name.isEmpty else { return nil }
        
        let types = withUnsafePointer(to: &methodInfoCopy.types.0) { String(cString: $0) }
        
        return ObjCMethod(
            name: name,
            types: types,
            implementation: methodInfo.implementation,
            isClassMethod: methodInfo.is_class_method
        )
    }
    
    private static func convertProperty(_ propertyInfo: ObjCPropertyInfo) -> ObjCProperty? {
        var propertyInfoCopy = propertyInfo
        let name = withUnsafePointer(to: &propertyInfoCopy.name.0) { String(cString: $0) }
        guard !name.isEmpty else { return nil }
        
        let attributes = withUnsafePointer(to: &propertyInfoCopy.attributes.0) { String(cString: $0) }
        
        return ObjCProperty(name: name, attributes: attributes)
    }
    
    private static func convertIvar(_ ivarInfo: ObjCIvarInfo) -> ObjCIvar? {
        var ivarInfoCopy = ivarInfo
        let name = withUnsafePointer(to: &ivarInfoCopy.name.0) { String(cString: $0) }
        guard !name.isEmpty else { return nil }
        
        let type = withUnsafePointer(to: &ivarInfoCopy.type.0) { String(cString: $0) }
        
        return ObjCIvar(name: name, type: type, offset: ivarInfo.offset)
    }
    
    private static func convertCategory(_ categoryInfo: ObjCCategoryInfo) -> ObjCCategory? {
        var categoryInfoCopy = categoryInfo
        let name = withUnsafePointer(to: &categoryInfoCopy.name.0) { String(cString: $0) }
        let className = withUnsafePointer(to: &categoryInfoCopy.class_name.0) { String(cString: $0) }
        
        guard !name.isEmpty && !className.isEmpty else { return nil }
        
        var instanceMethods: [ObjCMethod] = []
        if categoryInfo.instance_method_count > 0, let methodsPtr = categoryInfo.instance_methods {
            let methodsBuffer = UnsafeBufferPointer(start: methodsPtr, count: Int(categoryInfo.instance_method_count))
            instanceMethods = methodsBuffer.compactMap { convertMethod($0) }
        }
        
        var classMethods: [ObjCMethod] = []
        if categoryInfo.class_method_count > 0, let methodsPtr = categoryInfo.class_methods {
            let methodsBuffer = UnsafeBufferPointer(start: methodsPtr, count: Int(categoryInfo.class_method_count))
            classMethods = methodsBuffer.compactMap { convertMethod($0) }
        }
        
        var properties: [ObjCProperty] = []
        if categoryInfo.property_count > 0, let propertiesPtr = categoryInfo.properties {
            let propertiesBuffer = UnsafeBufferPointer(start: propertiesPtr, count: Int(categoryInfo.property_count))
            properties = propertiesBuffer.compactMap { convertProperty($0) }
        }
        
        var protocolNames: [String] = []
        if categoryInfo.protocol_count > 0, let protocolsPtr = categoryInfo.protocols {
            let protocolsBuffer = UnsafeBufferPointer(start: protocolsPtr, count: Int(categoryInfo.protocol_count))
            for protocolPtr in protocolsBuffer {
                if let ptr = protocolPtr {
                    let name = String(cString: ptr)
                    protocolNames.append(name)
                }
            }
        }
        
        return ObjCCategory(
            name: name,
            className: className,
            instanceMethods: instanceMethods,
            classMethods: classMethods,
            properties: properties,
            protocols: protocolNames
        )
    }
    
    private static func convertProtocol(_ protocolInfo: ObjCProtocolInfo) -> ObjCProtocol? {
        var protocolInfoCopy = protocolInfo
        let name = withUnsafePointer(to: &protocolInfoCopy.name.0) { String(cString: $0) }
        guard !name.isEmpty else { return nil }
        
        var methods: [ObjCMethod] = []
        if protocolInfo.method_count > 0, let methodsPtr = protocolInfo.methods {
            let methodsBuffer = UnsafeBufferPointer(start: methodsPtr, count: Int(protocolInfo.method_count))
            methods = methodsBuffer.compactMap { convertMethod($0) }
        }
        
        return ObjCProtocol(name: name, protocols: [], methods: methods)
    }
}


