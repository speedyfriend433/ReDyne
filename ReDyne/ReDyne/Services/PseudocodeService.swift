import Foundation

public class PseudocodeService {
    
    // MARK: - Singleton
    public static let shared = PseudocodeService()
    
    // MARK: - Properties
    private var generators: [String: OpaquePointer] = [:]
    private let queue = DispatchQueue(label: "com.redyne.pseudocode", qos: .userInitiated)
    
    // MARK: - Configuration
    public struct Configuration {
        var verbosityLevel: Int32 = 2
        var showTypes: Bool = true
        var showAddresses: Bool = true
        var simplifyExpressions: Bool = true
        var inferTypes: Bool = true
        var useSimpleNames: Bool = true
        var maxInliningDepth: Int32 = 3
        var collapseConstants: Bool = true
        
        var toCConfig: PseudocodeConfig {
            return PseudocodeConfig(
                verbosity_level: verbosityLevel,
                show_types: showTypes ? 1 : 0,
                show_addresses: showAddresses ? 1 : 0,
                simplify_expressions: simplifyExpressions ? 1 : 0,
                infer_types: inferTypes ? 1 : 0,
                use_simple_names: useSimpleNames ? 1 : 0,
                max_inlining_depth: maxInliningDepth,
                collapse_constants: collapseConstants ? 1 : 0
            )
        }
    }
    
    public var configuration = Configuration()
    
    // MARK: - Initialization
    private init() {}
    
    deinit {
        cleanup()
    }
    
    // MARK: - Public API
    
    public func generatePseudocode(
        from disassembly: String,
        startAddress: UInt64,
        functionName: String? = nil
    ) -> Result<PseudocodeOutput, PseudocodeError> {
        return queue.sync {
            let generator = pseudocode_generator_create()
            guard let generator = generator else {
                return .failure(.initializationFailed)
            }
            
            defer {
                pseudocode_generator_destroy(generator)
            }
            
            var config = configuration.toCConfig
            pseudocode_generator_set_config(generator, &config)
            
            let lines = disassembly.components(separatedBy: .newlines)
            var address = startAddress
            
            for line in lines where !line.isEmpty {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                
                if var instruction = parseInstruction(trimmed, address: &address) {
                    pseudocode_generator_add_instruction(generator, &instruction)
                }
            }
            
            if let name = functionName {
                var namePtr: UnsafePointer<CChar>? = nil
                name.withCString { ptr in
                    namePtr = ptr
                }
                if namePtr != nil {
                    withUnsafeMutablePointer(to: &namePtr) { ptrToPtr in
                        pseudocode_generator_set_function_name(generator, ptrToPtr)
                    }
                }
            }
            
            if pseudocode_generator_generate(generator) == 0 {
                return .failure(.generationFailed)
            }
            
            let output = pseudocode_generator_get_output(generator)
            guard let output = output else {
                return .failure(.noOutput)
            }
            
            let result = PseudocodeOutput(from: output.pointee)
            return .success(result)
        }
    }

    public func generatePseudocode(
        forSymbol symbolName: String,
        inBinary binaryPath: String
    ) -> Result<PseudocodeOutput, PseudocodeError> {
        do {
            let instructions = try DisassemblerService.disassembleFile(
                atPath: binaryPath,
                progressBlock: nil
            )
            
            guard !instructions.isEmpty else {
                return .failure(.parsingFailed("No instructions found in binary"))
            }
            
            return generateFromInstructions(instructions, symbolName: symbolName)
        } catch {
            return .failure(.parsingFailed("Failed to disassemble binary: \(error.localizedDescription)"))
        }
    }
    
