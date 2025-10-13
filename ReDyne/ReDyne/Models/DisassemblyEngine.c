#include "DisassemblyEngine.h"
#include <stdlib.h>
#include <string.h>

#pragma mark - String Helpers

const char* disasm_category_string(InstructionCategory category) {
    switch (category) {
        case INST_CATEGORY_DATA_PROCESSING: return "Data Processing";
        case INST_CATEGORY_LOAD_STORE: return "Load/Store";
        case INST_CATEGORY_BRANCH: return "Branch";
        case INST_CATEGORY_SYSTEM: return "System";
        case INST_CATEGORY_SIMD: return "SIMD";
        default: return "Unknown";
    }
}

const char* disasm_branch_type_string(BranchType type) {
    switch (type) {
        case BRANCH_CALL: return "Call";
        case BRANCH_UNCONDITIONAL: return "Unconditional";
        case BRANCH_CONDITIONAL: return "Conditional";
        case BRANCH_RETURN: return "Return";
        default: return "None";
    }
}

const char* arm64_register_name(uint8_t reg, bool is_64bit) {
    static const char* x_regs[] = {"X0", "X1", "X2", "X3", "X4", "X5", "X6", "X7",
                                    "X8", "X9", "X10", "X11", "X12", "X13", "X14", "X15",
                                    "X16", "X17", "X18", "X19", "X20", "X21", "X22", "X23",
                                    "X24", "X25", "X26", "X27", "X28", "X29", "X30", "SP"};
    static const char* w_regs[] = {"W0", "W1", "W2", "W3", "W4", "W5", "W6", "W7",
                                    "W8", "W9", "W10", "W11", "W12", "W13", "W14", "W15",
                                    "W16", "W17", "W18", "W19", "W20", "W21", "W22", "W23",
                                    "W24", "W25", "W26", "W27", "W28", "W29", "W30", "WSP"};
    
    if (reg > 31) return "???";
    return is_64bit ? x_regs[reg] : w_regs[reg];
}

const char* arm64_condition_string(uint8_t cond) {
    static const char* conditions[] = {"EQ", "NE", "CS", "CC", "MI", "PL", "VS", "VC",
                                        "HI", "LS", "GE", "LT", "GT", "LE", "AL", "NV"};
    return (cond < 16) ? conditions[cond] : "??";
}

#pragma mark - Context Management

DisassemblyContext* disasm_create(MachOContext *macho_ctx) {
    if (!macho_ctx) return NULL;
    
    DisassemblyContext *ctx = (DisassemblyContext*)calloc(1, sizeof(DisassemblyContext));
    if (!ctx) return NULL;
    
    ctx->macho_ctx = macho_ctx;
    
    switch (macho_ctx->header.cputype) {
        case CPU_TYPE_ARM64:
            ctx->arch = ARCH_ARM64;
            break;
        case CPU_TYPE_X86_64:
            ctx->arch = ARCH_X86_64;
            break;
        default:
            ctx->arch = ARCH_UNKNOWN;
            break;
    }
    
    return ctx;
}

void disasm_free(DisassemblyContext *ctx) {
    if (!ctx) return;
    if (ctx->code_data) free(ctx->code_data);
    if (ctx->instructions) free(ctx->instructions);
    free(ctx);
}

#pragma mark - Code Loading

bool disasm_load_section(DisassemblyContext *ctx, const char *section_name) {
    if (!ctx || !ctx->macho_ctx || !section_name) return false;
    
    MachOContext *mctx = ctx->macho_ctx;
    
    for (uint32_t i = 0; i < mctx->section_count; i++) {
        SectionInfo *sect = &mctx->sections[i];
        if (strncmp(sect->sectname, section_name, 16) == 0) {
            ctx->code_size = sect->size;
            ctx->code_base_addr = sect->addr;
            
            ctx->code_data = (uint8_t*)malloc(ctx->code_size);
            if (!ctx->code_data) return false;
            
            fseek(mctx->file, sect->offset, SEEK_SET);
            size_t read = fread(ctx->code_data, 1, ctx->code_size, mctx->file);
            if (read != ctx->code_size) {
                free(ctx->code_data);
                ctx->code_data = NULL;
                return false;
            }
            
            return true;
        }
    }
    
    return false;
}

#pragma mark - ARM64 Instruction Decoding

bool arm64_is_prologue(const DisassembledInstruction *inst) {
    if (strstr(inst->mnemonic, "STP") &&
        strstr(inst->operands, "X29") && 
        strstr(inst->operands, "X30") &&
        strstr(inst->operands, "#-")) {
        return true;
    }
    return false;
}

bool arm64_is_epilogue(const DisassembledInstruction *inst) {
    if (strstr(inst->mnemonic, "LDP") && strstr(inst->operands, "X29") && strstr(inst->operands, "X30")) {
        return true;
    }
    if (strcmp(inst->mnemonic, "RET") == 0) {
        return true;
    }
    return false;
}

