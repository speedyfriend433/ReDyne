import Foundation

// MARK: - Symbolic Execution Engine for Register Tracking

private enum RegisterValue {
    case unknown
    case constant(UInt64)
    case pageBase(UInt64)
    case computed(base: UInt64, offset: Int64)
    case copyFrom(Int)
}

private class RegisterState {
    private var registers: [Int: RegisterValue] = [:]
    
    func set(register: Int, value: RegisterValue) {
        registers[register] = value
    }
    
    func get(register: Int) -> RegisterValue {
        return registers[register] ?? .unknown
    }
    
    func resolve(register: Int) -> UInt64? {
        switch get(register: register) {
        case .constant(let value):
            return value
        case .pageBase(let page):
            return page
        case .computed(let base, let offset):
            if offset >= 0 {
                return base &+ UInt64(offset)
            } else {
                return base &- UInt64(-offset)
            }
        case .copyFrom(let srcReg):
            return resolve(register: srcReg)
        case .unknown:
            return nil
        }
    }
    
    func reset() {
        registers.removeAll()
    }
}

class XrefAnalyzer {
    
    // MARK: - ARM64 Instruction Patterns
    
    private static let callPattern = "\\bbl\\b"
    private static let blrPattern = "\\bblr\\b"
    private static let jumpPattern = "\\bb\\b(?!\\.|l)"
    private static let brPattern = "\\bbr\\b"
    private static let condBranchPattern = "\\bb\\.(eq|ne|cs|cc|mi|pl|vs|vc|hi|ls|ge|lt|gt|le|al)"
    private static let cbzPattern = "\\b(cbz|cbnz)\\b"
    private static let tbzPattern = "\\b(tbz|tbnz)\\b"
    private static let ldrPattern = "\\bldr\\b"
    private static let ldurPattern = "\\bldur\\b"
    private static let strPattern = "\\bstr\\b"
    private static let sturPattern = "\\bstur\\b"
    private static let adrpPattern = "\\badrp\\b"
    private static let adrPattern = "\\badr\\b"
    
    // MARK: - Public Analysis Method
    
    static func analyze(disassembly: String, symbols: [SymbolInfo]) -> XrefAnalysisResult {
        print("Starting xref analysis...")
        let startTime = CFAbsoluteTimeGetCurrent()
        let instructions = parseDisassembly(disassembly)
        print("Parsed \(instructions.count) instructions")
        
        if let first = instructions.first {
            print("Sample instruction: address=0x\(String(format: "%llx", first.address)), mnemonic=\(first.mnemonic), operands=\(first.operands)")
        }
        
        let symbolTable = buildSymbolTable(symbols)
        
        var allXrefs: [CrossReference] = []
        var functionXrefsDict: [String: [CrossReference]] = [:]
        var mnemonicCounts: [String: Int] = [:]
        for inst in instructions.prefix(1000) {
            mnemonicCounts[inst.mnemonic, default: 0] += 1
        }
        print("Top mnemonics in first 1000: \(mnemonicCounts.sorted { $0.value > $1.value }.prefix(10).map { "\($0.key)(\($0.value))" }.joined(separator: ", "))")
        
        for instruction in instructions {
            if let xref = analyzeInstruction(instruction, symbolTable: symbolTable) {
                allXrefs.append(xref)
                
                let fromKey = String(format: "0x%llX", xref.fromAddress)
                if functionXrefsDict[fromKey] == nil {
                    functionXrefsDict[fromKey] = []
                }
                functionXrefsDict[fromKey]?.append(xref)
            }
        }
        
        print("Found \(allXrefs.count) cross-references")
        
        let functionXrefs = buildFunctionXrefs(allXrefs: allXrefs, symbols: symbols, symbolTable: symbolTable)
        let totalCalls = allXrefs.filter { $0.xrefType == .call }.count
        let totalJumps = allXrefs.filter { $0.xrefType == .jump || $0.xrefType == .conditionalJump }.count
        let totalDataRefs = allXrefs.filter { $0.xrefType == .dataRead || $0.xrefType == .dataWrite }.count
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("Xref analysis complete in \(String(format: "%.2f", elapsed))s")
        print("   • \(totalCalls) calls")
        print("   • \(totalJumps) jumps/branches")
        print("   • \(totalDataRefs) data references")
        
        return XrefAnalysisResult(
            totalXrefs: allXrefs.count,
            totalCalls: totalCalls,
            totalJumps: totalJumps,
            totalDataRefs: totalDataRefs,
            functionXrefs: functionXrefs,
            allXrefs: allXrefs
        )
    }
    
