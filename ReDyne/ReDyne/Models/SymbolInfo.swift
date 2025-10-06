import Foundation

struct SymbolInfo {
    let name: String
    let address: UInt64
    let size: UInt64
    let type: String
    let scope: String
    let isDefined: Bool
    let isExternal: Bool
    let isFunction: Bool
    
    init(name: String, address: UInt64, size: UInt64, type: String, scope: String, isDefined: Bool, isExternal: Bool, isFunction: Bool) {
        self.name = name
        self.address = address
        self.size = size
        self.type = type
        self.scope = scope
        self.isDefined = isDefined
        self.isExternal = isExternal
        self.isFunction = isFunction
    }
    
    init(from model: SymbolModel) {
        self.name = model.name
        self.address = model.address
        self.size = model.size
        self.type = model.type
        self.scope = model.scope
        self.isDefined = model.isDefined
        self.isExternal = model.isExternal
        self.isFunction = model.isFunction
    }
}