bool disasm_arm64(uint32_t bytes, uint64_t address, DisassembledInstruction *inst) {
    memset(inst, 0, sizeof(DisassembledInstruction));
    inst->address = address;
    inst->raw_bytes = bytes;
    inst->length = 4;
    inst->is_valid = false;
    
    uint8_t op0 = (bytes >> 25) & 0xF;
    uint8_t op1 = (bytes >> 19) & 0x3F;
    
    if (((bytes >> 26) & 0x3F) == 0x5 || ((bytes >> 26) & 0x3F) == 0x25) {
        bool is_link = ((bytes >> 31) & 0x1) == 1;
        int32_t imm26 = bytes & 0x3FFFFFF;
        if (imm26 & 0x2000000) imm26 |= 0xFC000000;
        int64_t offset = (int64_t)imm26 * 4;
        
        strcpy(inst->mnemonic, is_link ? "BL" : "B");
        inst->branch_target = address + offset;
        inst->branch_offset = offset;
        inst->has_branch_target = true;
        inst->has_branch = true;
        inst->branch_type = is_link ? BRANCH_CALL : BRANCH_UNCONDITIONAL;
        
        snprintf(inst->operands, sizeof(inst->operands), "0x%llx", inst->branch_target);
        inst->category = INST_CATEGORY_BRANCH;
        inst->is_valid = true;
        inst->updates_pc = true;
        
        if (is_link) {
            inst->regs_written = (1U << 30);
        }
    }
    
    else if (((bytes >> 21) & 0x7FF) >= 0x6B0 && ((bytes >> 21) & 0x7FF) <= 0x6B3) {
        uint8_t rn = (bytes >> 5) & 0x1F;
        uint8_t opc = (bytes >> 21) & 0x3;
        
        if (opc == 0) strcpy(inst->mnemonic, "BR");
        else if (opc == 1) strcpy(inst->mnemonic, "BLR");
        else if (opc == 2) strcpy(inst->mnemonic, "RET");
        else strcpy(inst->mnemonic, "BRAA");
        
        if (opc == 2 && rn == 30) {
            strcpy(inst->operands, "");
        } else {
            snprintf(inst->operands, sizeof(inst->operands), "%s", arm64_register_name(rn, true));
        }
        
        inst->has_branch = true;
        inst->branch_type = (opc == 2) ? BRANCH_RETURN : ((opc == 1) ? BRANCH_CALL : BRANCH_UNCONDITIONAL);
        inst->category = INST_CATEGORY_BRANCH;
        inst->is_valid = true;
        inst->updates_pc = true;
        
        inst->regs_read = (1U << rn);
        if (opc == 1) {
            inst->regs_written = (1U << 30);
        } else if (opc == 2) {
            inst->is_function_end = true;
        }
    }
    
    else if (((bytes >> 22) & 0x3FF) >= 0x290 && ((bytes >> 22) & 0x3FF) <= 0x2BF) {
        bool is_load = ((bytes >> 22) & 0x1) == 1;
        bool is_64bit = ((bytes >> 31) & 0x1) == 1;
        uint8_t rt = bytes & 0x1F;
        uint8_t rt2 = (bytes >> 10) & 0x1F;
        uint8_t rn = (bytes >> 5) & 0x1F;
        int16_t imm7 = (bytes >> 15) & 0x7F;
        if (imm7 & 0x40) imm7 |= 0xFF80;
        int32_t offset = (int32_t)imm7 * (is_64bit ? 8 : 4);
        
        strcpy(inst->mnemonic, is_load ? "LDP" : "STP");
        
        uint8_t idx = (bytes >> 23) & 0x3;
        if (idx == 0x3) {
            snprintf(inst->operands, sizeof(inst->operands), "%s, %s, [%s, #%d]!",
                     arm64_register_name(rt, is_64bit),
                     arm64_register_name(rt2, is_64bit),
                     arm64_register_name(rn, true),
                     offset);
        } else if (idx == 0x1) {
            snprintf(inst->operands, sizeof(inst->operands), "%s, %s, [%s], #%d",
                     arm64_register_name(rt, is_64bit),
                     arm64_register_name(rt2, is_64bit),
                     arm64_register_name(rn, true),
                     offset);
        } else {
            snprintf(inst->operands, sizeof(inst->operands), "%s, %s, [%s, #%d]",
                     arm64_register_name(rt, is_64bit),
                     arm64_register_name(rt2, is_64bit),
                     arm64_register_name(rn, true),
                     offset);
        }
        
        inst->category = INST_CATEGORY_LOAD_STORE;
        inst->is_valid = true;
    }
    
    else if ((op0 & 0x8) == 0x8) {
        uint8_t opc = (bytes >> 29) & 0x7;
        
        if (((bytes >> 23) & 0x3F) == 0x22 || ((bytes >> 23) & 0x3F) == 0x32) {
            bool is_sub = ((bytes >> 30) & 0x1) == 1;
            bool is_64bit = ((bytes >> 31) & 0x1) == 1;
            uint8_t rd = bytes & 0x1F;
            uint8_t rn = (bytes >> 5) & 0x1F;
            uint16_t imm12 = (bytes >> 10) & 0xFFF;
            uint8_t shift = (bytes >> 22) & 0x3;
            uint32_t imm = imm12 << (shift * 12);
            
            strcpy(inst->mnemonic, is_sub ? "SUB" : "ADD");
            snprintf(inst->operands, sizeof(inst->operands), "%s, %s, #%u",
                     arm64_register_name(rd, is_64bit),
                     arm64_register_name(rn, is_64bit),
                     imm);
            inst->category = INST_CATEGORY_DATA_PROCESSING;
            inst->is_valid = true;
            inst->regs_read = (1U << rn);
            inst->regs_written = (1U << rd);
        }
        else if (((bytes >> 23) & 0x3F) == 0x25 || ((bytes >> 23) & 0x3F) == 0x05 || ((bytes >> 23) & 0x3F) == 0x35) {
            uint8_t opc = (bytes >> 29) & 0x3;
            bool is_64bit = ((bytes >> 31) & 0x1) == 1;
            uint8_t rd = bytes & 0x1F;
            uint16_t imm16 = (bytes >> 5) & 0xFFFF;
            
            if (opc == 0x2) strcpy(inst->mnemonic, "MOVZ");
            else if (opc == 0x0) strcpy(inst->mnemonic, "MOVN");
            else if (opc == 0x3) strcpy(inst->mnemonic, "MOVK");
            else strcpy(inst->mnemonic, "MOV");
            
            snprintf(inst->operands, sizeof(inst->operands), "%s, #0x%X",
                     arm64_register_name(rd, is_64bit), imm16);
            inst->category = INST_CATEGORY_DATA_PROCESSING;
            inst->is_valid = true;
            
            if (opc == 0x3) {
                inst->regs_read = (1U << rd);
                inst->regs_written = (1U << rd);
            } else {
                inst->regs_read = 0;
                inst->regs_written = (1U << rd);
            }
        }
    }
    
    else if ((op0 & 0xE) == 0xA) {
        
        if (((bytes >> 24) & 0xFF) == 0x54) {
            uint8_t cond = bytes & 0xF;
            int32_t imm19 = (bytes >> 5) & 0x7FFFF;
            if (imm19 & 0x40000) imm19 |= 0xFFF80000;
            int64_t offset = (int64_t)imm19 * 4;
            
            snprintf(inst->mnemonic, sizeof(inst->mnemonic), "B.%s", arm64_condition_string(cond));
            inst->branch_target = address + offset;
            inst->branch_offset = offset;
            inst->has_branch_target = true;
            inst->has_branch = true;
            inst->branch_type = BRANCH_CONDITIONAL;
            
            snprintf(inst->operands, sizeof(inst->operands), "0x%llx", inst->branch_target);
            inst->category = INST_CATEGORY_BRANCH;
            inst->is_valid = true;
            inst->updates_pc = true;
        }
        else if (((bytes >> 24) & 0x7F) == 0x34 || ((bytes >> 24) & 0x7F) == 0x35) {
            bool is_cbnz = ((bytes >> 24) & 0x1) == 1;
            bool is_64bit = ((bytes >> 31) & 0x1) == 1;
            uint8_t rt = bytes & 0x1F;
            int32_t imm19 = (bytes >> 5) & 0x7FFFF;
            if (imm19 & 0x40000) imm19 |= 0xFFF80000;
            int64_t offset = (int64_t)imm19 * 4;
            
            strcpy(inst->mnemonic, is_cbnz ? "CBNZ" : "CBZ");
            inst->branch_target = address + offset;
            inst->branch_offset = offset;
            inst->has_branch_target = true;
            inst->has_branch = true;
            inst->branch_type = BRANCH_CONDITIONAL;
            
            snprintf(inst->operands, sizeof(inst->operands), "%s, 0x%llx",
                     arm64_register_name(rt, is_64bit), inst->branch_target);
            inst->category = INST_CATEGORY_BRANCH;
            inst->is_valid = true;
            inst->updates_pc = true;
            inst->regs_read = (1U << rt);
        }
    }
    
    else if ((op0 & 0xB) == 0x8) {
        uint8_t size = (bytes >> 30) & 0x3;
        
        if ((bytes >> 24) == 0xB9 || (bytes >> 24) == 0xF9 ||
            (bytes >> 24) == 0x39 || (bytes >> 24) == 0x79) {
            bool is_load = ((bytes >> 22) & 0x1) == 1;
            bool is_64bit = (size == 0x3);
            uint8_t rt = bytes & 0x1F;
            uint8_t rn = (bytes >> 5) & 0x1F;
            uint16_t imm12 = (bytes >> 10) & 0xFFF;
            uint32_t offset = imm12 << size;
            
            strcpy(inst->mnemonic, is_load ? "LDR" : "STR");
            snprintf(inst->operands, sizeof(inst->operands), "%s, [%s, #%u]",
                     arm64_register_name(rt, is_64bit),
                     arm64_register_name(rn, true),
                     offset);
            inst->category = INST_CATEGORY_LOAD_STORE;
            inst->is_valid = true;
        }
        
        else if (((bytes >> 21) & 0x7FF) == 0x1C0 || ((bytes >> 21) & 0x7FF) == 0x1C1 ||
                 ((bytes >> 21) & 0x7FF) == 0x3C0 || ((bytes >> 21) & 0x7FF) == 0x3C1) {
            bool is_load = ((bytes >> 22) & 0x1) == 1;
            bool is_64bit = (size >= 0x2);
            uint8_t rt = bytes & 0x1F;
            uint8_t rn = (bytes >> 5) & 0x1F;
            int16_t imm9 = (bytes >> 12) & 0x1FF;
            if (imm9 & 0x100) imm9 |= 0xFE00;
            
            strcpy(inst->mnemonic, is_load ? "LDUR" : "STUR");
            snprintf(inst->operands, sizeof(inst->operands), "%s, [%s, #%d]",
                     arm64_register_name(rt, is_64bit),
                     arm64_register_name(rn, true),
                     imm9);
            inst->category = INST_CATEGORY_LOAD_STORE;
            inst->is_valid = true;
        }
        
        else if ((bytes >> 24) == 0x18 || (bytes >> 24) == 0x58 ||
                 (bytes >> 24) == 0x98 || (bytes >> 24) == 0xD8) {
            uint8_t rt = bytes & 0x1F;
            int32_t imm19 = (bytes >> 5) & 0x7FFFF;
            if (imm19 & 0x40000) imm19 |= 0xFFF80000;
            int64_t offset = (int64_t)imm19 * 4;
            uint64_t target = address + offset;
            
            strcpy(inst->mnemonic, "LDR");
            snprintf(inst->operands, sizeof(inst->operands), "%s, 0x%llx",
                     arm64_register_name(rt, true), target);
            inst->category = INST_CATEGORY_LOAD_STORE;
            inst->is_valid = true;
        }
    }
    
    else if ((op0 & 0xE) == 0xA) {
        if (((bytes >> 21) & 0xFF) >= 0x0 && ((bytes >> 21) & 0xFF) <= 0x77) {
            uint8_t opc = (bytes >> 29) & 0x3;
            bool is_64bit = ((bytes >> 31) & 0x1) == 1;
            uint8_t rd = bytes & 0x1F;
            uint8_t rn = (bytes >> 5) & 0x1F;
            uint8_t rm = (bytes >> 16) & 0x1F;
            bool N = ((bytes >> 21) & 0x1) == 1;
            
            if (opc == 0) strcpy(inst->mnemonic, N ? "BIC" : "AND");
            else if (opc == 1) strcpy(inst->mnemonic, N ? "ORN" : "ORR");
            else if (opc == 2) strcpy(inst->mnemonic, N ? "EON" : "EOR");
            else strcpy(inst->mnemonic, N ? "BICS" : "ANDS");
            
            if (!N && opc == 1 && rn == 31) {
                strcpy(inst->mnemonic, "MOV");
                snprintf(inst->operands, sizeof(inst->operands), "%s, %s",
                         arm64_register_name(rd, is_64bit),
                         arm64_register_name(rm, is_64bit));
            } else {
                snprintf(inst->operands, sizeof(inst->operands), "%s, %s, %s",
                         arm64_register_name(rd, is_64bit),
                         arm64_register_name(rn, is_64bit),
                         arm64_register_name(rm, is_64bit));
            }
            inst->category = INST_CATEGORY_DATA_PROCESSING;
            inst->is_valid = true;
        }
        
        else if (((bytes >> 21) & 0xFF) >= 0x1B && ((bytes >> 21) & 0xFF) <= 0x1F) {
            bool is_64bit = ((bytes >> 31) & 0x1) == 1;
            uint8_t rd = bytes & 0x1F;
            uint8_t rn = (bytes >> 5) & 0x1F;
            uint8_t rm = (bytes >> 16) & 0x1F;
            uint8_t ra = (bytes >> 10) & 0x1F;
            uint8_t op = (bytes >> 21) & 0x7;
            
            if (op == 0x0) strcpy(inst->mnemonic, "MADD");
            else if (op == 0x1) strcpy(inst->mnemonic, "MSUB");
            else if (op == 0x2) strcpy(inst->mnemonic, "SMULL");
            else if (op == 0x3) strcpy(inst->mnemonic, "SMULH");
            else if (op == 0x2) strcpy(inst->mnemonic, "UDIV");
            else if (op == 0x3) strcpy(inst->mnemonic, "SDIV");
            else strcpy(inst->mnemonic, "MUL");
            
            if (ra == 31 && op == 0x0) {
                strcpy(inst->mnemonic, "MUL");
                snprintf(inst->operands, sizeof(inst->operands), "%s, %s, %s",
                         arm64_register_name(rd, is_64bit),
                         arm64_register_name(rn, is_64bit),
                         arm64_register_name(rm, is_64bit));
            } else {
                snprintf(inst->operands, sizeof(inst->operands), "%s, %s, %s, %s",
                         arm64_register_name(rd, is_64bit),
                         arm64_register_name(rn, is_64bit),
                         arm64_register_name(rm, is_64bit),
                         arm64_register_name(ra, is_64bit));
            }
            inst->category = INST_CATEGORY_DATA_PROCESSING;
            inst->is_valid = true;
        }
    }
    
    else if (((bytes >> 24) & 0xFF) == 0xF1 || ((bytes >> 24) & 0xFF) == 0x71 ||
             ((bytes >> 24) & 0xFF) == 0xEB || ((bytes >> 24) & 0xFF) == 0x6B) {
        bool is_64bit = ((bytes >> 31) & 0x1) == 1;
        uint8_t rn = (bytes >> 5) & 0x1F;
        
        if (((bytes >> 24) & 0xFF) == 0xF1 || ((bytes >> 24) & 0xFF) == 0x71) {
            bool is_sub = ((bytes >> 30) & 0x1) == 1;
            uint16_t imm12 = (bytes >> 10) & 0xFFF;
            
            strcpy(inst->mnemonic, is_sub ? "CMP" : "CMN");
            snprintf(inst->operands, sizeof(inst->operands), "%s, #%u",
                     arm64_register_name(rn, is_64bit), imm12);
            inst->category = INST_CATEGORY_DATA_PROCESSING;
            inst->is_valid = true;
        }
        
        else if (((bytes >> 24) & 0xFF) == 0xEB || ((bytes >> 24) & 0xFF) == 0x6B) {
            bool is_sub = ((bytes >> 30) & 0x1) == 1;
            uint8_t rm = (bytes >> 16) & 0x1F;
            
            strcpy(inst->mnemonic, is_sub ? "CMP" : "CMN");
            snprintf(inst->operands, sizeof(inst->operands), "%s, %s",
                     arm64_register_name(rn, is_64bit),
                     arm64_register_name(rm, is_64bit));
            inst->category = INST_CATEGORY_DATA_PROCESSING;
            inst->is_valid = true;
        }
    }
    
    else if (((bytes >> 21) & 0x7FF) >= 0x69A && ((bytes >> 21) & 0x7FF) <= 0x69F) {
        bool is_64bit = ((bytes >> 31) & 0x1) == 1;
        uint8_t rd = bytes & 0x1F;
        uint8_t rn = (bytes >> 5) & 0x1F;
        uint8_t rm = (bytes >> 16) & 0x1F;
        uint8_t shift_type = (bytes >> 22) & 0x3;
        
        if (shift_type == 0x0) strcpy(inst->mnemonic, "LSL");
        else if (shift_type == 0x1) strcpy(inst->mnemonic, "LSR");
        else if (shift_type == 0x2) strcpy(inst->mnemonic, "ASR");
        else strcpy(inst->mnemonic, "ROR");
        
        snprintf(inst->operands, sizeof(inst->operands), "%s, %s, %s",
                 arm64_register_name(rd, is_64bit),
                 arm64_register_name(rn, is_64bit),
                 arm64_register_name(rm, is_64bit));
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
    }
    
    else if (((bytes >> 21) & 0x7FF) >= 0x3A2 && ((bytes >> 21) & 0x7FF) <= 0x3A3) {
        bool is_64bit = ((bytes >> 31) & 0x1) == 1;
        uint8_t rn = (bytes >> 5) & 0x1F;
        uint8_t rm = (bytes >> 16) & 0x1F;
        uint8_t nzcv = bytes & 0xF;
        uint8_t cond = (bytes >> 12) & 0xF;
        
        strcpy(inst->mnemonic, "CCMP");
        snprintf(inst->operands, sizeof(inst->operands), "%s, %s, #%u, %s",
                 arm64_register_name(rn, is_64bit),
                 arm64_register_name(rm, is_64bit),
                 nzcv,
                 arm64_condition_string(cond));
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
    }
    
    else if (bytes == 0xD503201F) {
        strcpy(inst->mnemonic, "NOP");
        inst->operands[0] = '\0';
        inst->category = INST_CATEGORY_SYSTEM;
        inst->is_valid = true;
    }
    else if ((bytes >> 12) == 0xD503301) {
        uint8_t crm = (bytes >> 8) & 0xF;
        uint8_t op2 = (bytes >> 5) & 0x7;
        
        if (crm == 0x0 && op2 == 0x1) strcpy(inst->mnemonic, "YIELD");
        else if (crm == 0x0 && op2 == 0x2) strcpy(inst->mnemonic, "WFE");
        else if (crm == 0x0 && op2 == 0x3) strcpy(inst->mnemonic, "WFI");
        else if (crm == 0x0 && op2 == 0x4) strcpy(inst->mnemonic, "SEV");
        else if (crm == 0x0 && op2 == 0x5) strcpy(inst->mnemonic, "SEVL");
        else strcpy(inst->mnemonic, "HINT");
        
        inst->operands[0] = '\0';
        inst->category = INST_CATEGORY_SYSTEM;
        inst->is_valid = true;
    }
    
    else if ((bytes >> 12) == 0xD503309) {
        uint8_t crm = (bytes >> 8) & 0xF;
        uint8_t op2 = (bytes >> 5) & 0x7;
        
        if (op2 == 0x4) strcpy(inst->mnemonic, "DSB");
        else if (op2 == 0x5) strcpy(inst->mnemonic, "DMB");
        else if (op2 == 0x6) strcpy(inst->mnemonic, "ISB");
        else strcpy(inst->mnemonic, "BARRIER");
        
        snprintf(inst->operands, sizeof(inst->operands), "#%u", crm);
        inst->category = INST_CATEGORY_SYSTEM;
        inst->is_valid = true;
    }
    
    if (!inst->is_valid) {
        uint8_t op0 = (bytes >> 25) & 0xF;
        
        if ((op0 & 0xB) == 0x8 || (op0 & 0xB) == 0x9) {
            bool is_load = ((bytes >> 22) & 0x1) == 1;
            uint8_t rt = bytes & 0x1F;
            uint8_t rn = (bytes >> 5) & 0x1F;
            uint8_t size = (bytes >> 30) & 0x3;
            bool is_64bit = (size >= 0x2);
            
            strcpy(inst->mnemonic, is_load ? "LDR" : "STR");
            snprintf(inst->operands, sizeof(inst->operands), "%s, [%s, ...]",
                     arm64_register_name(rt, is_64bit),
                     arm64_register_name(rn, true));
            inst->category = INST_CATEGORY_LOAD_STORE;
            inst->is_valid = true;
        }
        
        else if (op0 == 0xB) {
            uint8_t rd = bytes & 0x1F;
            uint8_t rn = (bytes >> 5) & 0x1F;
            uint8_t rm = (bytes >> 16) & 0x1F;
            bool is_64bit = ((bytes >> 31) & 0x1) == 1;
            
            strcpy(inst->mnemonic, "DP3SRC");
            snprintf(inst->operands, sizeof(inst->operands), "%s, %s, %s, ...",
                     arm64_register_name(rd, is_64bit),
                     arm64_register_name(rn, is_64bit),
                     arm64_register_name(rm, is_64bit));
            inst->category = INST_CATEGORY_DATA_PROCESSING;
            inst->is_valid = true;
        }
        
        else if ((op0 & 0x7) == 0x7 || (op0 & 0xE) == 0xE) {
            strcpy(inst->mnemonic, "SIMD");
            snprintf(inst->operands, sizeof(inst->operands), "...");
            inst->category = INST_CATEGORY_SIMD;
            inst->is_valid = true;
        }
        
        else if ((op0 & 0xE) == 0xA) {
            uint8_t rd = bytes & 0x1F;
            uint8_t rn = (bytes >> 5) & 0x1F;
            bool is_64bit = ((bytes >> 31) & 0x1) == 1;
            
            strcpy(inst->mnemonic, "DPREG");
            snprintf(inst->operands, sizeof(inst->operands), "%s, %s, ...",
                     arm64_register_name(rd, is_64bit),
                     arm64_register_name(rn, is_64bit));
            inst->category = INST_CATEGORY_DATA_PROCESSING;
            inst->is_valid = true;
        }
        
        else if (op0 == 0xD) {
            strcpy(inst->mnemonic, "SYS");
            snprintf(inst->operands, sizeof(inst->operands), "...");
            inst->category = INST_CATEGORY_SYSTEM;
            inst->is_valid = true;
        }
    }
    
    if (!inst->is_valid) {
        strcpy(inst->mnemonic, ".word");
        snprintf(inst->operands, sizeof(inst->operands), "0x%08X", bytes);
        inst->category = INST_CATEGORY_UNKNOWN;
        inst->is_valid = true;
    }
    
    snprintf(inst->full_disasm, sizeof(inst->full_disasm), "0x%llx: %s %s",
             inst->address, inst->mnemonic, inst->operands);
    
    inst->is_function_start = arm64_is_prologue(inst);
    inst->is_function_end = arm64_is_epilogue(inst);
    
    return inst->is_valid;
}