    // MARK: - Disassembly Parsing
    
    private struct Instruction {
        let address: UInt64
        let bytes: String
        let mnemonic: String
        let operands: String
        let fullLine: String
    }
    
    private static func parseDisassembly(_ disassembly: String) -> [Instruction] {
        var instructions: [Instruction] = []
        
        let lines = disassembly.components(separatedBy: .newlines)
        for line in lines {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            // with bytes: "0x100004abc: 94 00 12 34    bl    0x100008def"
            // simple:      "0x100004abc: bl 0x100008def"
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { continue }
            
            let addressStr = parts[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "0x", with: "")
            guard let address = UInt64(addressStr, radix: 16) else { continue }
            
            let rest = parts[1].trimmingCharacters(in: .whitespaces)
            let components = rest.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            guard !components.isEmpty else { continue }
            
            var bytes = ""
            var mnemonic = ""
            var operands = ""
            
            if components.count >= 5 && components[0].count == 2 {
                bytes = components[0..<min(4, components.count)].joined(separator: " ")
                let instructionParts = components.dropFirst(4)
                if let mn = instructionParts.first {
                    mnemonic = mn.lowercased()
                    operands = instructionParts.dropFirst().joined(separator: " ")
                }
            } else if components.count >= 1 {
                mnemonic = components[0].lowercased()
                operands = components.dropFirst().joined(separator: " ")
                bytes = ""
            } else {
                continue
            }
            
            guard !mnemonic.isEmpty else { continue }
            
            instructions.append(Instruction(
                address: address,
                bytes: bytes,
                mnemonic: mnemonic,
                operands: operands,
                fullLine: line
            ))
        }
        
        return instructions
    }
    
    // MARK: - Symbol Table
    
    private static func buildSymbolTable(_ symbols: [SymbolInfo]) -> [UInt64: SymbolInfo] {
        var table: [UInt64: SymbolInfo] = [:]
        for symbol in symbols where symbol.isDefined {
            table[symbol.address] = symbol
        }
        return table
    }
    
    private static func findSymbol(forAddress address: UInt64, in symbolTable: [UInt64: SymbolInfo]) -> String {
        if let symbol = symbolTable[address] {
            return symbol.name
        }
        
        let closestSymbol = symbolTable
            .filter { $0.key <= address }
            .max { $0.key < $1.key }
        
        if let closest = closestSymbol {
            let offset = Int64(address) - Int64(closest.key)
            if offset < 1024 {
                return "\(closest.value.name)+\(offset)"
            }
        }
        
        return ""
    }
    
    // MARK: - Instruction Analysis
    
