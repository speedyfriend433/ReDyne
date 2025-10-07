#include "ARM64InstructionDecoder.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// MARK: - Bit Manipulation Macros

#define BITS(ins, start, end) (((ins) >> (start)) & ((1U << ((end) - (start) + 1)) - 1))
#define BIT(ins, pos) (((ins) >> (pos)) & 1)

static inline int64_t sign_extend(uint64_t value, int bits) {
    if (value & (1ULL << (bits - 1))) {
        return (int64_t)(value | (~0ULL << bits));
    }
    return (int64_t)value;
}

static inline uint64_t replicate(uint64_t value, int from_width, int to_width) {
    uint64_t result = 0;
    for (int i = 0; i < to_width; i += from_width) {
        result |= value << i;
    }
    return result;
}

static inline uint64_t ror64(uint64_t value, int shift) {
    return (value >> shift) | (value << (64 - shift));
}

static bool decode_bitmask_immediate(uint8_t n, uint8_t immr, uint8_t imms, bool is_64, uint64_t *out_value) {
    if (!out_value) return false;
    
    uint8_t len = 0;
    uint8_t levels;
    
    if (n == 1) {
        len = 6;
        levels = 0x3F;
    } else {
        uint8_t not_imms = (~imms) & 0x3F;
        if (not_imms == 0) {
            return false;
        }
        
        int leading_zeros = 0;
        for (int i = 5; i >= 0; i--) {
            if (not_imms & (1 << i)) break;
            leading_zeros++;
        }
        
        len = 5 - leading_zeros;
        levels = (1 << len) - 1;
        
        if (!is_64 && len == 5) {
            return false;
        }
    }
    
    uint8_t s = imms & levels;
    uint8_t r = immr & levels;
    
    int esize = 1 << len;
    int ones = s + 1;
    uint64_t pattern = (1ULL << ones) - 1;
    
    if (r > 0 && r < esize) {
        uint64_t mask = (1ULL << esize) - 1;
        pattern = ((pattern >> r) | (pattern << (esize - r))) & mask;
    }
    
    int width = is_64 ? 64 : 32;
    uint64_t result = replicate(pattern, esize, width);
    
    if (!is_64) {
        result &= 0xFFFFFFFF;
    }
    
    *out_value = result;
    return true;
}

// MARK: - Register Helpers

static ARM64Register make_reg(uint8_t num, bool is_64bit) {
    ARM64Register reg;
    reg.num = num;
    reg.is_64bit = is_64bit;
    reg.is_sp = (num == 31);
    reg.is_zero = (num == 31);
    return reg;
}

const char* arm64dec_register_name(ARM64Register reg) {
    static char buf[8];
    
    if (reg.num == 31) {
        if (reg.is_sp) {
            return reg.is_64bit ? "sp" : "wsp";
        } else {
            return reg.is_64bit ? "xzr" : "wzr";
        }
    }
    
    snprintf(buf, sizeof(buf), "%c%d", reg.is_64bit ? 'x' : 'w', reg.num);
    return buf;
}

const char* arm64dec_condition_name(ARM64Condition cond) {
    static const char *names[] = {
        "eq", "ne", "cs", "cc", "mi", "pl", "vs", "vc",
        "hi", "ls", "ge", "lt", "gt", "le", "al", "nv"
    };
    return names[cond & 0xF];
}