    private func generateFromInstructions(
        _ instructions: [InstructionModel],
        symbolName: String
    ) -> Result<PseudocodeOutput, PseudocodeError> {
        
        guard let function = instructions.first(where: { instruction in
            instruction.comment?.contains(symbolName) == true || 
            instruction.fullDisassembly.contains(symbolName)
        }) else {
            return .failure(.parsingFailed("Symbol '\(symbolName)' not found in binary"))
        }
        
        guard let startIdx = instructions.firstIndex(where: { $0.address == function.address }) else {
            return .failure(.parsingFailed("Function address not found in disassembly"))
        }
        
        var endIdx = startIdx + 1
        var foundReturn = false
        
        for i in (startIdx + 1)..<instructions.count {
            let inst = instructions[i]
            let mnemonic = inst.mnemonic.lowercased()
            
            if mnemonic == "ret" {
                endIdx = i + 1
                foundReturn = true
                break
            }
            
            if mnemonic == "b" && !inst.operands.isEmpty {
                endIdx = i + 1
                foundReturn = true
                break
            }
            
            if i - startIdx > 1000 {
                endIdx = i
                break
            }
            
            if i > startIdx + 10 {
                if mnemonic.hasPrefix("stp") && inst.operands.contains("fp") && inst.operands.contains("lr") {
                    endIdx = i
                    break
                }
            }
        }
        
        if !foundReturn {
            endIdx = min(startIdx + 200, instructions.count)
        }
        
        let functionInstructions = Array(instructions[startIdx..<endIdx])
        
        var disassembly = ""
        for inst in functionInstructions {
            disassembly += String(format: "0x%llx: %@ %@ %@\n",
                                inst.address,
                                inst.hexBytes,
                                inst.mnemonic,
                                inst.operands)
        }
        
        return generatePseudocode(
            from: disassembly,
            startAddress: function.address,
            functionName: symbolName
        )
    }
    
    public func generatePseudocode(
        fromBytes bytes: Data,
        startAddress: UInt64,
        architecture: Architecture = .arm64
    ) -> Result<PseudocodeOutput, PseudocodeError> {
        var disassembly = ""
        var currentAddr = startAddress
        
        for i in stride(from: 0, to: bytes.count, by: 4) {
            guard i + 4 <= bytes.count else { break }
            
            let instructionBytes = bytes.subdata(in: i..<(i+4))
            let rawInstruction = instructionBytes.withUnsafeBytes { ptr in
                ptr.load(as: UInt32.self)
            }
            
            var decoded = ARM64DecodedInstruction()
            let success = arm64dec_decode_instruction(rawInstruction, currentAddr, &decoded)
            
            if success {
                var buffer = [CChar](repeating: 0, count: 512)
                let _ = arm64dec_format_instruction(&decoded, &buffer, 512)
                let assembly = String(cString: buffer)
                
                disassembly += String(format: "0x%llx: %@\n", currentAddr, assembly)
            } else {
                disassembly += String(format: "0x%llx: .long 0x%08X\n", currentAddr, rawInstruction)
            }
            
            currentAddr += 4
        }
        
        if disassembly.isEmpty {
            return .failure(.invalidInput)
        }
        
        return generatePseudocode(
            from: disassembly,
            startAddress: startAddress,
            functionName: "FUN_\(String(format: "%08llx", startAddress))"
        )
    }
    
    // MARK: - Helper Methods
    
    private func parseInstruction(_ line: String, address: inout UInt64) -> PseudocodeInstruction? {
        var instruction = PseudocodeInstruction()
        instruction.address = address
        
        let parts = line.components(separatedBy: ":")
        if parts.count >= 2 {
            let addrStr = parts[0].trimmingCharacters(in: .whitespaces)
            if let addr = UInt64(addrStr.replacingOccurrences(of: "0x", with: ""), radix: 16) {
                instruction.address = addr
                address = addr
            }
            
            let rest = parts[1].trimmingCharacters(in: .whitespaces)
            let components = rest.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            if components.count >= 2 {
                var idx = 0
                if components[0].count == 8 && components[0].allSatisfy({ $0.isHexDigit }) {
                    if let bytes = UInt32(components[0], radix: 16) {
                        instruction.raw_bytes = bytes
                    }
                    idx = 1
                }
                
                if idx < components.count {
                    let mnemonic = components[idx]
                    _ = mnemonic.withCString { ptr in
                        strncpy(&instruction.mnemonic.0, ptr, 31)
                    }
                    idx += 1
                }
                
                if idx < components.count {
                    let operands = components[idx...].joined(separator: " ")
                    _ = operands.withCString { ptr in
                        strncpy(&instruction.operands.0, ptr, 127)
                    }
                }
            }
        } else {
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if components.count >= 1 {
                _ = components[0].withCString { ptr in
                    strncpy(&instruction.mnemonic.0, ptr, 31)
                }
                if components.count > 1 {
                    let operands = components[1...].joined(separator: " ")
                    _ = operands.withCString { ptr in
                        strncpy(&instruction.operands.0, ptr, 127)
                    }
                }
            }
        }
        
        address += 4
        return instruction
    }
    
