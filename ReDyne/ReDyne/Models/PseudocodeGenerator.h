#ifndef PseudocodeGenerator_h
#define PseudocodeGenerator_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "DisassemblyEngine.h"

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Instruction Format

typedef struct {
    uint64_t address;
    uint32_t raw_bytes;
    char mnemonic[32];
    char operands[128];
} PseudocodeInstruction;

// MARK: - Type System

typedef enum {
    TYPE_UNKNOWN,
    TYPE_VOID,
    TYPE_INT8,
    TYPE_INT16,
    TYPE_INT32,
    TYPE_INT64,
    TYPE_UINT8,
    TYPE_UINT16,
    TYPE_UINT32,
    TYPE_UINT64,
    TYPE_FLOAT32,
    TYPE_FLOAT64,
    TYPE_POINTER,
    TYPE_STRUCT,
    TYPE_ARRAY,
    TYPE_FUNCTION
} PseudoType;

typedef struct PseudoTypeInfo {
    PseudoType type;
    int size;
    int pointerLevel;
    char name[64];
    struct PseudoTypeInfo *elementType;
} PseudoTypeInfo;

// MARK: - Expression Tree

typedef enum {
    EXPR_CONSTANT,
    EXPR_VARIABLE,
    EXPR_BINARY_OP,
    EXPR_UNARY_OP,
    EXPR_MEMORY_ACCESS,
    EXPR_FUNCTION_CALL,
    EXPR_CAST,
    EXPR_TERNARY
} ExpressionType;

typedef enum {
    OP_ADD, OP_SUB, OP_MUL, OP_DIV,
    OP_MOD, OP_SHL, OP_SHR,
    OP_AND, OP_OR, OP_XOR,
    OP_EQ, OP_NE, OP_LT, OP_LE, OP_GT, OP_GE,
    OP_LAND, OP_LOR,
    OP_NEG, OP_NOT, OP_LNOT
} Operator;

typedef struct Expression Expression;

struct Expression {
    ExpressionType type;
    PseudoTypeInfo *dataType;
    
    union {
        struct {
            uint64_t value;
            bool isFloat;
            double floatValue;
        } constant;
        
        struct {
            char name[32];
            int version;
        } variable;
        
        struct {
            Operator op;
            Expression *left;
            Expression *right;
        } binaryOp;
        
        struct {
            Operator op;
            Expression *operand;
        } unaryOp;
        
        struct {
            Expression *base;
            Expression *offset;
            int size;
        } memAccess;
        
        struct {
            char name[64];
            Expression **args;
            int argCount;
        } call;
        
        struct {
            Expression *expr;
            PseudoTypeInfo *targetType;
        } cast;
        
        struct {
            Expression *condition;
            Expression *trueExpr;
            Expression *falseExpr;
        } ternary;
    };
};

// MARK: - Statement IR

typedef enum {
    STMT_ASSIGNMENT,
    STMT_IF,
    STMT_WHILE,
    STMT_DO_WHILE,
    STMT_FOR,
    STMT_RETURN,
    STMT_CALL,
    STMT_GOTO,
    STMT_LABEL,
    STMT_BREAK,
    STMT_CONTINUE,
    STMT_SWITCH,
    STMT_CASE,
    STMT_BLOCK
} StatementType;

typedef struct Statement Statement;

struct Statement {
    StatementType type;
    uint64_t address;
    int lineNumber;
    
    union {
        struct {
            char varName[32];
            Expression *value;
        } assignment;
        
        struct {
            Expression *condition;
            Statement **thenBlock;
            int thenCount;
            Statement **elseBlock;
            int elseCount;
        } ifStmt;
        
        struct {
            Expression *condition;
            Statement **body;
            int bodyCount;
        } whileStmt;
        
        struct {
            Statement *init;
            Expression *condition;
            Statement *update;
            Statement **body;
            int bodyCount;
        } forStmt;
        
        struct {
            Expression *value;
        } returnStmt;
        
        struct {
            Expression *call;
        } callStmt;
        
        struct {
            char label[32];
        } gotoLabel;
        
        struct {
            Expression *expr;
            Statement **cases;
            int caseCount;
        } switchStmt;
        
        struct {
            int64_t value;
            Statement **body;
            int bodyCount;
        } caseStmt;
        
        struct {
            Statement **statements;
            int count;
        } block;
    };
};

