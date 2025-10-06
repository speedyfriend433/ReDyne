#ifndef ControlFlowGraph_h
#define ControlFlowGraph_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "DisassemblyEngine.h"

#pragma mark - Basic Block Structure

typedef enum {
    EDGE_UNCONDITIONAL,
    EDGE_CONDITIONAL_TRUE,
    EDGE_CONDITIONAL_FALSE,
    EDGE_CALL,
    EDGE_RETURN
} EdgeType;

typedef struct BasicBlock {
    uint64_t start_address;
    uint64_t end_address;
    uint32_t instruction_start;
    uint32_t instruction_count;
    
    struct BasicBlock **successors;
    uint32_t successor_count;
    EdgeType *successor_edge_types;
    
    struct BasicBlock **predecessors;
    uint32_t predecessor_count;
    
    bool is_entry;
    bool is_exit;
    bool is_loop_header;
    bool visited;
    
    struct BasicBlock *immediate_dominator;
    uint32_t dom_level;
    
} BasicBlock;

typedef struct {
    DisassemblyContext *disasm_ctx;
    
    BasicBlock *blocks;
    uint32_t block_count;
    uint32_t block_capacity;
    
    BasicBlock *entry_block;
    BasicBlock **exit_blocks;
    uint32_t exit_block_count;
    uint64_t function_start;
    uint64_t function_end;
    
} CFGContext;

#pragma mark - Function Declarations

CFGContext* cfg_create(DisassemblyContext *disasm_ctx);

bool cfg_build_function(CFGContext *ctx, uint64_t func_start, uint64_t func_end);

uint32_t cfg_build_all(CFGContext *ctx);

BasicBlock* cfg_add_block(CFGContext *ctx, uint64_t start_addr, uint64_t end_addr);

bool cfg_add_edge(BasicBlock *from, BasicBlock *to, EdgeType edge_type);

BasicBlock* cfg_find_block(CFGContext *ctx, uint64_t address);

bool cfg_compute_dominance(CFGContext *ctx);

uint32_t cfg_detect_loops(CFGContext *ctx);

bool cfg_export_dot(CFGContext *ctx, FILE *output);

const char* cfg_edge_type_string(EdgeType type);

void cfg_free(CFGContext *ctx);

#endif