#pragma mark - x86_64 Disassembly

typedef struct {
    uint8_t mod;
    uint8_t reg;
    uint8_t rm;
} ModRM;

static ModRM decode_modrm(uint8_t byte) {
    ModRM modrm;
    modrm.mod = (byte >> 6) & 0x3;
    modrm.reg = (byte >> 3) & 0x7;
    modrm.rm = byte & 0x7;
    return modrm;
}

typedef struct {
    uint8_t scale;
    uint8_t index;
    uint8_t base;
} SIB;

static SIB decode_sib(uint8_t byte) {
    SIB sib;
    sib.scale = (byte >> 6) & 0x3;
    sib.index = (byte >> 3) & 0x7;
    sib.base = byte & 0x7;
    return sib;
}

static uint32_t calculate_x86_64_length(const uint8_t *bytes, uint32_t max_len, bool has_rex, uint8_t opcode, ModRM *modrm_out) {
    if (max_len < 2) return 1;
    
    uint32_t len = 1;
    if (has_rex) len++;
    
    bool has_modrm = false;
    
    if ((opcode >= 0x00 && opcode <= 0x3F) || 
        (opcode >= 0x80 && opcode <= 0x8F) ||
        (opcode >= 0xC0 && opcode <= 0xC7 && opcode != 0xC3) ||
        (opcode >= 0xD0 && opcode <= 0xD3) ||
        (opcode >= 0xF6 && opcode <= 0xF7) ||
        (opcode >= 0xFE && opcode <= 0xFF)) {
        has_modrm = true;
    }
    
    if (!has_modrm) return len;
    if (len >= max_len) return len;
    
    ModRM modrm = decode_modrm(bytes[len]);
    if (modrm_out) *modrm_out = modrm;
    len++;
    
    bool has_sib = (modrm.mod != 3 && modrm.rm == 4);
    if (has_sib) {
        if (len >= max_len) return len;
        len++;
    }
    
    if (modrm.mod == 1) {
        len += 1;
    } else if (modrm.mod == 2) {
        len += 4;
    } else if (modrm.mod == 0 && modrm.rm == 5) {
        len += 4;
    }
    
    return len;
}

