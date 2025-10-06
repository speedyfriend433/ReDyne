#include "ControlFlowGraph.h"
#include <stdlib.h>
#include <string.h>

#pragma mark - String Helpers

const char* cfg_edge_type_string(EdgeType type) {
    switch (type) {
        case EDGE_UNCONDITIONAL: return "Unconditional";
        case EDGE_CONDITIONAL_TRUE: return "True";
        case EDGE_CONDITIONAL_FALSE: return "False";
        case EDGE_CALL: return "Call";
        case EDGE_RETURN: return "Return";
        default: return "Unknown";
    }
}

#pragma mark - Context Management

CFGContext* cfg_create(DisassemblyContext *disasm_ctx) {
    if (!disasm_ctx) return NULL;
    
    CFGContext *ctx = (CFGContext*)calloc(1, sizeof(CFGContext));
    if (!ctx) return NULL;
    
    ctx->disasm_ctx = disasm_ctx;
    ctx->block_capacity = 256;
    ctx->blocks = (BasicBlock*)calloc(ctx->block_capacity, sizeof(BasicBlock));
    
    if (!ctx->blocks) {
        free(ctx);
        return NULL;
    }
    
    return ctx;
}

void cfg_free(CFGContext *ctx) {
    if (!ctx) return;
    
    if (ctx->blocks) {
        for (uint32_t i = 0; i < ctx->block_count; i++) {
            if (ctx->blocks[i].successors) free(ctx->blocks[i].successors);
            if (ctx->blocks[i].successor_edge_types) free(ctx->blocks[i].successor_edge_types);
            if (ctx->blocks[i].predecessors) free(ctx->blocks[i].predecessors);
        }
        free(ctx->blocks);
    }
    
    if (ctx->exit_blocks) free(ctx->exit_blocks);
    
    free(ctx);
}

#pragma mark - Basic Block Management

BasicBlock* cfg_add_block(CFGContext *ctx, uint64_t start_addr, uint64_t end_addr) {
    if (!ctx || start_addr >= end_addr) return NULL;
    
    if (ctx->block_count >= ctx->block_capacity) {
        ctx->block_capacity *= 2;
        ctx->blocks = (BasicBlock*)realloc(ctx->blocks, ctx->block_capacity * sizeof(BasicBlock));
        if (!ctx->blocks) return NULL;
    }
    
    BasicBlock *block = &ctx->blocks[ctx->block_count++];
    memset(block, 0, sizeof(BasicBlock));
    
    block->start_address = start_addr;
    block->end_address = end_addr;
    
    return block;
}

bool cfg_add_edge(BasicBlock *from, BasicBlock *to, EdgeType edge_type) {
    if (!from || !to) return false;
    
    from->successor_count++;
    from->successors = (BasicBlock**)realloc(from->successors, from->successor_count * sizeof(BasicBlock*));
    from->successor_edge_types = (EdgeType*)realloc(from->successor_edge_types, from->successor_count * sizeof(EdgeType));
    
    if (!from->successors || !from->successor_edge_types) return false;
    
    from->successors[from->successor_count - 1] = to;
    from->successor_edge_types[from->successor_count - 1] = edge_type;
    
    to->predecessor_count++;
    to->predecessors = (BasicBlock**)realloc(to->predecessors, to->predecessor_count * sizeof(BasicBlock*));
    
    if (!to->predecessors) return false;
    
    to->predecessors[to->predecessor_count - 1] = from;
    
    return true;
}

BasicBlock* cfg_find_block(CFGContext *ctx, uint64_t address) {
    if (!ctx || !ctx->blocks) return NULL;
    
    for (uint32_t i = 0; i < ctx->block_count; i++) {
        if (address >= ctx->blocks[i].start_address && address < ctx->blocks[i].end_address) {
            return &ctx->blocks[i];
        }
    }
    
    return NULL;
}

#pragma mark - CFG Building