const char* arm64dec_opcode_mnemonic(ARM64Opcode opcode) {
    switch (opcode) {
        case ARM64_OP_B: return "b";
        case ARM64_OP_BL: return "bl";
        case ARM64_OP_BR: return "br";
        case ARM64_OP_BLR: return "blr";
        case ARM64_OP_RET: return "ret";
        case ARM64_OP_CBZ: return "cbz";
        case ARM64_OP_CBNZ: return "cbnz";
        case ARM64_OP_TBZ: return "tbz";
        case ARM64_OP_TBNZ: return "tbnz";
        case ARM64_OP_B_COND: return "b";
        case ARM64_OP_LDR: return "ldr";
        case ARM64_OP_LDRB: return "ldrb";
        case ARM64_OP_LDRH: return "ldrh";
        case ARM64_OP_LDRSB: return "ldrsb";
        case ARM64_OP_LDRSH: return "ldrsh";
        case ARM64_OP_LDRSW: return "ldrsw";
        case ARM64_OP_STR: return "str";
        case ARM64_OP_STRB: return "strb";
        case ARM64_OP_STRH: return "strh";
        case ARM64_OP_LDP: return "ldp";
        case ARM64_OP_STP: return "stp";
        case ARM64_OP_LDUR: return "ldur";
        case ARM64_OP_STUR: return "stur";
        case ARM64_OP_ADD: return "add";
        case ARM64_OP_ADDS: return "adds";
        case ARM64_OP_SUB: return "sub";
        case ARM64_OP_SUBS: return "subs";
        case ARM64_OP_MUL: return "mul";
        case ARM64_OP_MADD: return "madd";
        case ARM64_OP_MSUB: return "msub";
        case ARM64_OP_SMULL: return "smull";
        case ARM64_OP_UMULL: return "umull";
        case ARM64_OP_SDIV: return "sdiv";
        case ARM64_OP_UDIV: return "udiv";
        case ARM64_OP_AND: return "and";
        case ARM64_OP_ANDS: return "ands";
        case ARM64_OP_ORR: return "orr";
        case ARM64_OP_EOR: return "eor";
        case ARM64_OP_BIC: return "bic";
        case ARM64_OP_EON: return "eon";
        case ARM64_OP_TST: return "tst";
        case ARM64_OP_MOV: return "mov";
        case ARM64_OP_MOVZ: return "movz";
        case ARM64_OP_MOVN: return "movn";
        case ARM64_OP_MOVK: return "movk";
        case ARM64_OP_MVN: return "mvn";
        case ARM64_OP_LSL: return "lsl";
        case ARM64_OP_LSR: return "lsr";
        case ARM64_OP_ASR: return "asr";
        case ARM64_OP_ROR: return "ror";
        case ARM64_OP_CMP: return "cmp";
        case ARM64_OP_CMN: return "cmn";
        case ARM64_OP_UBFM: return "ubfm";
        case ARM64_OP_SBFM: return "sbfm";
        case ARM64_OP_BFM: return "bfm";
        case ARM64_OP_EXTR: return "extr";
        case ARM64_OP_NOP: return "nop";
        case ARM64_OP_HLT: return "hlt";
        case ARM64_OP_BRK: return "brk";
        case ARM64_OP_SVC: return "svc";
        case ARM64_OP_HVC: return "hvc";
        case ARM64_OP_SMC: return "smc";
        case ARM64_OP_ADRP: return "adrp";
        case ARM64_OP_ADR: return "adr";
        
        default: return "unknown";
    }
}

// MARK: - Instruction Category Detection

static ARM64InstructionCategory get_instruction_category(uint32_t ins) {
    uint8_t op0 = BITS(ins, 25, 28);
    
    switch (op0) {
        case 0b0000 ... 0b0011:
            return ARM64_INS_UNKNOWN;
            
        case 0b1000:
        case 0b1001:
            return ARM64_INS_DATA_PROCESSING_IMM;
            
        case 0b1010:
        case 0b1011:
            return ARM64_INS_BRANCH;
            
        case 0b0100:
        case 0b0110:
        case 0b1100:
        case 0b1110:
            return ARM64_INS_LOAD_STORE;
            
        case 0b0101:
        case 0b1101:
            return ARM64_INS_DATA_PROCESSING_REG;
            
        case 0b0111:
        case 0b1111:
            return ARM64_INS_DATA_PROCESSING_SIMD;
            
        default:
            return ARM64_INS_UNKNOWN;
    }
}

// MARK: - Branch Instruction Decoding

