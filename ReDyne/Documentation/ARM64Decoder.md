# ARM64 Instruction Decoder - Custom Implementation

## Overview

ReDyne now features a **custom, from-scratch ARM64 (AArch64) instruction decoder** with **zero third-party dependencies**. This implementation decodes ARM64 instructions purely through bit manipulation and masking, following the official ARM Architecture Reference Manual for A-profile architecture.

## Why We Built This

Many reverse engineering tools rely on third-party libraries like Capstone for disassembly. While powerful, these dependencies can:
- Add complexity to the build system
- Increase binary size
- Create licensing considerations
- Reduce control over the decoding process

By implementing our own decoder, ReDyne achieves:
- **Zero Dependencies**: No external libraries required
- **Full Control**: Complete understanding and customization of the decoding process
- **Educational Value**: A deep dive into ARM64 instruction encoding
- **Performance**: Optimized specifically for our use cases
- **Maintainability**: Self-contained, documented implementation

## Architecture

The decoder is implemented in two files:

### `ARM64InstructionDecoder.h` (~10KB)
Defines the data structures and API:
- **Instruction Categories**: Branch, Load/Store, Data Processing (Immediate/Register), SIMD/FP
- **Opcode Enumeration**: 80+ ARM64 opcodes (B, BL, LDR, STR, ADD, SUB, MUL, AND, ORR, etc.)
- **Operand Types**: Register, Immediate, Memory, Label
- **Addressing Modes**: Offset, Pre/Post-index, Register offset, Literal pool
- **Decoded Instruction Structure**: Complete representation with mnemonic, operands, and metadata

### `ARM64InstructionDecoder.c` (~36KB)
Implements the decoding logic:
- **Bit Manipulation**: Extracts instruction fields using bit masking and shifting
- **Category Detection**: Top-level instruction classification
- **Specialized Decoders**:
  - `decode_branch_instruction()`: B, BL, BR, BLR, RET, CBZ, CBNZ, TBZ, TBNZ, B.cond
  - `decode_load_store_instruction()`: LDR, STR, LDP, STP, and all variants
  - `decode_data_processing_imm()`: ADR, ADRP, ADD, SUB, logical ops, MOVZ/MOVN/MOVK
  - `decode_data_processing_reg()`: Register-based arithmetic, logical, and shift operations
- **Formatting**: Converts decoded instructions to human-readable assembly
- **Analysis**: Branch target calculation, call/return detection

## Supported Instructions

### Branch Instructions (16 types)
- `B`, `BL` - Unconditional branch (immediate)
- `BR`, `BLR`, `RET` - Unconditional branch (register)
- `B.cond` - Conditional branch (EQ, NE, CS, CC, MI, PL, VS, VC, HI, LS, GE, LT, GT, LE, AL)
- `CBZ`, `CBNZ` - Compare and branch on zero/non-zero
- `TBZ`, `TBNZ` - Test bit and branch

### Load/Store Instructions (15 types)
- `LDR`, `STR` - Load/store register (64-bit and 32-bit)
- `LDRB`, `STRB` - Load/store byte
- `LDRH`, `STRH` - Load/store halfword
- `LDRSB`, `LDRSH`, `LDRSW` - Load signed byte/halfword/word
- `LDP`, `STP` - Load/store pair
- `LDUR`, `STUR` - Load/store unscaled
- All addressing modes: offset, pre-index, post-index, register offset, literal

### Arithmetic Instructions (11 types)
- `ADD`, `ADDS`, `SUB`, `SUBS` - Add/subtract with optional flags
- `CMP`, `CMN` - Compare (aliases)
- `MUL` - Multiply
- `MADD`, `MSUB` - Multiply-add/subtract
- `SMULL`, `UMULL` - Signed/unsigned multiply long
- `SDIV`, `UDIV` - Signed/unsigned divide

### Logical Instructions (7 types)
- `AND`, `ANDS`, `ORR`, `EOR` - Bitwise operations
- `BIC`, `EON` - Bit clear, exclusive OR NOT
- `TST` - Test bits (alias)

### Move/Shift Instructions (9 types)
- `MOV`, `MVN` - Move (register/immediate)
- `MOVZ`, `MOVN`, `MOVK` - Move wide with zero/NOT/keep
- `LSL`, `LSR`, `ASR`, `ROR` - Logical/arithmetic shift, rotate

### Other Instructions (8 types)
- `ADRP`, `ADR` - Address of page/label
- `UBFM`, `SBFM`, `BFM` - Bitfield move
- `EXTR` - Extract register
- `NOP`, `HLT`, `BRK`, `SVC`, `HVC`, `SMC` - System instructions

**Total: 70+ instructions covering the most common ARM64 operations**

## Usage Example

```c
#include "ARM64InstructionDecoder.h"

// Raw instruction bytes (e.g., from a Mach-O binary)
uint32_t raw_instruction = 0x910043FF;  // add sp, sp, #0x10
uint64_t address = 0x100000000;

// Decode the instruction
ARM64DecodedInstruction decoded;
if (arm64dec_decode_instruction(raw_instruction, address, &decoded)) {
    // Format to assembly string
    char buffer[512];
    arm64dec_format_instruction(&decoded, buffer, sizeof(buffer));
    
    printf("0x%llx: %s\n", address, buffer);
    // Output: 0x100000000: add      sp, sp, #0x10
    
    // Access decoded information
    printf("Opcode: %s\n", arm64dec_opcode_mnemonic(decoded.opcode));
    printf("Category: %d\n", decoded.category);
    printf("Operands: %d\n", decoded.operand_count);
    
    // Analyze instruction
    if (arm64dec_is_call(&decoded)) {
        printf("This is a function call!\n");
    }
}
```

