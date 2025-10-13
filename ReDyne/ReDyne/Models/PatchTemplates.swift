import Foundation

struct PatchTemplate: Identifiable {
    let id: UUID
    let name: String
    let description: String
    let category: Category
    let icon: String
    let instructions: [TemplateInstruction]
    let tags: [String]
    let difficulty: Difficulty
    
    enum Category: String, CaseIterable {
        case nop = "NOP Instructions"
        case bypass = "Security Bypasses"
        case optimization = "Optimizations"
        case debugging = "Debugging Helpers"
        case custom = "Custom"
        
        var icon: String {
            switch self {
            case .nop: return "x.circle"
            case .bypass: return "lock.open"
            case .optimization: return "speedometer"
            case .debugging: return "ant"
            case .custom: return "wrench.and.screwdriver"
            }
        }
    }
    
    enum Difficulty: String {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
        
        var color: String {
            switch self {
            case .beginner: return "systemGreen"
            case .intermediate: return "systemOrange"
            case .advanced: return "systemRed"
            }
        }
    }
    
    init(id: UUID = UUID(), name: String, description: String, category: Category, icon: String, instructions: [TemplateInstruction], tags: [String] = [], difficulty: Difficulty = .intermediate) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.icon = icon
        self.instructions = instructions
        self.tags = tags
        self.difficulty = difficulty
    }
}

struct TemplateInstruction {
    let step: Int
    let title: String
    let detail: String
    let arm64Pattern: String?
    let x86Pattern: String?
    let example: String?
}

class PatchTemplateLibrary {
    static let shared = PatchTemplateLibrary()
    
    let templates: [PatchTemplate]
    