static bool decode_branch_instruction(uint32_t ins, uint64_t addr, ARM64DecodedInstruction *decoded) {
    decoded->category = ARM64_INS_BRANCH;
    
    if (BITS(ins, 26, 30) == 0b00101) {
        bool is_link = BIT(ins, 31);
        decoded->opcode = is_link ? ARM64_OP_BL : ARM64_OP_B;
        
        int64_t imm26 = sign_extend(BITS(ins, 0, 25), 26) << 2;
        
        decoded->operands[0].type = ARM64_OPERAND_LABEL;
        decoded->operands[0].imm = addr + imm26;
        decoded->operand_count = 1;
        
        return true;
    }
    
    if (BITS(ins, 24, 30) == 0b0101010 && BIT(ins, 4) == 0) {
        decoded->opcode = ARM64_OP_B_COND;
        decoded->condition = (ARM64Condition)BITS(ins, 0, 3);
        
        int64_t imm19 = sign_extend(BITS(ins, 5, 23), 19) << 2;
        
        decoded->operands[0].type = ARM64_OPERAND_LABEL;
        decoded->operands[0].imm = addr + imm19;
        decoded->operand_count = 1;
        
        return true;
    }
    
    if (BITS(ins, 25, 30) == 0b011010) {
        bool is_nz = BIT(ins, 24);
        bool is_64 = BIT(ins, 31);
        
        decoded->opcode = is_nz ? ARM64_OP_CBNZ : ARM64_OP_CBZ;
        
        uint8_t rt = BITS(ins, 0, 4);
        decoded->operands[0].type = ARM64_OPERAND_REG;
        decoded->operands[0].reg = make_reg(rt, is_64);
        
        int64_t imm19 = sign_extend(BITS(ins, 5, 23), 19) << 2;
        decoded->operands[1].type = ARM64_OPERAND_LABEL;
        decoded->operands[1].imm = addr + imm19;
        decoded->operand_count = 2;
        
        return true;
    }
    
    if (BITS(ins, 25, 30) == 0b011011) {
        bool is_nz = BIT(ins, 24);
        uint8_t b5 = BIT(ins, 31);
        uint8_t b40 = BITS(ins, 19, 23);
        uint8_t bit_pos = (b5 << 5) | b40;
        
        decoded->opcode = is_nz ? ARM64_OP_TBNZ : ARM64_OP_TBZ;
        
        uint8_t rt = BITS(ins, 0, 4);
        decoded->operands[0].type = ARM64_OPERAND_REG;
        decoded->operands[0].reg = make_reg(rt, b5);
        
        decoded->operands[1].type = ARM64_OPERAND_IMM;
        decoded->operands[1].imm = bit_pos;
        
        int64_t imm14 = sign_extend(BITS(ins, 5, 18), 14) << 2;
        decoded->operands[2].type = ARM64_OPERAND_LABEL;
        decoded->operands[2].imm = addr + imm14;
        decoded->operand_count = 3;
        
        return true;
    }
    
    if (BITS(ins, 25, 31) == 0b1101011) {
        uint8_t opc = BITS(ins, 21, 24);
        uint8_t rn = BITS(ins, 5, 9);
        
        if (opc == 0b0000) {
            decoded->opcode = ARM64_OP_BR;
            decoded->operands[0].type = ARM64_OPERAND_REG;
            decoded->operands[0].reg = make_reg(rn, true);
            decoded->operand_count = 1;
            return true;
        } else if (opc == 0b0001) {
            decoded->opcode = ARM64_OP_BLR;
            decoded->operands[0].type = ARM64_OPERAND_REG;
            decoded->operands[0].reg = make_reg(rn, true);
            decoded->operand_count = 1;
            return true;
        } else if (opc == 0b0010) {
            decoded->opcode = ARM64_OP_RET;
            if (rn != 30) {
                decoded->operands[0].type = ARM64_OPERAND_REG;
                decoded->operands[0].reg = make_reg(rn, true);
                decoded->operand_count = 1;
            } else {
                decoded->operand_count = 0;
            }
            return true;
        }
    }
    
    if (ins == 0xD503201F) {
        decoded->opcode = ARM64_OP_NOP;
        decoded->operand_count = 0;
        return true;
    }
    
    return false;
}

// MARK: - Load/Store Instruction Decoding