    private static func analyzeInstruction(_ inst: Instruction, symbolTable: [UInt64: SymbolInfo]) -> CrossReference? {
        let mnemonic = inst.mnemonic
        let operands = inst.operands
        
        var xrefType: XrefType?
        var targetAddress: UInt64?
        
        if mnemonic == "bl" || mnemonic == "blr" {
            xrefType = .call
            targetAddress = extractTargetAddress(from: operands, currentAddress: inst.address)
        } else if mnemonic == "b" && !mnemonic.contains(".") {
            xrefType = .jump
            targetAddress = extractTargetAddress(from: operands, currentAddress: inst.address)
        } else if mnemonic == "br" {
            xrefType = .jump
            return nil
        } else if mnemonic.hasPrefix("b.") || mnemonic == "cbz" || mnemonic == "cbnz" || mnemonic == "tbz" || mnemonic == "tbnz" {
            xrefType = .conditionalJump
            targetAddress = extractTargetAddress(from: operands, currentAddress: inst.address)
        } else if mnemonic.hasPrefix("ldr") || mnemonic.hasPrefix("ldur") {
            xrefType = .dataRead
            targetAddress = extractDataAddress(from: operands, currentAddress: inst.address)
        } else if mnemonic.hasPrefix("str") || mnemonic.hasPrefix("stur") {
            xrefType = .dataWrite
            targetAddress = extractDataAddress(from: operands, currentAddress: inst.address)
        } else if mnemonic == "adrp" || mnemonic == "adr" {
            xrefType = .addressLoad
            targetAddress = extractTargetAddress(from: operands, currentAddress: inst.address)
        }
        
        guard let type = xrefType, let target = targetAddress, target != 0 else {
            return nil
        }
        
        let fromSymbol = findSymbol(forAddress: inst.address, in: symbolTable)
        let toSymbol = findSymbol(forAddress: target, in: symbolTable)
        
        return CrossReference(
            fromAddress: inst.address,
            toAddress: target,
            type: type,
            instruction: "\(inst.mnemonic) \(inst.operands)",
            fromSymbol: fromSymbol,
            toSymbol: toSymbol
        )
    }
    
    private static func extractTargetAddress(from operands: String, currentAddress: UInt64) -> UInt64? {
        var cleaned = operands.trimmingCharacters(in: .whitespaces)
        
        cleaned = cleaned.replacingOccurrences(of: "#", with: "")
        
        if let firstComponent = cleaned.components(separatedBy: CharacterSet(charactersIn: ", ")).first {
            cleaned = firstComponent.trimmingCharacters(in: .whitespaces)
        }
        
        if cleaned.hasPrefix("0x") {
            let hexStr = cleaned.replacingOccurrences(of: "0x", with: "")
            return UInt64(hexStr, radix: 16)
        }
        
        if cleaned.hasPrefix("-0x") {
            let hexStr = cleaned.replacingOccurrences(of: "-0x", with: "")
            if let offset = Int64(hexStr, radix: 16) {
                if currentAddress >= UInt64(offset) {
                    return currentAddress - UInt64(offset)
                }
            }
        }
        
        if cleaned.contains("0x") && !cleaned.hasPrefix("-") {
            let hexStr = cleaned.replacingOccurrences(of: "0x", with: "")
            if let offset = UInt64(hexStr, radix: 16) {
                if offset < 0x10000 {
                    return currentAddress + offset
                }
                return offset
            }
        }
        
        if let decimalValue = Int64(cleaned) {
            if decimalValue < 0 {
                if currentAddress >= UInt64(-decimalValue) {
                    return currentAddress - UInt64(-decimalValue)
                }
            } else {
                if decimalValue < 0x10000 {
                    return currentAddress + UInt64(decimalValue)
                }
                return UInt64(decimalValue)
            }
        }
        return nil
    }
    
    private static func extractDataAddress(from operands: String, currentAddress: UInt64) -> UInt64? {
        var cleaned = operands.trimmingCharacters(in: .whitespaces)
        
        if let bracketStart = cleaned.firstIndex(of: "["),
           let bracketEnd = cleaned.firstIndex(of: "]") {
            
            let bracketContent = String(cleaned[cleaned.index(after: bracketStart)..<bracketEnd])
            let components = bracketContent.components(separatedBy: ",")
            
            if components.count >= 2 {
                let offsetStr = components[1].trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "#", with: "")
                    .replacingOccurrences(of: "0x", with: "")
                
                if let offset = Int64(offsetStr, radix: 16) {
                    if offset > 0x100000000 { // extractDataAddressWithState
                        return UInt64(offset)
                    }
                }
            }
            return nil
        }
        