bool disasm_x86_64(const uint8_t *bytes, uint64_t address, DisassembledInstruction *inst) {
    memset(inst, 0, sizeof(DisassembledInstruction));
    inst->address = address;
    inst->is_valid = false;
    inst->length = 1;
    
    uint32_t pos = 0;
    bool has_rex = false;
    uint8_t rex = 0;
    
    if (bytes[pos] >= 0x40 && bytes[pos] <= 0x4F) {
        has_rex = true;
        rex = bytes[pos];
        pos++;
    }
    
    uint8_t opcode = bytes[pos];
    pos++;
    
    ModRM modrm;
    bool has_modrm = false;
    
    if (opcode == 0xC3) {
        strcpy(inst->mnemonic, "RET");
        inst->has_branch = true;
        inst->branch_type = BRANCH_RETURN;
        inst->category = INST_CATEGORY_BRANCH;
        inst->is_valid = true;
        inst->is_function_end = true;
        inst->length = pos;
    }
    else if (opcode == 0xCB) {
        strcpy(inst->mnemonic, "RETF");
        inst->has_branch = true;
        inst->branch_type = BRANCH_RETURN;
        inst->category = INST_CATEGORY_BRANCH;
        inst->is_valid = true;
        inst->is_function_end = true;
        inst->length = pos;
    }
    else if (opcode == 0xC2) {
        strcpy(inst->mnemonic, "RET");
        if (pos + 2 <= 15) {
            uint16_t imm = *(uint16_t*)&bytes[pos];
            snprintf(inst->operands, sizeof(inst->operands), "0x%x", imm);
            inst->length = pos + 2;
        }
        inst->has_branch = true;
        inst->branch_type = BRANCH_RETURN;
        inst->category = INST_CATEGORY_BRANCH;
        inst->is_valid = true;
        inst->is_function_end = true;
    }
    else if (opcode == 0x90) {
        strcpy(inst->mnemonic, "NOP");
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
        inst->length = pos;
    }
    else if (opcode == 0xCC) {
        strcpy(inst->mnemonic, "INT3");
        inst->category = INST_CATEGORY_SYSTEM;
        inst->is_valid = true;
        inst->length = pos;
    }
    else if (opcode == 0xF4) {
        strcpy(inst->mnemonic, "HLT");
        inst->category = INST_CATEGORY_SYSTEM;
        inst->is_valid = true;
        inst->length = pos;
    }
    else if (opcode == 0xC9) {
        strcpy(inst->mnemonic, "LEAVE");
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
        inst->length = pos;
    }
    else if (opcode == 0x9C) {
        strcpy(inst->mnemonic, has_rex ? "PUSHFQ" : "PUSHF");
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
        inst->length = pos;
    }
    else if (opcode == 0x9D) {
        strcpy(inst->mnemonic, has_rex ? "POPFQ" : "POPF");
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
        inst->length = pos;
    }
    else if (opcode == 0x99) {
        strcpy(inst->mnemonic, has_rex ? "CQO" : "CDQ");
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
        inst->length = pos;
    }
    else if (opcode == 0xF5) {
        strcpy(inst->mnemonic, "CMC");
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
        inst->length = pos;
    }
    else if (opcode == 0xF8) {
        strcpy(inst->mnemonic, "CLC");
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
        inst->length = pos;
    }
    else if (opcode == 0xF9) {
        strcpy(inst->mnemonic, "STC");
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
        inst->length = pos;
    }

    else if (opcode >= 0x50 && opcode <= 0x57) {
        strcpy(inst->mnemonic, "PUSH");
        const char *regs64[] = {"rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi"};
        const char *regs64_rex[] = {"r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15"};
        
        uint8_t reg_idx = opcode - 0x50;
        if (has_rex && (rex & 0x01)) {
            snprintf(inst->operands, sizeof(inst->operands), "%s", regs64_rex[reg_idx]);
        } else {
            snprintf(inst->operands, sizeof(inst->operands), "%s", regs64[reg_idx]);
        }
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
        inst->length = pos;
        inst->regs_read = (1U << reg_idx);
    }

    else if (opcode >= 0x58 && opcode <= 0x5F) {
        strcpy(inst->mnemonic, "POP");
        const char *regs64[] = {"rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi"};
        const char *regs64_rex[] = {"r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15"};
        
        uint8_t reg_idx = opcode - 0x58;
        if (has_rex && (rex & 0x01)) {
            snprintf(inst->operands, sizeof(inst->operands), "%s", regs64_rex[reg_idx]);
        } else {
            snprintf(inst->operands, sizeof(inst->operands), "%s", regs64[reg_idx]);
        }
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
        inst->length = pos;
        inst->regs_written = (1U << reg_idx);
    }
    
    else if (opcode == 0xE9) {
        strcpy(inst->mnemonic, "JMP");
        if (pos + 4 <= 15) {
            int32_t offset = *(int32_t*)&bytes[pos];
            inst->branch_target = address + pos + 4 + offset;
            inst->has_branch_target = true;
            inst->has_branch = true;
            snprintf(inst->operands, sizeof(inst->operands), "0x%llx", inst->branch_target);
            inst->branch_type = BRANCH_UNCONDITIONAL;
            inst->category = INST_CATEGORY_BRANCH;
            inst->is_valid = true;
            inst->length = pos + 4;
            inst->updates_pc = true;
        }
    }

    else if (opcode == 0xEB) {
        strcpy(inst->mnemonic, "JMP");
        if (pos < 15) {
            int8_t offset = (int8_t)bytes[pos];
            inst->branch_target = address + pos + 1 + offset;
            inst->has_branch_target = true;
            inst->has_branch = true;
            snprintf(inst->operands, sizeof(inst->operands), "0x%llx", inst->branch_target);
            inst->branch_type = BRANCH_UNCONDITIONAL;
            inst->category = INST_CATEGORY_BRANCH;
            inst->is_valid = true;
            inst->length = pos + 1;
            inst->updates_pc = true;
        }
    }

    else if (opcode == 0xE8) {
        strcpy(inst->mnemonic, "CALL");
        if (pos + 4 <= 15) {
            int32_t offset = *(int32_t*)&bytes[pos];
            inst->branch_target = address + pos + 4 + offset;
            inst->has_branch_target = true;
            inst->has_branch = true;
            snprintf(inst->operands, sizeof(inst->operands), "0x%llx", inst->branch_target);
            inst->branch_type = BRANCH_CALL;
            inst->category = INST_CATEGORY_BRANCH;
            inst->is_valid = true;
            inst->length = pos + 4;
            inst->updates_pc = true;
        }
    }

    else if (opcode >= 0x70 && opcode <= 0x7F) {
        const char *cond[] = {
            "JO", "JNO", "JB", "JAE", "JE", "JNE", "JBE", "JA",
            "JS", "JNS", "JP", "JNP", "JL", "JGE", "JLE", "JG"
        };
        strcpy(inst->mnemonic, cond[opcode - 0x70]);
        
        if (pos < 15) {
            int8_t offset = (int8_t)bytes[pos];
            inst->branch_target = address + pos + 1 + offset;
            inst->branch_offset = offset;
            inst->has_branch_target = true;
            inst->has_branch = true;
            inst->branch_type = BRANCH_CONDITIONAL;
            
            snprintf(inst->operands, sizeof(inst->operands), "0x%llx", inst->branch_target);
            inst->category = INST_CATEGORY_BRANCH;
            inst->is_valid = true;
            inst->length = pos + 1;
            inst->updates_pc = true;
        }
    }

    else if (opcode == 0x0F && inst->length < 15) {
        uint8_t opcode2 = bytes[1];
        inst->length = 2;
        
        if (opcode2 >= 0x80 && opcode2 <= 0x8F) {
            const char *cond[] = {
                "JO", "JNO", "JB", "JNB", "JZ", "JNZ", "JBE", "JNBE",
                "JS", "JNS", "JP", "JNP", "JL", "JNL", "JLE", "JNLE"
            };
            strcpy(inst->mnemonic, cond[opcode2 - 0x80]);
            int32_t offset = *(int32_t*)&bytes[2];
            inst->branch_target = address + 6 + offset;
            inst->has_branch_target = true;
            inst->has_branch = true;
            snprintf(inst->operands, sizeof(inst->operands), "0x%llx", inst->branch_target);
            inst->branch_type = BRANCH_CONDITIONAL;
            inst->category = INST_CATEGORY_BRANCH;
            inst->is_valid = true;
            inst->length = 6;
        }

        else if (opcode2 >= 0x90 && opcode2 <= 0x9F) {
            const char *cond[] = {
                "SETO", "SETNO", "SETB", "SETNB", "SETZ", "SETNZ", "SETBE", "SETNBE",
                "SETS", "SETNS", "SETP", "SETNP", "SETL", "SETNL", "SETLE", "SETNLE"
            };
            strcpy(inst->mnemonic, cond[opcode2 - 0x90]);
            strcpy(inst->operands, "r/m8");
            inst->length = 3;
            
            inst->category = INST_CATEGORY_DATA_PROCESSING;
            inst->is_valid = true;
        }

        else if (opcode2 == 0x0B) {
            strcpy(inst->mnemonic, "UD2");
            inst->category = INST_CATEGORY_SYSTEM;
            inst->is_valid = true;
            inst->length = 2;
        }
        else {
            snprintf(inst->mnemonic, sizeof(inst->mnemonic), ".byte");
            snprintf(inst->operands, sizeof(inst->operands), "0x0F 0x%02X", opcode2);
            inst->is_valid = true;
            inst->length = 2;
        }
    }

    else if (opcode >= 0xB8 && opcode <= 0xBF) {
        strcpy(inst->mnemonic, "MOV");
        const char *regs[] = {"eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi"};
        uint32_t imm = *(uint32_t*)&bytes[1];
        snprintf(inst->operands, sizeof(inst->operands), "%s, 0x%08X", regs[opcode - 0xB8], imm);
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
        inst->length = 5;
    }

    else if (opcode == 0xCD) {
        strcpy(inst->mnemonic, "INT");
        snprintf(inst->operands, sizeof(inst->operands), "0x%02X", bytes[1]);
        inst->category = INST_CATEGORY_SYSTEM;
        inst->is_valid = true;
        inst->length = 2;
    }

    else if (opcode == 0xC9) {
        strcpy(inst->mnemonic, "LEAVE");
        inst->category = INST_CATEGORY_DATA_PROCESSING;
        inst->is_valid = true;
        inst->length = 1;
    }

    else {
        strcpy(inst->mnemonic, ".byte");
        snprintf(inst->operands, sizeof(inst->operands), "0x%02X", opcode);
        inst->is_valid = true;
        inst->length = 1;
    }
    
    snprintf(inst->full_disasm, sizeof(inst->full_disasm), "0x%llx: %s %s",
             inst->address, inst->mnemonic,
             inst->operands[0] ? inst->operands : "");
    
    return inst->is_valid;
}