static bool decode_load_store_instruction(uint32_t ins, uint64_t addr, ARM64DecodedInstruction *decoded) {
    decoded->category = ARM64_INS_LOAD_STORE;
    
    uint8_t op0 = BITS(ins, 28, 31);
    uint8_t op1 = BIT(ins, 26);
    uint8_t op2 = BITS(ins, 23, 24);
    uint8_t op3 = BITS(ins, 16, 21);
    uint8_t op4 = BITS(ins, 10, 11);
    
    if ((op0 & 0b0011) == 0b0011 && op1 == 1 && op2 == 0b01) {
        uint8_t size = BITS(ins, 30, 31);
        bool is_load = BIT(ins, 22);
        
        uint8_t rt = BITS(ins, 0, 4);
        uint8_t rn = BITS(ins, 5, 9);
        uint16_t imm12 = BITS(ins, 10, 21);
        
        bool is_64 = (size == 0b11);
        
        if (size == 0b00) {
            decoded->opcode = is_load ? ARM64_OP_LDRB : ARM64_OP_STRB;
        } else if (size == 0b01) {
            decoded->opcode = is_load ? ARM64_OP_LDRH : ARM64_OP_STRH;
        } else if (size == 0b10) {
            decoded->opcode = is_load ? ARM64_OP_LDR : ARM64_OP_STR;
            is_64 = false;
        } else {
            decoded->opcode = is_load ? ARM64_OP_LDR : ARM64_OP_STR;
            is_64 = true;
        }
        
        decoded->operands[0].type = ARM64_OPERAND_REG;
        decoded->operands[0].reg = make_reg(rt, is_64);
        decoded->operands[1].type = ARM64_OPERAND_MEM;
        decoded->operands[1].mem.base = make_reg(rn, true);
        decoded->operands[1].mem.offset_imm = imm12 << size;
        decoded->operands[1].mem.mode = ARM64_ADDR_OFFSET;
        
        decoded->operand_count = 2;
        return true;
    }
    
    if ((op0 & 0b0011) == 0b0011 && op1 == 1 && op2 == 0b00 && op4 == 0b10) {
        uint8_t size = BITS(ins, 30, 31);
        bool is_load = BIT(ins, 22);
        
        uint8_t rt = BITS(ins, 0, 4);
        uint8_t rn = BITS(ins, 5, 9);
        uint8_t rm = BITS(ins, 16, 20);
        uint8_t option = BITS(ins, 13, 15);
        uint8_t s = BIT(ins, 12);
        
        bool is_64 = (size == 0b11);
        
        if (size == 0b00) {
            decoded->opcode = is_load ? ARM64_OP_LDRB : ARM64_OP_STRB;
        } else if (size == 0b01) {
            decoded->opcode = is_load ? ARM64_OP_LDRH : ARM64_OP_STRH;
        } else if (size == 0b10) {
            decoded->opcode = is_load ? ARM64_OP_LDR : ARM64_OP_STR;
            is_64 = false;
        } else {
            decoded->opcode = is_load ? ARM64_OP_LDR : ARM64_OP_STR;
            is_64 = true;
        }
        
        decoded->operands[0].type = ARM64_OPERAND_REG;
        decoded->operands[0].reg = make_reg(rt, is_64);
        decoded->operands[1].type = ARM64_OPERAND_MEM;
        decoded->operands[1].mem.base = make_reg(rn, true);
        decoded->operands[1].mem.offset_reg = make_reg(rm, true);
        decoded->operands[1].mem.mode = ARM64_ADDR_REG_EXTENDED;
        decoded->operands[1].mem.extend_type = option;
        decoded->operands[1].mem.shift_amount = s ? size : 0;
        
        decoded->operand_count = 2;
        return true;
    }
    
    if ((op0 & 0b0010) == 0b0010 && op1 == 1) {
        uint8_t opc = BITS(ins, 30, 31);
        bool is_load = BIT(ins, 22);
        
        uint8_t rt = BITS(ins, 0, 4);
        uint8_t rn = BITS(ins, 5, 9);
        uint8_t rt2 = BITS(ins, 10, 14);
        int8_t imm7 = sign_extend(BITS(ins, 15, 21), 7);
        
        bool is_64 = (opc & 0b10);
        int scale = is_64 ? 3 : 2;
        
        decoded->opcode = is_load ? ARM64_OP_LDP : ARM64_OP_STP;
        
        decoded->operands[0].type = ARM64_OPERAND_REG;
        decoded->operands[0].reg = make_reg(rt, is_64);
        
        decoded->operands[1].type = ARM64_OPERAND_REG;
        decoded->operands[1].reg = make_reg(rt2, is_64);
        
        decoded->operands[2].type = ARM64_OPERAND_MEM;
        decoded->operands[2].mem.base = make_reg(rn, true);
        decoded->operands[2].mem.offset_imm = imm7 << scale;
        
        if (op2 == 0b01) {
            decoded->operands[2].mem.mode = ARM64_ADDR_POST_INDEX;
        } else if (op2 == 0b11) {
            decoded->operands[2].mem.mode = ARM64_ADDR_PRE_INDEX;
        } else {
            decoded->operands[2].mem.mode = ARM64_ADDR_OFFSET;
        }
        
        decoded->operand_count = 3;
        return true;
    }
    
    if (BITS(ins, 24, 30) == 0b0011000) {
        bool is_64 = BIT(ins, 30);
        uint8_t rt = BITS(ins, 0, 4);
        int32_t imm19 = sign_extend(BITS(ins, 5, 23), 19) << 2;
        
        decoded->opcode = ARM64_OP_LDR;
        decoded->operands[0].type = ARM64_OPERAND_REG;
        decoded->operands[0].reg = make_reg(rt, is_64);
        decoded->operands[1].type = ARM64_OPERAND_MEM;
        decoded->operands[1].mem.offset_imm = addr + imm19;
        decoded->operands[1].mem.mode = ARM64_ADDR_LITERAL;
        decoded->operand_count = 2;
        return true;
    }
    
    return false;
}

// MARK: - Data Processing (Immediate) Instruction Decoding