    private func cleanup() {
        queue.sync {
            for (_, generator) in generators {
                pseudocode_generator_destroy(generator)
            }
            generators.removeAll()
        }
    }
}

// MARK: - Supporting Types

public enum Architecture {
    case arm64
    case x86_64
    case arm
    
    var description: String {
        switch self {
        case .arm64: return "ARM64"
        case .x86_64: return "x86_64"
        case .arm: return "ARM"
        }
    }
}

public enum PseudocodeError: Error, LocalizedError {
    case initializationFailed
    case generationFailed
    case noOutput
    case invalidInput
    case notImplemented
    case parsingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize pseudocode generator"
        case .generationFailed:
            return "Failed to generate pseudocode"
        case .noOutput:
            return "No pseudocode output generated"
        case .invalidInput:
            return "Invalid input data"
        case .notImplemented:
            return "Feature not yet implemented"
        case .parsingFailed(let detail):
            return "Failed to parse input: \(detail)"
        }
    }
}

public struct PseudocodeOutput {
    public let functionSignature: String
    public let pseudocode: String
    public let statistics: Statistics
    public let syntaxHighlighting: [HighlightRange]
    
    public struct Statistics {
        public let instructionCount: Int
        public let basicBlockCount: Int
        public let variableCount: Int
        public let complexity: Int
        public let loopCount: Int
        public let conditionalCount: Int
    }
    
    public struct HighlightRange {
        public let start: Int
        public let length: Int
        public let type: HighlightType
    }
    
    public enum HighlightType {
        case keyword
        case type
        case variable
        case constant
        case comment
        case function
        case operator_
        case register
        case address
    }
    
    init(from output: PseudocodeGeneratorOutput) {
        let sigPtr = withUnsafePointer(to: output.function_signature) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) { $0 }
        }
        self.functionSignature = String(cString: sigPtr)
        
        if let codePtr = output.pseudocode {
            self.pseudocode = String(cString: codePtr)
        } else {
            self.pseudocode = ""
        }
        
        self.statistics = Statistics(
            instructionCount: Int(output.instruction_count),
            basicBlockCount: Int(output.basic_block_count),
            variableCount: Int(output.variable_count),
            complexity: Int(output.complexity),
            loopCount: Int(output.loop_count),
            conditionalCount: Int(output.conditional_count)
        )
        
        var highlights: [HighlightRange] = []
        if let highlightPtr = output.syntax_highlights {
            for i in 0..<Int(output.highlight_count) {
                let highlight = highlightPtr[i]
                if let type = HighlightType(from: highlight.type) {
                    highlights.append(HighlightRange(
                        start: Int(highlight.start),
                        length: Int(highlight.length),
                        type: type
                    ))
                }
            }
        }
        self.syntaxHighlighting = highlights
    }
}

extension PseudocodeOutput.HighlightType {
    init?(from type: SyntaxHighlightType) {
        switch type {
        case HIGHLIGHT_KEYWORD: self = .keyword
        case HIGHLIGHT_TYPE: self = .type
        case HIGHLIGHT_VARIABLE: self = .variable
        case HIGHLIGHT_CONSTANT: self = .constant
        case HIGHLIGHT_COMMENT: self = .comment
        case HIGHLIGHT_FUNCTION: self = .function
        case HIGHLIGHT_OPERATOR: self = .operator_
        case HIGHLIGHT_REGISTER: self = .register
        case HIGHLIGHT_ADDRESS: self = .address
        default: return nil
        }
    }
}

// MARK: - String Extensions

extension Character {
    var isHexDigit: Bool {
        return isHexDigit(self)
    }
    
    private func isHexDigit(_ c: Character) -> Bool {
        return ("0"..."9").contains(c) || ("a"..."f").contains(c) || ("A"..."F").contains(c)
    }
}