#pragma mark - High-Level Disassembly

bool disasm_instruction(DisassemblyContext *ctx, DisassembledInstruction *inst) {
    if (!ctx || !ctx->code_data || ctx->current_offset >= ctx->code_size) return false;
    
    uint64_t addr = ctx->code_base_addr + ctx->current_offset;
    
    if (ctx->arch == ARCH_ARM64) {
        if (ctx->current_offset + 4 > ctx->code_size) return false;
        uint32_t bytes = *(uint32_t*)(ctx->code_data + ctx->current_offset);
        
        if (ctx->macho_ctx && ctx->macho_ctx->header.is_swapped) {
            bytes = swap_uint32(bytes);
        }
        
        ctx->current_offset += 4;
        return disasm_arm64(bytes, addr, inst);
    } else if (ctx->arch == ARCH_X86_64) {
        bool result = disasm_x86_64(ctx->code_data + ctx->current_offset, addr, inst);
        ctx->current_offset += inst->length;
        return result;
    }
    
    return false;
}

uint32_t disasm_range(DisassemblyContext *ctx, uint64_t start_addr, uint64_t end_addr) {
    if (!ctx || start_addr >= end_addr) return 0;
    
    uint64_t start_offset = start_addr - ctx->code_base_addr;
    uint64_t end_offset = end_addr - ctx->code_base_addr;
    
    if (start_offset >= ctx->code_size) return 0;
    if (end_offset > ctx->code_size) end_offset = ctx->code_size;
    
    uint64_t range_size = end_offset - start_offset;
    uint32_t estimated = (uint32_t)(range_size / 4);
    if (estimated == 0) estimated = 1;
    
    ctx->instructions = (DisassembledInstruction*)malloc(estimated * sizeof(DisassembledInstruction));
    if (!ctx->instructions) return 0;
    
    ctx->instruction_capacity = estimated;
    ctx->instruction_count = 0;
    ctx->current_offset = start_offset;
    
    while (ctx->current_offset < end_offset) {
        if (ctx->instruction_count >= ctx->instruction_capacity) {
            ctx->instruction_capacity *= 2;
            DisassembledInstruction *new_ptr = (DisassembledInstruction*)realloc(
                ctx->instructions,
                ctx->instruction_capacity * sizeof(DisassembledInstruction)
            );
            if (!new_ptr) {
                return ctx->instruction_count;
            }
            ctx->instructions = new_ptr;
        }
        
        if (!disasm_instruction(ctx, &ctx->instructions[ctx->instruction_count])) {
            break;
        }
        ctx->instruction_count++;
    }
    
    return ctx->instruction_count;
}