static bool decode_data_processing_imm(uint32_t ins, uint64_t addr, ARM64DecodedInstruction *decoded) {
    decoded->category = ARM64_INS_DATA_PROCESSING_IMM;
    
    bool is_64 = BIT(ins, 31);
    uint8_t op = BITS(ins, 23, 25);
    
    if (op == 0b000) {
        bool is_adrp = BIT(ins, 31);
        uint8_t rd = BITS(ins, 0, 4);
        uint32_t immlo = BITS(ins, 29, 30);
        uint32_t immhi = BITS(ins, 5, 23);
        int64_t imm = sign_extend((immhi << 2) | immlo, 21);
        
        decoded->opcode = is_adrp ? ARM64_OP_ADRP : ARM64_OP_ADR;
        
        decoded->operands[0].type = ARM64_OPERAND_REG;
        decoded->operands[0].reg = make_reg(rd, true);
        
        decoded->operands[1].type = ARM64_OPERAND_IMM;
        if (is_adrp) {
            decoded->operands[1].imm = (addr & ~0xFFFULL) + (imm << 12);
        } else {
            decoded->operands[1].imm = addr + imm;
        }
        
        decoded->operand_count = 2;
        return true;
    }
    
    if (op == 0b010 || op == 0b011) {
        bool is_sub = BIT(ins, 30);
        bool set_flags = BIT(ins, 29);
        
        uint8_t rd = BITS(ins, 0, 4);
        uint8_t rn = BITS(ins, 5, 9);
        uint16_t imm12 = BITS(ins, 10, 21);
        uint8_t shift = BIT(ins, 22) ? 12 : 0;
        
        if (is_sub) {
            decoded->opcode = set_flags ? ARM64_OP_SUBS : ARM64_OP_SUB;
        } else {
            decoded->opcode = set_flags ? ARM64_OP_ADDS : ARM64_OP_ADD;
        }
        
        if (set_flags && rd == 31) {
            decoded->opcode = is_sub ? ARM64_OP_CMP : ARM64_OP_CMN;
            decoded->operands[0].type = ARM64_OPERAND_REG;
            decoded->operands[0].reg = make_reg(rn, is_64);
            decoded->operands[1].type = ARM64_OPERAND_IMM;
            decoded->operands[1].imm = imm12 << shift;
            decoded->operand_count = 2;
        } else {
            decoded->operands[0].type = ARM64_OPERAND_REG;
            decoded->operands[0].reg = make_reg(rd, is_64);
            decoded->operands[1].type = ARM64_OPERAND_REG;
            decoded->operands[1].reg = make_reg(rn, is_64);
            decoded->operands[2].type = ARM64_OPERAND_IMM;
            decoded->operands[2].imm = imm12 << shift;
            decoded->operand_count = 3;
        }
        
        return true;
    }
    
    if (op == 0b100) {
        uint8_t opc = BITS(ins, 29, 30);
        uint8_t rd = BITS(ins, 0, 4);
        uint8_t rn = BITS(ins, 5, 9);
        uint8_t n = BIT(ins, 22);
        uint8_t immr = BITS(ins, 16, 21);
        uint8_t imms = BITS(ins, 10, 15);
        
        uint64_t immediate_value = 0;
        if (!decode_bitmask_immediate(n, immr, imms, is_64, &immediate_value)) {
            return false;
        }
        
        switch (opc) {
            case 0b00: decoded->opcode = ARM64_OP_AND; break;
            case 0b01: decoded->opcode = ARM64_OP_ORR; break;
            case 0b10: decoded->opcode = ARM64_OP_EOR; break;
            case 0b11: decoded->opcode = ARM64_OP_ANDS; break;
        }
        
        if (opc == 0b11 && rd == 31) {
            decoded->opcode = ARM64_OP_TST;
            decoded->operands[0].type = ARM64_OPERAND_REG;
            decoded->operands[0].reg = make_reg(rn, is_64);
            decoded->operand_count = 2;
        } else {
            decoded->operands[0].type = ARM64_OPERAND_REG;
            decoded->operands[0].reg = make_reg(rd, is_64);
            
            decoded->operands[1].type = ARM64_OPERAND_REG;
            decoded->operands[1].reg = make_reg(rn, is_64);
            
            decoded->operand_count = 3;
        }
        
        decoded->operands[decoded->operand_count - 1].type = ARM64_OPERAND_IMM;
        decoded->operands[decoded->operand_count - 1].imm = immediate_value;
        
        return true;
    }
    
    if (op == 0b101) {
        uint8_t opc = BITS(ins, 29, 30);
        uint8_t rd = BITS(ins, 0, 4);
        uint16_t imm16 = BITS(ins, 5, 20);
        uint8_t hw = BITS(ins, 21, 22);
        
        switch (opc) {
            case 0b00: decoded->opcode = ARM64_OP_MOVN; break;
            case 0b10: decoded->opcode = ARM64_OP_MOVZ; break;
            case 0b11: decoded->opcode = ARM64_OP_MOVK; break;
            default: return false;
        }
        
        decoded->operands[0].type = ARM64_OPERAND_REG;
        decoded->operands[0].reg = make_reg(rd, is_64);
        decoded->operands[1].type = ARM64_OPERAND_IMM;
        decoded->operands[1].imm = imm16;
        
        if (hw > 0) {
            decoded->operands[2].type = ARM64_OPERAND_IMM;
            decoded->operands[2].imm = hw * 16;
            decoded->operand_count = 3;
        } else {
            decoded->operand_count = 2;
        }
        
        return true;
    }
    
    if (op == 0b110) {
        uint8_t opc = BITS(ins, 29, 30);
        uint8_t rd = BITS(ins, 0, 4);
        uint8_t rn = BITS(ins, 5, 9);
        uint8_t immr = BITS(ins, 16, 21);
        uint8_t imms = BITS(ins, 10, 15);
        
        switch (opc) {
            case 0b00: decoded->opcode = ARM64_OP_SBFM; break;
            case 0b01: decoded->opcode = ARM64_OP_BFM; break;
            case 0b10: decoded->opcode = ARM64_OP_UBFM; break;
            default: return false;
        }
        
        decoded->operands[0].type = ARM64_OPERAND_REG;
        decoded->operands[0].reg = make_reg(rd, is_64);
        decoded->operands[1].type = ARM64_OPERAND_REG;
        decoded->operands[1].reg = make_reg(rn, is_64);
        decoded->operands[2].type = ARM64_OPERAND_IMM;
        decoded->operands[2].imm = immr;
        decoded->operands[3].type = ARM64_OPERAND_IMM;
        decoded->operands[3].imm = imms;
        decoded->operand_count = 4;
        return true;
    }
    
    return false;
}

