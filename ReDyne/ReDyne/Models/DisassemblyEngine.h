#ifndef DisassemblyEngine_h
#define DisassemblyEngine_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "MachOHeader.h"

#pragma mark - Constants

#define MAX_INSTRUCTION_LENGTH 16
#define MAX_DISASM_STRING 256
#define MAX_OPERAND_STRING 128

typedef enum {
    ARCH_ARM64,
    ARCH_X86_64,
    ARCH_UNKNOWN
} Architecture;

typedef enum {
    INST_CATEGORY_DATA_PROCESSING,
    INST_CATEGORY_LOAD_STORE,
    INST_CATEGORY_BRANCH,
    INST_CATEGORY_SYSTEM,
    INST_CATEGORY_SIMD,
    INST_CATEGORY_UNKNOWN
} InstructionCategory;

typedef enum {
    BRANCH_NONE,
    BRANCH_CALL,
    BRANCH_UNCONDITIONAL,
    BRANCH_CONDITIONAL,
    BRANCH_RETURN
} BranchType;

#pragma mark - Instruction Structure

typedef struct {
    uint64_t address;
    uint32_t raw_bytes;
    uint8_t length;
    
    char mnemonic[32];
    char operands[MAX_OPERAND_STRING];
    char full_disasm[MAX_DISASM_STRING];
    char comment[128];
    
    InstructionCategory category;
    BranchType branch_type;
    
    bool has_branch_target;
    uint64_t branch_target;
    int64_t branch_offset;
    uint32_t regs_read;
    uint32_t regs_written;
    
    bool is_valid;
    bool is_function_start;
    bool is_function_end;
    bool updates_pc;
    bool has_branch;
    
} DisassembledInstruction;

typedef struct {
    MachOContext *macho_ctx;
    Architecture arch;
    
    uint8_t *code_data;
    uint64_t code_size;
    uint64_t code_base_addr;
    uint64_t current_offset;
    
    DisassembledInstruction *instructions;
    uint32_t instruction_count;
    uint32_t instruction_capacity;
    
} DisassemblyContext;

#pragma mark - Function Declarations

DisassemblyContext* disasm_create(MachOContext *macho_ctx);

bool disasm_load_section(DisassemblyContext *ctx, const char *section_name);

bool disasm_instruction(DisassemblyContext *ctx, DisassembledInstruction *inst);

uint32_t disasm_range(DisassemblyContext *ctx, uint64_t start_addr, uint64_t end_addr);

uint32_t disasm_all(DisassemblyContext *ctx);

bool disasm_arm64(uint32_t bytes, uint64_t address, DisassembledInstruction *inst);

bool disasm_x86_64(const uint8_t *bytes, uint64_t address, DisassembledInstruction *inst);

uint32_t disasm_detect_functions(DisassemblyContext *ctx);

int32_t disasm_find_by_address(DisassemblyContext *ctx, uint64_t address);

const char* disasm_category_string(InstructionCategory category);

const char* disasm_branch_type_string(BranchType type);

void disasm_format_instruction(const DisassembledInstruction *inst, char *buffer, size_t buffer_size);

void disasm_free(DisassemblyContext *ctx);

#pragma mark - ARM64 Specific Helpers

const char* arm64_register_name(uint8_t reg, bool is_64bit);

const char* arm64_condition_string(uint8_t cond);

bool arm64_is_prologue(const DisassembledInstruction *inst);

bool arm64_is_epilogue(const DisassembledInstruction *inst);

#endif