bool cfg_build_function(CFGContext *ctx, uint64_t func_start, uint64_t func_end) {
    if (!ctx || !ctx->disasm_ctx || !ctx->disasm_ctx->instructions) return false;
    
    ctx->function_start = func_start;
    ctx->function_end = func_end;
    
    bool *is_leader = (bool*)calloc(ctx->disasm_ctx->instruction_count, sizeof(bool));
    if (!is_leader) return false;
    
    is_leader[0] = true;
    
    for (uint32_t i = 0; i < ctx->disasm_ctx->instruction_count; i++) {
        DisassembledInstruction *inst = &ctx->disasm_ctx->instructions[i];
        
        if (inst->address < func_start || inst->address >= func_end) continue;
        
        if (inst->branch_type != BRANCH_NONE && inst->has_branch_target) {
            int32_t target_idx = disasm_find_by_address(ctx->disasm_ctx, inst->branch_target);
            if (target_idx >= 0) {
                is_leader[target_idx] = true;
            }
            
            if (i + 1 < ctx->disasm_ctx->instruction_count) {
                is_leader[i + 1] = true;
            }
        }
    }
    
    uint32_t block_start_idx = 0;
    for (uint32_t i = 1; i <= ctx->disasm_ctx->instruction_count; i++) {
        if (i == ctx->disasm_ctx->instruction_count || is_leader[i]) {
            if (i > block_start_idx) {
                uint64_t start_addr = ctx->disasm_ctx->instructions[block_start_idx].address;
                uint64_t end_addr = ctx->disasm_ctx->instructions[i - 1].address + 
                                    ctx->disasm_ctx->instructions[i - 1].length;
                
                if (start_addr >= func_start && start_addr < func_end) {
                    BasicBlock *block = cfg_add_block(ctx, start_addr, end_addr);
                    if (block) {
                        block->instruction_start = block_start_idx;
                        block->instruction_count = i - block_start_idx;
                        
                        if (block_start_idx == 0) {
                            block->is_entry = true;
                            ctx->entry_block = block;
                        }
                    }
                }
            }
            block_start_idx = i;
        }
    }
    
    for (uint32_t i = 0; i < ctx->block_count; i++) {
        BasicBlock *block = &ctx->blocks[i];
        
        uint32_t last_idx = block->instruction_start + block->instruction_count - 1;
        DisassembledInstruction *last_inst = &ctx->disasm_ctx->instructions[last_idx];
        
        if (last_inst->branch_type == BRANCH_UNCONDITIONAL || last_inst->branch_type == BRANCH_CALL) {
            if (last_inst->has_branch_target) {
                BasicBlock *target = cfg_find_block(ctx, last_inst->branch_target);
                if (target) {
                    EdgeType edge_type = (last_inst->branch_type == BRANCH_CALL) ? EDGE_CALL : EDGE_UNCONDITIONAL;
                    cfg_add_edge(block, target, edge_type);
                }
            }
            
            if (last_inst->branch_type == BRANCH_CALL && i + 1 < ctx->block_count) {
                cfg_add_edge(block, &ctx->blocks[i + 1], EDGE_UNCONDITIONAL);
            }
        } else if (last_inst->branch_type == BRANCH_CONDITIONAL) {
            if (last_inst->has_branch_target) {
                BasicBlock *target = cfg_find_block(ctx, last_inst->branch_target);
                if (target) {
                    cfg_add_edge(block, target, EDGE_CONDITIONAL_TRUE);
                }
            }
            
            if (i + 1 < ctx->block_count) {
                cfg_add_edge(block, &ctx->blocks[i + 1], EDGE_CONDITIONAL_FALSE);
            }
        } else if (last_inst->branch_type == BRANCH_RETURN) {
            block->is_exit = true;
        } else {
            if (i + 1 < ctx->block_count) {
                cfg_add_edge(block, &ctx->blocks[i + 1], EDGE_UNCONDITIONAL);
            }
        }
    }
    
    free(is_leader);
    return true;
}

uint32_t cfg_build_all(CFGContext *ctx) {
    if (!ctx || !ctx->disasm_ctx) return 0;
    
    uint64_t start = ctx->disasm_ctx->code_base_addr;
    uint64_t end = start + ctx->disasm_ctx->code_size;
    
    cfg_build_function(ctx, start, end);
    
    return ctx->block_count;
}

#pragma mark - Analysis