// MARK: - Data Processing (Register) Instruction Decoding

static bool decode_data_processing_reg(uint32_t ins, uint64_t addr, ARM64DecodedInstruction *decoded) {
    decoded->category = ARM64_INS_DATA_PROCESSING_REG;
    
    bool is_64 = BIT(ins, 31);
    uint8_t op0 = BIT(ins, 30);
    uint8_t op1 = BIT(ins, 28);
    uint8_t op2 = BITS(ins, 21, 24);
    uint8_t op3 = BITS(ins, 10, 15);
    
    if (op1 == 0 && op2 == 0b0000) {
        bool is_sub = BIT(ins, 30);
        bool set_flags = BIT(ins, 29);
        
        uint8_t rd = BITS(ins, 0, 4);
        uint8_t rn = BITS(ins, 5, 9);
        uint8_t rm = BITS(ins, 16, 20);
        uint8_t shift = BITS(ins, 22, 23);
        uint8_t imm6 = BITS(ins, 10, 15);
        
        if (is_sub) {
            decoded->opcode = set_flags ? ARM64_OP_SUBS : ARM64_OP_SUB;
        } else {
            decoded->opcode = set_flags ? ARM64_OP_ADDS : ARM64_OP_ADD;
        }
        
        if (set_flags && rd == 31) {
            decoded->opcode = is_sub ? ARM64_OP_CMP : ARM64_OP_CMN;
            decoded->operands[0].type = ARM64_OPERAND_REG;
            decoded->operands[0].reg = make_reg(rn, is_64);
            decoded->operands[1].type = ARM64_OPERAND_REG;
            decoded->operands[1].reg = make_reg(rm, is_64);
            decoded->operand_count = 2;
        } else {
            decoded->operands[0].type = ARM64_OPERAND_REG;
            decoded->operands[0].reg = make_reg(rd, is_64);
            decoded->operands[1].type = ARM64_OPERAND_REG;
            decoded->operands[1].reg = make_reg(rn, is_64);
            decoded->operands[2].type = ARM64_OPERAND_REG;
            decoded->operands[2].reg = make_reg(rm, is_64);
            decoded->operand_count = 3;
        }
        
        return true;
    }
    
    if (op1 == 0 && (op2 == 0b0000 || op2 == 0b0001 || op2 == 0b0010 || op2 == 0b0011)) {
        uint8_t opc = BITS(ins, 29, 30);
        bool n = BIT(ins, 21);
        uint8_t rd = BITS(ins, 0, 4);
        uint8_t rn = BITS(ins, 5, 9);
        uint8_t rm = BITS(ins, 16, 20);
        
        if (opc == 0b00) {
            decoded->opcode = n ? ARM64_OP_BIC : ARM64_OP_AND;
        } else if (opc == 0b01) {
            decoded->opcode = n ? ARM64_OP_EON : ARM64_OP_ORR;
        } else if (opc == 0b10) {
            decoded->opcode = ARM64_OP_EOR;
        } else if (opc == 0b11) {
            decoded->opcode = n ? ARM64_OP_BIC : ARM64_OP_ANDS;
        }
        
        if (decoded->opcode == ARM64_OP_ORR && rn == 31) {
            decoded->opcode = ARM64_OP_MOV;
            decoded->operands[0].type = ARM64_OPERAND_REG;
            decoded->operands[0].reg = make_reg(rd, is_64);
            decoded->operands[1].type = ARM64_OPERAND_REG;
            decoded->operands[1].reg = make_reg(rm, is_64);
            decoded->operand_count = 2;
        } else {
            decoded->operands[0].type = ARM64_OPERAND_REG;
            decoded->operands[0].reg = make_reg(rd, is_64);
            decoded->operands[1].type = ARM64_OPERAND_REG;
            decoded->operands[1].reg = make_reg(rn, is_64);
            decoded->operands[2].type = ARM64_OPERAND_REG;
            decoded->operands[2].reg = make_reg(rm, is_64);
            decoded->operand_count = 3;
        }
        
        return true;
    }
    
    if (op1 == 1 && op2 == 0b0110) {
        uint8_t rd = BITS(ins, 0, 4);
        uint8_t rn = BITS(ins, 5, 9);
        uint8_t rm = BITS(ins, 16, 20);
        uint8_t opcode = BITS(ins, 10, 15);
        
        switch (opcode) {
            case 0b000010: decoded->opcode = ARM64_OP_UDIV; break;
            case 0b000011: decoded->opcode = ARM64_OP_SDIV; break;
            case 0b001000: decoded->opcode = ARM64_OP_LSL; break;
            case 0b001001: decoded->opcode = ARM64_OP_LSR; break;
            case 0b001010: decoded->opcode = ARM64_OP_ASR; break;
            case 0b001011: decoded->opcode = ARM64_OP_ROR; break;
            default: return false;
        }
        
        decoded->operands[0].type = ARM64_OPERAND_REG;
        decoded->operands[0].reg = make_reg(rd, is_64);
        decoded->operands[1].type = ARM64_OPERAND_REG;
        decoded->operands[1].reg = make_reg(rn, is_64);
        decoded->operands[2].type = ARM64_OPERAND_REG;
        decoded->operands[2].reg = make_reg(rm, is_64);
        decoded->operand_count = 3;
        return true;
    }
    
    if (op1 == 1 && (op2 & 0b1000)) {
        uint8_t op31 = BITS(ins, 15, 15);
        uint8_t o0 = BIT(ins, 15);
        uint8_t rd = BITS(ins, 0, 4);
        uint8_t rn = BITS(ins, 5, 9);
        uint8_t ra = BITS(ins, 10, 14);
        uint8_t rm = BITS(ins, 16, 20);
        
        if ((op2 & 0b0111) == 0b0000) {
            decoded->opcode = o0 ? ARM64_OP_MSUB : ARM64_OP_MADD;
            
            if (decoded->opcode == ARM64_OP_MADD && ra == 31) {
                decoded->opcode = ARM64_OP_MUL;
                decoded->operands[0].type = ARM64_OPERAND_REG;
                decoded->operands[0].reg = make_reg(rd, is_64);
                decoded->operands[1].type = ARM64_OPERAND_REG;
                decoded->operands[1].reg = make_reg(rn, is_64);
                decoded->operands[2].type = ARM64_OPERAND_REG;
                decoded->operands[2].reg = make_reg(rm, is_64);
                decoded->operand_count = 3;
            } else {
                decoded->operands[0].type = ARM64_OPERAND_REG;
                decoded->operands[0].reg = make_reg(rd, is_64);
                decoded->operands[1].type = ARM64_OPERAND_REG;
                decoded->operands[1].reg = make_reg(rn, is_64);
                decoded->operands[2].type = ARM64_OPERAND_REG;
                decoded->operands[2].reg = make_reg(rm, is_64);
                decoded->operands[3].type = ARM64_OPERAND_REG;
                decoded->operands[3].reg = make_reg(ra, is_64);
                decoded->operand_count = 4;
            }
            
            return true;
        }
    }
    
    return false;
}