        cleaned = cleaned.replacingOccurrences(of: "#", with: "")
        
        if cleaned.hasPrefix("0x") {
            let hexStr = cleaned.replacingOccurrences(of: "0x", with: "")
            return UInt64(hexStr, radix: 16)
        }
        
        if let value = UInt64(cleaned, radix: 16) ?? UInt64(cleaned) {
            if value > 0x100000000 {
                return value
            }
        }
        return nil
    }
    
    // MARK: - Symbolic Execution for Data Address Extraction
    
    private static func updateRegisterState(_ state: RegisterState, instruction: Instruction) {
        let mnemonic = instruction.mnemonic.uppercased()
        let operands = instruction.operands
        
        if mnemonic == "ADRP" {
            if let (destReg, address) = parseADRP(operands: operands, currentAddress: instruction.address) {
                state.set(register: destReg, value: .pageBase(address))
            }
        }
        
        else if mnemonic == "ADD" {
            if let (destReg, srcReg, immediate) = parseADD(operands: operands) {
                let srcValue = state.get(register: srcReg)
                switch srcValue {
                case .pageBase(let base):
                    state.set(register: destReg, value: .computed(base: base, offset: immediate))
                case .constant(let base):
                    state.set(register: destReg, value: .constant(base &+ UInt64(bitPattern: immediate)))
                case .computed(let base, let offset):
                    state.set(register: destReg, value: .computed(base: base, offset: offset + immediate))
                case .copyFrom(let srcReg2):
                    if let resolved = state.resolve(register: srcReg2) {
                        state.set(register: destReg, value: .constant(resolved &+ UInt64(bitPattern: immediate)))
                    } else {
                        state.set(register: destReg, value: .unknown)
                    }
                case .unknown:
                    if immediate >= 0 {
                        state.set(register: destReg, value: .unknown)
                    }
                }
            }
        }

        else if mnemonic == "MOV" || mnemonic.hasPrefix("MOVZ") || mnemonic.hasPrefix("MOVN") {
            if let (destReg, value) = parseMOV(operands: operands) {
                state.set(register: destReg, value: value)
            }
        }
    }
    
    private static func extractDataAddressWithState(from operands: String, currentAddress: UInt64, registerState: RegisterState) -> UInt64? {
        if let simpleAddr = extractDataAddress(from: operands, currentAddress: currentAddress) {
            return simpleAddr
        }
        
        if let bracketStart = operands.firstIndex(of: "["),
           let bracketEnd = operands.firstIndex(of: "]") {
            
            let bracketContent = String(operands[operands.index(after: bracketStart)..<bracketEnd])
            let components = bracketContent.components(separatedBy: ",")
            
            if let firstComp = components.first {
                let regStr = firstComp.trimmingCharacters(in: .whitespaces)
                if let regNum = parseRegisterNumber(regStr) {
                    var offset: Int64 = 0
                    if components.count >= 2 {
                        let offsetStr = components[1].trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: "#", with: "")
                        if offsetStr.hasPrefix("0x") {
                            let hexStr = offsetStr.replacingOccurrences(of: "0x", with: "")
                            offset = Int64(hexStr, radix: 16) ?? 0
                        } else {
                            offset = Int64(offsetStr) ?? 0
                        }
                    }
                    
                    if let baseAddr = registerState.resolve(register: regNum) {
                        if offset >= 0 {
                            return baseAddr &+ UInt64(offset)
                        } else {
                            return baseAddr &- UInt64(-offset)
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Instruction Parsing Helpers
    
    private static func parseADRP(operands: String, currentAddress: UInt64) -> (destReg: Int, address: UInt64)? {
        let components = operands.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard components.count >= 2 else { return nil }
        
        guard let destReg = parseRegisterNumber(components[0]) else { return nil }
        
        var addressStr = components[1].replacingOccurrences(of: "#", with: "")
        
        if addressStr.hasPrefix("0x") {
            let hexStr = addressStr.replacingOccurrences(of: "0x", with: "")
            if let addr = UInt64(hexStr, radix: 16) {
                return (destReg, addr & ~0xFFF)
            }
        }
        
        if let offset = Int64(addressStr) {
            let pcBase = currentAddress & ~0xFFF
            if offset >= 0 {
                return (destReg, pcBase &+ UInt64(offset))
            } else {
                return (destReg, pcBase &- UInt64(-offset))
            }
        }
        
        return nil
    }
    
    private static func parseADD(operands: String) -> (destReg: Int, srcReg: Int, immediate: Int64)? {
        let components = operands.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard components.count >= 3 else { return nil }
        
        guard let destReg = parseRegisterNumber(components[0]) else { return nil }
        guard let srcReg = parseRegisterNumber(components[1]) else { return nil }
        
        var immStr = components[2].replacingOccurrences(of: "#", with: "")
        
        if immStr.hasPrefix("0x") {
            let hexStr = immStr.replacingOccurrences(of: "0x", with: "")
            if let imm = UInt64(hexStr, radix: 16) {
                return (destReg, srcReg, Int64(bitPattern: imm))
            }
        } else if let imm = Int64(immStr) {
            return (destReg, srcReg, imm)
        }
        
        return nil
    }
    
    private static func parseMOV(operands: String) -> (destReg: Int, value: RegisterValue)? {
        let components = operands.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard components.count >= 2 else { return nil }
        
        guard let destReg = parseRegisterNumber(components[0]) else { return nil }
        
        var srcStr = components[1].replacingOccurrences(of: "#", with: "")
        
        if srcStr.hasPrefix("0x") {
            let hexStr = srcStr.replacingOccurrences(of: "0x", with: "")
            if let value = UInt64(hexStr, radix: 16) {
                return (destReg, .constant(value))
            }
        }
        
        else if let value = UInt64(srcStr) {
            return (destReg, .constant(value))
        }

        else if let srcReg = parseRegisterNumber(srcStr) {
            return (destReg, .copyFrom(srcReg))
        }
        
        return nil
    }
    
    private static func parseRegisterNumber(_ regStr: String) -> Int? {
        let cleaned = regStr.trimmingCharacters(in: .whitespaces).lowercased()
        
        if cleaned.hasPrefix("x") || cleaned.hasPrefix("w") {
            let numStr = String(cleaned.dropFirst())
            if let num = Int(numStr), num >= 0 && num <= 30 {
                return num
            }
        }
        
        if cleaned == "sp" || cleaned == "xzr" || cleaned == "wzr" {
            return 31
        }
        if cleaned == "lr" {
            return 30
        }
        
        return nil
    }
    
    // MARK: - Function Xref Building
    
    private static func buildFunctionXrefs(allXrefs: [CrossReference], symbols: [SymbolInfo], symbolTable: [UInt64: SymbolInfo]) -> [String: FunctionXrefs] {
        var result: [String: FunctionXrefs] = [:]
        
        for symbol in symbols where symbol.isFunction {
            let address = symbol.address
            let key = String(format: "0x%llX", address)
            let xrefsTo = allXrefs.filter { xref in
                xref.toAddress == address || (xref.toAddress >= address && xref.toAddress < address + symbol.size)
            }
            
            let xrefsFrom = allXrefs.filter { xref in
                xref.fromAddress >= address && xref.fromAddress < address + symbol.size
            }
            
            if !xrefsTo.isEmpty || !xrefsFrom.isEmpty {
                result[key] = FunctionXrefs(
                    functionAddress: address,
                    functionName: symbol.name,
                    xrefsTo: xrefsTo,
                    xrefsFrom: xrefsFrom
                )
            }
        }
        
        return result
    }
}