bool cfg_compute_dominance(CFGContext *ctx) {
    if (!ctx || !ctx->blocks || ctx->block_count == 0) return false;
    
    uint32_t **dom_sets = calloc(ctx->block_count, sizeof(uint32_t*));
    if (!dom_sets) return false;
    
    uint32_t words_needed = (ctx->block_count + 31) / 32;
    for (uint32_t i = 0; i < ctx->block_count; i++) {
        dom_sets[i] = calloc(words_needed, sizeof(uint32_t));
        if (!dom_sets[i]) {
            for (uint32_t j = 0; j < i; j++) free(dom_sets[j]);
            free(dom_sets);
            return false;
        }
    }
    
#define SET_BIT(set, bit) ((set)[(bit) / 32] |= (1U << ((bit) % 32)))
#define CLEAR_BIT(set, bit) ((set)[(bit) / 32] &= ~(1U << ((bit) % 32)))
#define TEST_BIT(set, bit) (((set)[(bit) / 32] & (1U << ((bit) % 32))) != 0)

    SET_BIT(dom_sets[0], 0);
    for (uint32_t i = 1; i < ctx->block_count; i++) {
        for (uint32_t j = 0; j < ctx->block_count; j++) {
            SET_BIT(dom_sets[i], j);
        }
    }
    
    bool changed = true;
    int iterations = 0;
    while (changed && iterations < 100) {
        changed = false;
        iterations++;
        
        for (uint32_t i = 1; i < ctx->block_count; i++) {
            BasicBlock *block = &ctx->blocks[i];
            
            uint32_t *new_doms = calloc(words_needed, sizeof(uint32_t));
            if (!new_doms) continue;
            
            for (uint32_t w = 0; w < words_needed; w++) {
                new_doms[w] = 0xFFFFFFFF;
            }
            
            if (block->predecessor_count > 0) {
                for (uint32_t p = 0; p < block->predecessor_count; p++) {
                    BasicBlock *pred = block->predecessors[p];
                    int pred_idx = -1;
                    for (uint32_t k = 0; k < ctx->block_count; k++) {
                        if (&ctx->blocks[k] == pred) {
                            pred_idx = k;
                            break;
                        }
                    }
                    
                    if (pred_idx >= 0) {
                        for (uint32_t w = 0; w < words_needed; w++) {
                            new_doms[w] &= dom_sets[pred_idx][w];
                        }
                    }
                }
            }
            
            SET_BIT(new_doms, i);
            
            for (uint32_t w = 0; w < words_needed; w++) {
                if (new_doms[w] != dom_sets[i][w]) {
                    changed = true;
                    dom_sets[i][w] = new_doms[w];
                }
            }
            
            free(new_doms);
        }
    }
    
    for (uint32_t i = 0; i < ctx->block_count; i++) {
        free(dom_sets[i]);
    }
    free(dom_sets);
    
    #undef SET_BIT
    #undef CLEAR_BIT
    #undef TEST_BIT
    
    return true;
}

uint32_t cfg_detect_loops(CFGContext *ctx) {
    if (!ctx || !ctx->blocks) return 0;
    
    uint32_t loop_count = 0;
    
    for (uint32_t i = 0; i < ctx->block_count; i++) {
        BasicBlock *block = &ctx->blocks[i];
        for (uint32_t j = 0; j < block->successor_count; j++) {
            BasicBlock *succ = block->successors[j];
            
            bool is_back_edge = false;
            BasicBlock *dom = block->immediate_dominator;
            
            while (dom) {
                if (dom == succ) {
                    is_back_edge = true;
                    break;
                }
                dom = dom->immediate_dominator;
            }
            
            if (block == succ) {
                is_back_edge = true;
            }
            
            if (is_back_edge) {
                succ->is_loop_header = true;
                loop_count++;
            }
        }
    }
    
    return loop_count;
}

#pragma mark - Export

bool cfg_export_dot(CFGContext *ctx, FILE *output) {
    if (!ctx || !output) return false;
    
    fprintf(output, "digraph CFG {\n");
    fprintf(output, "  node [shape=box];\n\n");
    
    for (uint32_t i = 0; i < ctx->block_count; i++) {
        BasicBlock *block = &ctx->blocks[i];
        fprintf(output, "  bb_%u [label=\"BB %u\\n0x%llx - 0x%llx\"",
                i, i, block->start_address, block->end_address);
        
        if (block->is_entry) fprintf(output, " color=green");
        if (block->is_exit) fprintf(output, " color=red");
        if (block->is_loop_header) fprintf(output, " style=bold");
        
        fprintf(output, "];\n");
    }
    
    fprintf(output, "\n");
    
    for (uint32_t i = 0; i < ctx->block_count; i++) {
        BasicBlock *block = &ctx->blocks[i];
        for (uint32_t j = 0; j < block->successor_count; j++) {
            BasicBlock *succ = block->successors[j];
            
            uint32_t succ_idx = 0;
            for (uint32_t k = 0; k < ctx->block_count; k++) {
                if (&ctx->blocks[k] == succ) {
                    succ_idx = k;
                    break;
                }
            }
            
            fprintf(output, "  bb_%u -> bb_%u", i, succ_idx);
            
            EdgeType edge_type = block->successor_edge_types[j];
            if (edge_type == EDGE_CONDITIONAL_TRUE) {
                fprintf(output, " [label=\"T\" color=green]");
            } else if (edge_type == EDGE_CONDITIONAL_FALSE) {
                fprintf(output, " [label=\"F\" color=red]");
            } else if (edge_type == EDGE_CALL) {
                fprintf(output, " [label=\"call\" style=dashed]");
            }
            
            fprintf(output, ";\n");
        }
    }
    
    fprintf(output, "}\n");
    
    return true;
}