// MARK: - Main Decoder

bool arm64dec_decode_instruction(uint32_t raw_instruction, uint64_t address, ARM64DecodedInstruction *decoded) {
    if (!decoded) return false;
    
    memset(decoded, 0, sizeof(ARM64DecodedInstruction));
    
    decoded->raw = raw_instruction;
    decoded->address = address;
    decoded->condition = ARM64_COND_AL;
    decoded->category = get_instruction_category(raw_instruction);
    
    bool success = false;
    switch (decoded->category) {
        case ARM64_INS_BRANCH:
            success = decode_branch_instruction(raw_instruction, address, decoded);
            break;
            
        case ARM64_INS_LOAD_STORE:
            success = decode_load_store_instruction(raw_instruction, address, decoded);
            break;
            
        case ARM64_INS_DATA_PROCESSING_IMM:
            success = decode_data_processing_imm(raw_instruction, address, decoded);
            break;
            
        case ARM64_INS_DATA_PROCESSING_REG:
            success = decode_data_processing_reg(raw_instruction, address, decoded);
            break;
            
        case ARM64_INS_DATA_PROCESSING_SIMD:
        case ARM64_INS_UNKNOWN:
        default:
            decoded->opcode = ARM64_OP_UNKNOWN;
            snprintf(decoded->mnemonic, sizeof(decoded->mnemonic), ".long");
            snprintf(decoded->operand_str, sizeof(decoded->operand_str), "0x%08x", raw_instruction);
            return false;
    }
    
    if (success) {
        const char *base_mnemonic = arm64dec_opcode_mnemonic(decoded->opcode);
        if (decoded->opcode == ARM64_OP_B_COND) {
            snprintf(decoded->mnemonic, sizeof(decoded->mnemonic), "b.%s",
                    arm64dec_condition_name(decoded->condition));
        } else {
            snprintf(decoded->mnemonic, sizeof(decoded->mnemonic), "%s", base_mnemonic);
        }
    }
    
    return success;
}