// MARK: - Function Representation

typedef struct {
    char name[128];
    uint64_t address;
    uint64_t size;
    char **paramNames;
    PseudoTypeInfo **paramTypes;
    int paramCount;
    PseudoTypeInfo *returnType;
    char **localNames;
    PseudoTypeInfo **localTypes;
    int localCount;
    Statement **statements;
    int statementCount;
    bool isExported;
    bool isVariadic;
    int stackSize;
} PseudoFunction;

// MARK: - Pseudocode Context

typedef struct {
    PseudoFunction **functions;
    int functionCount;
    PseudoTypeInfo **typeCache;
    int typeCacheSize;
    char **symbolNames;
    uint64_t *symbolAddresses;
    int symbolCount;
    bool generateComments;
    bool simplifyExpressions;
    bool reconstructLoops;
    bool useTypeCasting;
    int indentSize;
} PseudocodeContext;

// MARK: - Configuration & Output

typedef struct {
    int32_t verbosity_level;
    int32_t show_types;
    int32_t show_addresses;
    int32_t simplify_expressions;
    int32_t infer_types;
    int32_t use_simple_names;
    int32_t max_inlining_depth;
    int32_t collapse_constants;
} PseudocodeConfig;

typedef enum {
    HIGHLIGHT_KEYWORD,
    HIGHLIGHT_TYPE,
    HIGHLIGHT_VARIABLE,
    HIGHLIGHT_CONSTANT,
    HIGHLIGHT_COMMENT,
    HIGHLIGHT_FUNCTION,
    HIGHLIGHT_OPERATOR,
    HIGHLIGHT_REGISTER,
    HIGHLIGHT_ADDRESS
} SyntaxHighlightType;

typedef struct {
    int start;
    int length;
    SyntaxHighlightType type;
} SyntaxHighlight;

typedef struct {
    char function_signature[256];
    char *pseudocode;
    int instruction_count;
    int basic_block_count;
    int variable_count;
    int complexity;
    int loop_count;
    int conditional_count;
    SyntaxHighlight *syntax_highlights;
    int highlight_count;
} PseudocodeGeneratorOutput;

// MARK: - Generator Interface (High-Level API)

typedef struct PseudocodeGenerator PseudocodeGenerator;

PseudocodeGenerator* pseudocode_generator_create(void);
void pseudocode_generator_destroy(PseudocodeGenerator *gen);
void pseudocode_generator_set_config(PseudocodeGenerator *gen, PseudocodeConfig *config);
void pseudocode_generator_add_instruction(PseudocodeGenerator *gen, PseudocodeInstruction *inst);
void pseudocode_generator_set_function_name(PseudocodeGenerator *gen, const char **name);
int pseudocode_generator_generate(PseudocodeGenerator *gen);
PseudocodeGeneratorOutput* pseudocode_generator_get_output(PseudocodeGenerator *gen);

// MARK: - API Functions

PseudocodeContext* pseudocode_create_context(void);
void pseudocode_free_context(PseudocodeContext *ctx);

PseudoFunction* pseudocode_generate_function(
    PseudocodeContext *ctx,
    const PseudocodeInstruction *instructions,
    int count,
    uint64_t startAddress
);

Expression* pseudocode_build_expression(
    PseudocodeContext *ctx,
    const PseudocodeInstruction *inst
);

PseudoTypeInfo* pseudocode_infer_type(
    PseudocodeContext *ctx,
    const Expression *expr
);

Statement** pseudocode_reconstruct_control_flow(
    PseudocodeContext *ctx,
    const PseudocodeInstruction *instructions,
    int count,
    int *outStatementCount
);

char* pseudocode_generate_c_like(
    PseudocodeContext *ctx,
    const PseudoFunction *function
);

char* pseudocode_generate_python_like(
    PseudocodeContext *ctx,
    const PseudoFunction *function
);

void pseudocode_optimize_expression(Expression *expr);
void pseudocode_simplify_statements(Statement **statements, int count);
char* pseudocode_format_type(const PseudoTypeInfo *type);
char* pseudocode_format_expression(const Expression *expr);
void pseudocode_free_expression(Expression *expr);
void pseudocode_free_statement(Statement *stmt);
void pseudocode_free_function(PseudoFunction *func);

#ifdef __cplusplus
}
#endif

#endif