    private init() {
        templates = [
            PatchTemplate(
                name: "NOP Single Instruction",
                description: "Replace any ARM64 instruction with NOP (no operation). Useful for disabling specific code without breaking flow.",
                category: .nop,
                icon: "x.circle.fill",
                instructions: [
                    TemplateInstruction(
                        step: 1,
                        title: "Find Target Instruction",
                        detail: "Locate the instruction you want to disable in the disassembly view",
                        arm64Pattern: "Any 4-byte instruction",
                        x86Pattern: "Any instruction",
                        example: "mov x0, x1 → NOP"
                    ),
                    TemplateInstruction(
                        step: 2,
                        title: "Replace with NOP",
                        detail: "ARM64 NOP is 0x1F2003D5. Replace the original 4 bytes with this value.",
                        arm64Pattern: "1F 20 03 D5",
                        x86Pattern: "90 (x86) or 1F 20 03 D5 (ARM64)",
                        example: "48 89 C7 45 → 1F 20 03 D5"
                    )
                ],
                tags: ["disable", "nop", "skip"],
                difficulty: .beginner
            ),
            
            PatchTemplate(
                name: "NOP Function Call",
                description: "Disable a BL (branch with link) instruction to skip calling a function. The return value will be undefined.",
                category: .nop,
                icon: "phone.down.fill",
                instructions: [
                    TemplateInstruction(
                        step: 1,
                        title: "Find BL Instruction",
                        detail: "Look for BL (Branch with Link) instruction that calls the target function",
                        arm64Pattern: "BL #offset (opcode 94xxxxxx)",
                        x86Pattern: nil,
                        example: "bl #0x100001234"
                    ),
                    TemplateInstruction(
                        step: 2,
                        title: "Replace with NOP",
                        detail: "Replace the 4-byte BL instruction with NOP",
                        arm64Pattern: "1F 20 03 D5",
                        x86Pattern: nil,
                        example: "94 00 12 34 → 1F 20 03 D5"
                    )
                ],
                tags: ["function", "call", "skip", "disable"],
                difficulty: .beginner
            ),
            
            PatchTemplate(
                name: "Force Return True",
                description: "Make a function always return 1 (true). Patches the function entry to set return register to 1 and return immediately.",
                category: .bypass,
                icon: "checkmark.shield.fill",
                instructions: [
                    TemplateInstruction(
                        step: 1,
                        title: "Find Function Entry",
                        detail: "Locate the first instruction of the target function",
                        arm64Pattern: "Usually starts with STP or SUB sp",
                        x86Pattern: "Usually PUSH rbp",
                        example: "stp x29, x30, [sp, #-16]!"
                    ),
                    TemplateInstruction(
                        step: 2,
                        title: "Set Return Value",
                        detail: "Replace with: MOV W0, #1 (return register = 1)",
                        arm64Pattern: "52 80 00 20",
                        x86Pattern: nil,
                        example: "New: mov w0, #1"
                    ),
                    TemplateInstruction(
                        step: 3,
                        title: "Add Return",
                        detail: "Follow with RET instruction to return immediately",
                        arm64Pattern: "C0 03 5F D6",
                        x86Pattern: nil,
                        example: "Then: ret"
                    )
                ],
                tags: ["bypass", "return", "authentication", "validation"],
                difficulty: .intermediate
            ),
            
            PatchTemplate(
                name: "Force Return False",
                description: "Make a function always return 0 (false). Useful for bypassing checks.",
                category: .bypass,
                icon: "xmark.shield.fill",
                instructions: [
                    TemplateInstruction(
                        step: 1,
                        title: "Find Function Entry",
                        detail: "Locate the first instruction of the target function",
                        arm64Pattern: "Usually starts with STP or SUB sp",
                        x86Pattern: nil,
                        example: "stp x29, x30, [sp, #-16]!"
                    ),
                    TemplateInstruction(
                        step: 2,
                        title: "Set Return Value",
                        detail: "Replace with: MOV W0, #0 (return register = 0)",
                        arm64Pattern: "52 80 00 00",
                        x86Pattern: nil,
                        example: "New: mov w0, #0"
                    ),
                    TemplateInstruction(
                        step: 3,
                        title: "Add Return",
                        detail: "Follow with RET instruction",
                        arm64Pattern: "C0 03 5F D6",
                        x86Pattern: nil,
                        example: "Then: ret"
                    )
                ],
                tags: ["bypass", "return", "disable", "check"],
                difficulty: .intermediate
            ),
            
            PatchTemplate(
                name: "Skip Conditional Branch",
                description: "Convert a conditional branch (B.cond) to an unconditional branch or NOP, forcing execution to always/never take the branch.",
                category: .bypass,
                icon: "arrow.triangle.branch",
                instructions: [
                    TemplateInstruction(
                        step: 1,
                        title: "Find Conditional Branch",
                        detail: "Locate B.EQ, B.NE, B.LT, etc. instruction",
                        arm64Pattern: "54xxxxxx (B.cond pattern)",
                        x86Pattern: nil,
                        example: "b.ne #0x100001234"
                    ),
                    TemplateInstruction(
                        step: 2,
                        title: "Convert to NOP (Never Branch)",
                        detail: "Replace with NOP to never take the branch",
                        arm64Pattern: "1F 20 03 D5",
                        x86Pattern: nil,
                        example: "Original → NOP (never branches)"
                    ),
                    TemplateInstruction(
                        step: 3,
                        title: "Or Convert to B (Always Branch)",
                        detail: "Replace with unconditional B to always branch",
                        arm64Pattern: "Keep offset, change opcode to 14xxxxxx",
                        x86Pattern: nil,
                        example: "B.NE → B (always branches)"
                    )
                ],
                tags: ["branch", "conditional", "bypass", "control flow"],
                difficulty: .advanced
            ),
            
            PatchTemplate(
                name: "Remove Debug Logging",
                description: "Disable debug print/log statements by NOPing the call instructions. Improves performance.",
                category: .optimization,
                icon: "text.slash",
                instructions: [
                    TemplateInstruction(
                        step: 1,
                        title: "Find Log Call",
                        detail: "Search for calls to NSLog, printf, os_log, etc.",
                        arm64Pattern: "BL to logging function",
                        x86Pattern: nil,
                        example: "bl #_NSLog"
                    ),
                    TemplateInstruction(
                        step: 2,
                        title: "NOP the Call",
                        detail: "Replace BL instruction with NOP",
                        arm64Pattern: "1F 20 03 D5",
                        x86Pattern: nil,
                        example: "BL _NSLog → NOP"
                    )
                ],
                tags: ["performance", "logging", "debug", "optimize"],
                difficulty: .beginner
            ),
            
            PatchTemplate(
                name: "Insert Breakpoint",
                description: "Insert a BRK instruction to trigger debugger at specific location. Useful for dynamic analysis.",
                category: .debugging,
                icon: "pause.circle.fill",
                instructions: [
                    TemplateInstruction(
                        step: 1,
                        title: "Find Target Location",
                        detail: "Choose where you want the debugger to break",
                        arm64Pattern: "Any instruction",
                        x86Pattern: nil,
                        example: "Before critical code"
                    ),
                    TemplateInstruction(
                        step: 2,
                        title: "Insert BRK",
                        detail: "Replace instruction with BRK #0",
                        arm64Pattern: "00 00 20 D4",
                        x86Pattern: "CC (x86 INT3)",
                        example: "Original → BRK #0"
                    )
                ],
                tags: ["debug", "breakpoint", "analysis"],
                difficulty: .intermediate
            ),
            
            PatchTemplate(
                name: "Force Assert Pass",
                description: "Skip assertion checks that might interfere with debugging or testing.",
                category: .debugging,
                icon: "exclamationmark.triangle.fill",
                instructions: [
                    TemplateInstruction(
                        step: 1,
                        title: "Find Assert Call",
                        detail: "Locate calls to assert, __assert_rtn, etc.",
                        arm64Pattern: "BL to assert function",
                        x86Pattern: nil,
                        example: "bl #___assert_rtn"
                    ),
                    TemplateInstruction(
                        step: 2,
                        title: "NOP the Assert",
                        detail: "Replace with NOP to skip the check",
                        arm64Pattern: "1F 20 03 D5",
                        x86Pattern: nil,
                        example: "BL assert → NOP"
                    )
                ],
                tags: ["assert", "debug", "testing"],
                difficulty: .beginner
            )
        ]
    }
    
    func templates(for category: PatchTemplate.Category) -> [PatchTemplate] {
        templates.filter { $0.category == category }
    }
    
    func search(query: String) -> [PatchTemplate] {
        guard !query.isEmpty else { return templates }
        let lowercased = query.lowercased()
        return templates.filter {
            $0.name.lowercased().contains(lowercased) ||
            $0.description.lowercased().contains(lowercased) ||
            $0.tags.contains { $0.lowercased().contains(lowercased) }
        }
    }
}