uint32_t disasm_all(DisassemblyContext *ctx) {
    if (!ctx || !ctx->code_data) return 0;
    
    ctx->current_offset = 0;
    uint32_t estimated = ctx->code_size / 4;
    
    ctx->instructions = (DisassembledInstruction*)malloc(estimated * sizeof(DisassembledInstruction));
    if (!ctx->instructions) return 0;
    
    ctx->instruction_capacity = estimated;
    ctx->instruction_count = 0;
    
    while (ctx->current_offset < ctx->code_size) {
        if (ctx->instruction_count >= ctx->instruction_capacity) {
            ctx->instruction_capacity *= 2;
            ctx->instructions = (DisassembledInstruction*)realloc(ctx->instructions,
                                                                   ctx->instruction_capacity * sizeof(DisassembledInstruction));
            if (!ctx->instructions) return 0;
        }
        
        if (!disasm_instruction(ctx, &ctx->instructions[ctx->instruction_count])) {
            break;
        }
        ctx->instruction_count++;
    }
    
    return ctx->instruction_count;
}

uint32_t disasm_detect_functions(DisassemblyContext *ctx) {
    if (!ctx || !ctx->instructions) return 0;
    
    uint32_t func_count = 0;
    for (uint32_t i = 0; i < ctx->instruction_count; i++) {
        if (ctx->instructions[i].is_function_start) {
            func_count++;
        }
    }
    
    return func_count;
}

int32_t disasm_find_by_address(DisassemblyContext *ctx, uint64_t address) {
    if (!ctx || !ctx->instructions) return -1;
    
    for (uint32_t i = 0; i < ctx->instruction_count; i++) {
        if (ctx->instructions[i].address == address) {
            return (int32_t)i;
        }
    }
    
    return -1;
}

void disasm_format_instruction(const DisassembledInstruction *inst, char *buffer, size_t buffer_size) {
    if (!inst || !buffer) return;
    
    if (inst->comment[0] != '\0') {
        snprintf(buffer, buffer_size, "0x%llx: %08X  %-8s %-32s ; %s",
                 inst->address, inst->raw_bytes, inst->mnemonic, inst->operands, inst->comment);
    } else {
        snprintf(buffer, buffer_size, "0x%llx: %08X  %-8s %s",
                 inst->address, inst->raw_bytes, inst->mnemonic, inst->operands);
    }
}