// MARK: - Formatting and Analysis

size_t arm64dec_format_instruction(const ARM64DecodedInstruction *decoded, char *buffer, size_t buffer_size) {
    if (!decoded || !buffer || buffer_size == 0) return 0;
    
    size_t written = 0;
    
    written += snprintf(buffer + written, buffer_size - written, "%-8s ", decoded->mnemonic);
    
    for (uint8_t i = 0; i < decoded->operand_count && written < buffer_size; i++) {
        if (i > 0) {
            written += snprintf(buffer + written, buffer_size - written, ", ");
        }
        
        const ARM64Operand *op = &decoded->operands[i];
        
        switch (op->type) {
            case ARM64_OPERAND_REG:
                written += snprintf(buffer + written, buffer_size - written, "%s",
                                  arm64dec_register_name(op->reg));
                break;
                
            case ARM64_OPERAND_IMM:
                written += snprintf(buffer + written, buffer_size - written, "#0x%llx",
                                  (unsigned long long)op->imm);
                break;
                
            case ARM64_OPERAND_LABEL:
                written += snprintf(buffer + written, buffer_size - written, "0x%llx",
                                  (unsigned long long)op->imm);
                break;
                
            case ARM64_OPERAND_MEM: {
                const ARM64MemoryOperand *mem = &op->mem;
                written += snprintf(buffer + written, buffer_size - written, "[%s",
                                  arm64dec_register_name(mem->base));
                
                if (mem->mode == ARM64_ADDR_LITERAL) {
                    written += snprintf(buffer + written, buffer_size - written, "]=0x%llx",
                                      (unsigned long long)mem->offset_imm);
                } else if (mem->mode == ARM64_ADDR_REG_OFFSET || mem->mode == ARM64_ADDR_REG_EXTENDED) {
                    written += snprintf(buffer + written, buffer_size - written, ", %s",
                                      arm64dec_register_name(mem->offset_reg));
                    if (mem->shift_amount > 0) {
                        written += snprintf(buffer + written, buffer_size - written, ", lsl #%d",
                                          mem->shift_amount);
                    }
                    written += snprintf(buffer + written, buffer_size - written, "]");
                } else if (mem->offset_imm != 0) {
                    written += snprintf(buffer + written, buffer_size - written, ", #%lld]",
                                      (long long)mem->offset_imm);
                } else {
                    written += snprintf(buffer + written, buffer_size - written, "]");
                }
                
                if (mem->mode == ARM64_ADDR_PRE_INDEX) {
                    written += snprintf(buffer + written, buffer_size - written, "!");
                } else if (mem->mode == ARM64_ADDR_POST_INDEX) {
                    written += snprintf(buffer + written, buffer_size - written - 1, ", #%lld",
                                      (long long)mem->offset_imm);
                }
                break;
            }
                
            case ARM64_OPERAND_NONE:
            default:
                break;
        }
    }
    
    return written;
}

bool arm64dec_get_branch_target(const ARM64DecodedInstruction *decoded, uint64_t *out_target) {
    if (!decoded || !out_target) return false;
    
    switch (decoded->opcode) {
        case ARM64_OP_B:
        case ARM64_OP_BL:
        case ARM64_OP_B_COND:
            if (decoded->operand_count > 0 && decoded->operands[0].type == ARM64_OPERAND_LABEL) {
                *out_target = decoded->operands[0].imm;
                return true;
            }
            break;
            
        case ARM64_OP_CBZ:
        case ARM64_OP_CBNZ:
            if (decoded->operand_count > 1 && decoded->operands[1].type == ARM64_OPERAND_LABEL) {
                *out_target = decoded->operands[1].imm;
                return true;
            }
            break;
            
        case ARM64_OP_TBZ:
        case ARM64_OP_TBNZ:
            if (decoded->operand_count > 2 && decoded->operands[2].type == ARM64_OPERAND_LABEL) {
                *out_target = decoded->operands[2].imm;
                return true;
            }
            break;
            
        default:
            break;
    }
    
    return false;
}

bool arm64dec_is_call(const ARM64DecodedInstruction *decoded) {
    return decoded && (decoded->opcode == ARM64_OP_BL || decoded->opcode == ARM64_OP_BLR);
}

bool arm64dec_is_return(const ARM64DecodedInstruction *decoded) {
    return decoded && decoded->opcode == ARM64_OP_RET;
}

bool arm64dec_is_conditional_branch(const ARM64DecodedInstruction *decoded) {
    if (!decoded) return false;
    
    switch (decoded->opcode) {
        case ARM64_OP_B_COND:
        case ARM64_OP_CBZ:
        case ARM64_OP_CBNZ:
        case ARM64_OP_TBZ:
        case ARM64_OP_TBNZ:
            return true;
        default:
            return false;
    }
}