## Integration with Pseudocode Generation

The decoder is seamlessly integrated with ReDyne's pseudocode generation engine:

```swift
// In PseudocodeService.swift
let rawInstruction: UInt32 = // ... load from binary
var decoded = ARM64DecodedInstruction()

if arm64dec_decode_instruction(rawInstruction, currentAddr, &decoded) {
    var buffer = [CChar](repeating: 0, count: 512)
    arm64dec_format_instruction(&decoded, &buffer, 512)
    let assembly = String(cString: buffer)
    
    // Use decoded instruction for pseudocode generation
    // The decoder provides rich semantic information:
    // - Opcode type (branch, load, store, etc.)
    // - Operand types (register, immediate, memory)
    // - Branch targets for control flow analysis
}
```

## Technical Details

### Instruction Encoding

ARM64 instructions are **32-bit fixed-width**. The decoder uses bit field extraction to identify:

1. **Top-level category** (bits [28:25]):
   - `0b1000`, `0b1001`: Data processing - immediate
   - `0b1010`, `0b1011`: Branch, exception, system
   - `0b0100`, `0b0110`, `0b1100`, `0b1110`: Load/Store
   - `0b0101`, `0b1101`: Data processing - register
   - `0b0111`, `0b1111`: SIMD/FP

2. **Specific instruction** (various bit fields depending on category)

3. **Operands** (register numbers, immediates, offsets)

### Example: Branch Decoding

```c
// Unconditional branch: bits[30:26] = 0b00101
if (BITS(ins, 26, 30) == 0b00101) {
    bool is_link = BIT(ins, 31);  // BL vs B
    decoded->opcode = is_link ? ARM64_OP_BL : ARM64_OP_B;
    
    // Extract 26-bit signed immediate, shift left by 2 (PC-relative)
    int64_t imm26 = sign_extend(BITS(ins, 0, 25), 26) << 2;
    uint64_t target = address + imm26;
    
    decoded->operands[0].type = ARM64_OPERAND_LABEL;
    decoded->operands[0].imm = target;
    return true;
}
```

### Bit Manipulation Macros

```c
// Extract bits [start:end] from instruction
#define BITS(ins, start, end) \
    (((ins) >> (start)) & ((1U << ((end) - (start) + 1)) - 1))

// Extract single bit at position
#define BIT(ins, pos) (((ins) >> (pos)) & 1)

// Sign extend a value
static inline int64_t sign_extend(uint64_t value, int bits) {
    if (value & (1ULL << (bits - 1))) {
        return (int64_t)(value | (~0ULL << bits));
    }
    return (int64_t)value;
}
```

## Performance Characteristics

- **Speed**: Direct bit manipulation - no parsing overhead
- **Memory**: Minimal allocations - most data is stack-based
- **Size**: ~46KB total (header + implementation)
- **Accuracy**: Follows ARM Architecture Reference Manual

## Limitations & Future Work

### Current Limitations
1. **SIMD/FP Instructions**: Not yet implemented (NEON, floating-point)
2. **System Instructions**: Limited support (MSR, MRS, etc.)
3. **Exception Generation**: Basic support only
4. **Atomic Operations**: Not yet implemented (LDXR, STXR, etc.)

### Future Enhancements
1. Complete NEON/ASIMD instruction support
2. Floating-point instruction decoding
3. Advanced system register access
4. Atomic and exclusive access instructions
5. SVE (Scalable Vector Extension) support
6. More sophisticated operand formatting (bitmask immediates)

## References

- [ARM Architecture Reference Manual ARMv8, for A-profile architecture](https://developer.arm.com/documentation/ddi0487/latest/)
- [ARM Cortex-A Series Programmer's Guide](https://developer.arm.com/documentation/den0024/latest/)
- ARM64 Instruction Set Encoding Documentation

## Comparison with Capstone

| Feature | Custom Decoder | Capstone |
|---------|---------------|----------|
| Dependencies | **None** | External library |
| Size | ~46KB | ~2-3MB |
| Supported Instructions | 70+ common | 1000+ comprehensive |
| ARM64 Coverage | Core ISA | Full ISA + extensions |
| Build Complexity | Simple C files | Library integration |
| Customization | **Full control** | Limited to API |
| Learning Value | **High** | Black box |
| Maintenance | Self-contained | External dependency |

## Conclusion

ReDyne's custom ARM64 decoder demonstrates that **enterprise-level functionality doesn't always require third-party dependencies**. By understanding the instruction encoding at the bit level, we've created a fast, lightweight, and maintainable decoder that serves our reverse engineering needs perfectly.

This is a testament to the power of **fundamental knowledge** and **custom implementation** over relying solely on existing libraries. It's not just a decoder - it's a learning resource and a foundation for even more advanced analysis features.

---

**Built with passion, powered by bit manipulation!** 🚀

