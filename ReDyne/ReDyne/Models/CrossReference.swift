import Foundation

// MARK: - Cross-Reference Types

enum XrefType: String, Codable {
    case call
    case jump
    case conditionalJump
    case dataRead
    case dataWrite
    case addressLoad
    case unknown
    
    var displayName: String {
        switch self {
        case .call: return "Call"
        case .jump: return "Jump"
        case .conditionalJump: return "Cond Jump"
        case .dataRead: return "Read"
        case .dataWrite: return "Write"
        case .addressLoad: return "Addr"
        case .unknown: return "Unknown"
        }
    }
    
    var symbol: String {
        switch self {
        case .call: return "📞"
        case .jump: return "↗️"
        case .conditionalJump: return "🔀"
        case .dataRead: return "📖"
        case .dataWrite: return "✍️"
        case .addressLoad: return "🎯"
        case .unknown: return "❓"
        }
    }
}

// MARK: - Cross-Reference Model

class CrossReference: NSObject, Codable {
    @objc let fromAddress: UInt64
    @objc let toAddress: UInt64
    @objc let type: String
    @objc let instruction: String
    @objc let fromSymbol: String
    @objc let toSymbol: String
    @objc let offset: Int64
    
    var xrefType: XrefType {
        return XrefType(rawValue: type) ?? .unknown
    }
    
    init(fromAddress: UInt64, toAddress: UInt64, type: XrefType, instruction: String, fromSymbol: String = "", toSymbol: String = "", offset: Int64 = 0) {
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.type = type.rawValue
        self.instruction = instruction
        self.fromSymbol = fromSymbol
        self.toSymbol = toSymbol
        self.offset = offset
        super.init()
    }
    
    @objc var displayDescription: String {
        let typeSymbol = xrefType.symbol
        let fromAddr = Constants.formatAddress(fromAddress)
        let toAddr = Constants.formatAddress(toAddress)
        
        if !fromSymbol.isEmpty && !toSymbol.isEmpty {
            return "\(typeSymbol) \(fromAddr) (\(fromSymbol)) → \(toAddr) (\(toSymbol))"
        } else if !toSymbol.isEmpty {
            return "\(typeSymbol) \(fromAddr) → \(toAddr) (\(toSymbol))"
        } else {
            return "\(typeSymbol) \(fromAddr) → \(toAddr)"
        }
    }
}

// MARK: - Function Xref Summary

class FunctionXrefs: NSObject {
    @objc let functionAddress: UInt64
    @objc let functionName: String
    @objc let xrefsTo: [CrossReference]
    @objc let xrefsFrom: [CrossReference]
    
    init(functionAddress: UInt64, functionName: String, xrefsTo: [CrossReference], xrefsFrom: [CrossReference]) {
        self.functionAddress = functionAddress
        self.functionName = functionName
        self.xrefsTo = xrefsTo
        self.xrefsFrom = xrefsFrom
        super.init()
    }
    
    @objc var hasXrefs: Bool {
        return !xrefsTo.isEmpty || !xrefsFrom.isEmpty
    }
    
    @objc var totalXrefs: Int {
        return xrefsTo.count + xrefsFrom.count
    }
    
    @objc var callerCount: Int {
        return xrefsTo.filter { $0.xrefType == .call }.count
    }
    
    @objc var calleeCount: Int {
        return xrefsFrom.filter { $0.xrefType == .call }.count
    }
}

// MARK: - Xref Analysis Result

@objc class XrefAnalysisResult: NSObject {
    @objc let totalXrefs: Int
    @objc let totalCalls: Int
    @objc let totalJumps: Int
    @objc let totalDataRefs: Int
    @objc let functionXrefs: [String: FunctionXrefs]  
    @objc let allXrefs: [CrossReference]
    
    init(totalXrefs: Int, totalCalls: Int, totalJumps: Int, totalDataRefs: Int, functionXrefs: [String: FunctionXrefs], allXrefs: [CrossReference]) {
        self.totalXrefs = totalXrefs
        self.totalCalls = totalCalls
        self.totalJumps = totalJumps
        self.totalDataRefs = totalDataRefs
        self.functionXrefs = functionXrefs
        self.allXrefs = allXrefs
        super.init()
    }
    
    @objc func getXrefs(forAddress address: UInt64) -> FunctionXrefs? {
        let key = String(format: "0x%llX", address)
        return functionXrefs[key]
    }
    
    @objc func getCallersOfFunction(address: UInt64) -> [CrossReference] {
        return allXrefs.filter { $0.toAddress == address && $0.xrefType == .call }
    }
    
    @objc func getCalledByFunction(address: UInt64) -> [CrossReference] {
        return allXrefs.filter { $0.fromAddress == address && $0.xrefType == .call }
    }
}

// MARK: - Array Extensions

extension Array where Element == CrossReference {
    func sortedByFromAddress() -> [CrossReference] {
        return sorted { $0.fromAddress < $1.fromAddress }
    }
    
    func sortedByToAddress() -> [CrossReference] {
        return sorted { $0.toAddress < $1.toAddress }
    }
    
    func filterByType(_ type: XrefType) -> [CrossReference] {
        return filter { $0.xrefType == type }
    }
    
    func calls() -> [CrossReference] {
        return filterByType(.call)
    }
    
    func jumps() -> [CrossReference] {
        return filter { $0.xrefType == .jump || $0.xrefType == .conditionalJump }
    }
    
    func dataReferences() -> [CrossReference] {
        return filter { $0.xrefType == .dataRead || $0.xrefType == .dataWrite }
    }
}

