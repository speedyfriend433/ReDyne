#ifndef ARM64InstructionDecoder_h
#define ARM64InstructionDecoder_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Instruction Types and Formats

typedef enum {
    ARM64_INS_UNKNOWN = 0,
    ARM64_INS_DATA_PROCESSING_IMM,
    ARM64_INS_BRANCH,
    ARM64_INS_LOAD_STORE,
    ARM64_INS_DATA_PROCESSING_REG,
    ARM64_INS_DATA_PROCESSING_SIMD,
} ARM64InstructionCategory;

typedef enum {
    ARM64_OP_UNKNOWN = 0,
    ARM64_OP_B,
    ARM64_OP_BL,
    ARM64_OP_BR,
    ARM64_OP_BLR,
    ARM64_OP_RET,
    ARM64_OP_CBZ,
    ARM64_OP_CBNZ,
    ARM64_OP_TBZ,
    ARM64_OP_TBNZ,
    ARM64_OP_B_COND,
    ARM64_OP_LDR,
    ARM64_OP_LDRB,
    ARM64_OP_LDRH,
    ARM64_OP_LDRSB,
    ARM64_OP_LDRSH,
    ARM64_OP_LDRSW,
    ARM64_OP_STR,
    ARM64_OP_STRB,
    ARM64_OP_STRH,
    ARM64_OP_LDP,
    ARM64_OP_STP,
    ARM64_OP_LDUR,
    ARM64_OP_STUR,
    ARM64_OP_ADD,
    ARM64_OP_ADDS,
    ARM64_OP_SUB,
    ARM64_OP_SUBS,
    ARM64_OP_MUL,
    ARM64_OP_MADD,
    ARM64_OP_MSUB,
    ARM64_OP_SMULL,
    ARM64_OP_UMULL,
    ARM64_OP_SDIV,
    ARM64_OP_UDIV,
    ARM64_OP_AND,
    ARM64_OP_ANDS,
    ARM64_OP_ORR,
    ARM64_OP_EOR,
    ARM64_OP_BIC,
    ARM64_OP_EON,
    ARM64_OP_TST,
    ARM64_OP_MOV,
    ARM64_OP_MOVZ,
    ARM64_OP_MOVN,
    ARM64_OP_MOVK,
    ARM64_OP_MVN,
    ARM64_OP_LSL,
    ARM64_OP_LSR,
    ARM64_OP_ASR,
    ARM64_OP_ROR,
    ARM64_OP_CMP,
    ARM64_OP_CMN,
    ARM64_OP_UBFM,
    ARM64_OP_SBFM,
    ARM64_OP_BFM,
    ARM64_OP_EXTR,
    ARM64_OP_NOP,
    ARM64_OP_HLT,
    ARM64_OP_BRK,
    ARM64_OP_SVC,
    ARM64_OP_HVC,
    ARM64_OP_SMC,
    ARM64_OP_ADRP,
    ARM64_OP_ADR,
    ARM64_OP_SXT,
    ARM64_OP_UXT,
} ARM64Opcode;

typedef enum {
    ARM64_COND_EQ = 0x0,
    ARM64_COND_NE = 0x1,
    ARM64_COND_CS = 0x2,
    ARM64_COND_CC = 0x3,
    ARM64_COND_MI = 0x4,
    ARM64_COND_PL = 0x5,
    ARM64_COND_VS = 0x6,
    ARM64_COND_VC = 0x7,
    ARM64_COND_HI = 0x8,
    ARM64_COND_LS = 0x9,
    ARM64_COND_GE = 0xA,
    ARM64_COND_LT = 0xB,
    ARM64_COND_GT = 0xC,
    ARM64_COND_LE = 0xD,
    ARM64_COND_AL = 0xE,
    ARM64_COND_NV = 0xF,
} ARM64Condition;

typedef struct {
    uint8_t num;
    bool is_64bit;
    bool is_sp;
    bool is_zero;
} ARM64Register;

typedef enum {
    ARM64_OPERAND_NONE = 0,
    ARM64_OPERAND_REG,
    ARM64_OPERAND_IMM,
    ARM64_OPERAND_MEM,
    ARM64_OPERAND_LABEL,
} ARM64OperandType;

typedef enum {
    ARM64_ADDR_NONE = 0,
    ARM64_ADDR_OFFSET,
    ARM64_ADDR_PRE_INDEX,
    ARM64_ADDR_POST_INDEX,
    ARM64_ADDR_REG_OFFSET,
    ARM64_ADDR_REG_EXTENDED,
    ARM64_ADDR_LITERAL,
} ARM64AddressingMode;

typedef struct {
    ARM64Register base;
    ARM64Register offset_reg;
    int64_t offset_imm;
    ARM64AddressingMode mode;
    uint8_t extend_type;
    uint8_t shift_amount;
} ARM64MemoryOperand;

typedef struct {
    ARM64OperandType type;
    union {
        ARM64Register reg;
        int64_t imm;
        ARM64MemoryOperand mem;
    };
} ARM64Operand;

typedef struct {
    uint32_t raw;
    uint64_t address;
    ARM64InstructionCategory category;
    ARM64Opcode opcode;
    ARM64Condition condition;
    ARM64Operand operands[4];
    uint8_t operand_count;
    char mnemonic[32];
    char operand_str[256];
} ARM64DecodedInstruction;

// MARK: - Decoder API

bool arm64dec_decode_instruction(
    uint32_t raw_instruction,
    uint64_t address,
    ARM64DecodedInstruction *out_decoded
);

size_t arm64dec_format_instruction(
    const ARM64DecodedInstruction *decoded,
    char *buffer,
    size_t buffer_size
);

bool arm64dec_get_branch_target(
    const ARM64DecodedInstruction *decoded,
    uint64_t *out_target
);

bool arm64dec_is_call(const ARM64DecodedInstruction *decoded);
bool arm64dec_is_return(const ARM64DecodedInstruction *decoded);
bool arm64dec_is_conditional_branch(const ARM64DecodedInstruction *decoded);

// MARK: - Helper Functions

const char* arm64dec_register_name(ARM64Register reg);
const char* arm64dec_condition_name(ARM64Condition cond);
const char* arm64dec_opcode_mnemonic(ARM64Opcode opcode);

#ifdef __cplusplus
}
#endif

#endif

