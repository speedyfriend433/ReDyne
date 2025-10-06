#include "SymbolTable.h"
#include <stdlib.h>
#include <string.h>
#include <mach-o/nlist.h>
#include <mach-o/stab.h>

#pragma mark - String Helpers

const char* symbol_type_string(SymbolType type) {
    switch (type) {
        case SYMBOL_TYPE_UNDEFINED: return "Undefined";
        case SYMBOL_TYPE_ABSOLUTE: return "Absolute";
        case SYMBOL_TYPE_SECTION: return "Section";
        case SYMBOL_TYPE_PREBOUND: return "Prebound";
        case SYMBOL_TYPE_INDIRECT: return "Indirect";
        default: return "Unknown";
    }
}

const char* symbol_scope_string(SymbolScope scope) {
    switch (scope) {
        case SYMBOL_SCOPE_LOCAL: return "Local";
        case SYMBOL_SCOPE_GLOBAL: return "Global";
        case SYMBOL_SCOPE_WEAK: return "Weak";
        case SYMBOL_SCOPE_EXTERNAL: return "External";
        default: return "Unknown";
    }
}

#pragma mark - Context Management

SymbolTableContext* symbol_table_create(MachOContext *macho_ctx) {
    if (!macho_ctx || macho_ctx->nsyms == 0) return NULL;
    
    SymbolTableContext *ctx = (SymbolTableContext*)calloc(1, sizeof(SymbolTableContext));
    if (!ctx) return NULL;
    
    ctx->macho_ctx = macho_ctx;
    ctx->symbol_count = macho_ctx->nsyms;
    ctx->symbols = (SymbolInfo*)calloc(ctx->symbol_count, sizeof(SymbolInfo));
    
    if (!ctx->symbols) {
        free(ctx);
        return NULL;
    }
    
    return ctx;
}

void symbol_table_free(SymbolTableContext *ctx) {
    if (!ctx) return;
    
    if (ctx->symbols) {
        for (uint32_t i = 0; i < ctx->symbol_count; i++) {
            if (ctx->symbols[i].name) free(ctx->symbols[i].name);
        }
        free(ctx->symbols);
    }
    
    if (ctx->string_table) free(ctx->string_table);
    if (ctx->defined_indices) free(ctx->defined_indices);
    if (ctx->undefined_indices) free(ctx->undefined_indices);
    if (ctx->external_indices) free(ctx->external_indices);
    if (ctx->function_indices) free(ctx->function_indices);
    
    free(ctx);
}

#pragma mark - String Table Loading

bool symbol_table_load_strings(SymbolTableContext *ctx) {
    if (!ctx || !ctx->macho_ctx || !ctx->macho_ctx->file) return false;
    
    MachOContext *mctx = ctx->macho_ctx;
    if (mctx->strsize == 0) return false;
    
    ctx->string_table_size = mctx->strsize;
    ctx->string_table = (char*)malloc(ctx->string_table_size);
    if (!ctx->string_table) return false;
    
    fseek(mctx->file, mctx->stroff, SEEK_SET);
    size_t read = fread(ctx->string_table, 1, ctx->string_table_size, mctx->file);
    
    if (read != ctx->string_table_size) {
        free(ctx->string_table);
        ctx->string_table = NULL;
        return false;
    }
    
    return true;
}

const char* symbol_table_get_string(SymbolTableContext *ctx, uint32_t strx) {
    if (!ctx || !ctx->string_table || strx >= ctx->string_table_size) return NULL;
    return ctx->string_table + strx;
}

#pragma mark - Symbol Parsing

bool symbol_table_parse(SymbolTableContext *ctx) {
    if (!ctx || !ctx->macho_ctx || !ctx->macho_ctx->file) return false;
    
    if (!symbol_table_load_strings(ctx)) return false;
    
    MachOContext *mctx = ctx->macho_ctx;
    
    fseek(mctx->file, mctx->symtab_offset, SEEK_SET);
    
    if (mctx->header.is_64bit) {
        for (uint32_t i = 0; i < ctx->symbol_count; i++) {
            struct nlist_64 nlist;
            if (fread(&nlist, sizeof(struct nlist_64), 1, mctx->file) != 1) return false;
            
            if (mctx->header.is_swapped) {
                nlist.n_un.n_strx = swap_uint32(nlist.n_un.n_strx);
                nlist.n_desc = swap_uint16(nlist.n_desc);
                nlist.n_value = swap_uint64(nlist.n_value);
            }
            
            SymbolInfo *sym = &ctx->symbols[i];
            
            const char *name = symbol_table_get_string(ctx, nlist.n_un.n_strx);
            if (name) {
                sym->name = strdup(name);
            } else {
                sym->name = strdup("");
            }
            
            sym->n_type = nlist.n_type;
            sym->desc = nlist.n_desc;
            sym->address = nlist.n_value;
            sym->section = nlist.n_sect;
            
            uint8_t type_mask = nlist.n_type & N_TYPE;
            switch (type_mask) {
                case N_UNDF: sym->type = SYMBOL_TYPE_UNDEFINED; break;
                case N_ABS: sym->type = SYMBOL_TYPE_ABSOLUTE; break;
                case N_SECT: sym->type = SYMBOL_TYPE_SECTION; break;
                case N_PBUD: sym->type = SYMBOL_TYPE_PREBOUND; break;
                case N_INDR: sym->type = SYMBOL_TYPE_INDIRECT; break;
                default: sym->type = SYMBOL_TYPE_UNDEFINED; break;
            }
            
            sym->is_external = (nlist.n_type & N_EXT) != 0;
            sym->is_debug = (nlist.n_type & N_STAB) != 0;
            sym->is_defined = (type_mask != N_UNDF);
            sym->is_weak = ((nlist.n_desc & N_WEAK_DEF) != 0) || ((nlist.n_desc & N_WEAK_REF) != 0);
            
            if (sym->is_weak) {
                sym->scope = SYMBOL_SCOPE_WEAK;
            } else if (sym->is_external) {
                sym->scope = SYMBOL_SCOPE_EXTERNAL;
            } else if (nlist.n_type & N_PEXT) {
                sym->scope = SYMBOL_SCOPE_GLOBAL;
            } else {
                sym->scope = SYMBOL_SCOPE_LOCAL;
            }
            
            if (mctx->header.cputype == CPU_TYPE_ARM && (nlist.n_desc & N_ARM_THUMB_DEF)) {
                sym->is_thumb = true;
            }
            sym->size = 0;
        }
    } else {
        for (uint32_t i = 0; i < ctx->symbol_count; i++) {
            struct nlist nlist;
            if (fread(&nlist, sizeof(struct nlist), 1, mctx->file) != 1) return false;
            
            if (mctx->header.is_swapped) {
                nlist.n_un.n_strx = swap_uint32(nlist.n_un.n_strx);
                nlist.n_desc = swap_uint16(nlist.n_desc);
                nlist.n_value = swap_uint32(nlist.n_value);
            }
            
            SymbolInfo *sym = &ctx->symbols[i];
            const char *name = symbol_table_get_string(ctx, nlist.n_un.n_strx);
            sym->name = name ? strdup(name) : strdup("");
            
            sym->n_type = nlist.n_type;
            sym->desc = nlist.n_desc;
            sym->address = nlist.n_value;
            sym->section = nlist.n_sect;
            
            uint8_t type_mask = nlist.n_type & N_TYPE;
            switch (type_mask) {
                case N_UNDF: sym->type = SYMBOL_TYPE_UNDEFINED; break;
                case N_ABS: sym->type = SYMBOL_TYPE_ABSOLUTE; break;
                case N_SECT: sym->type = SYMBOL_TYPE_SECTION; break;
                case N_PBUD: sym->type = SYMBOL_TYPE_PREBOUND; break;
                case N_INDR: sym->type = SYMBOL_TYPE_INDIRECT; break;
                default: sym->type = SYMBOL_TYPE_UNDEFINED; break;
            }
            
            sym->is_external = (nlist.n_type & N_EXT) != 0;
            sym->is_debug = (nlist.n_type & N_STAB) != 0;
            sym->is_defined = (type_mask != N_UNDF);
            sym->is_weak = ((nlist.n_desc & N_WEAK_DEF) != 0) || ((nlist.n_desc & N_WEAK_REF) != 0);
            
            if (sym->is_weak) {
                sym->scope = SYMBOL_SCOPE_WEAK;
            } else if (sym->is_external) {
                sym->scope = SYMBOL_SCOPE_EXTERNAL;
            } else {
                sym->scope = SYMBOL_SCOPE_LOCAL;
            }
        }
    }
    
    return true;
}

#pragma mark - Symbol Categorization

bool symbol_table_categorize(SymbolTableContext *ctx) {
    if (!ctx || !ctx->symbols) return false;
    
    uint32_t def_count = 0, undef_count = 0, ext_count = 0;
    for (uint32_t i = 0; i < ctx->symbol_count; i++) {
        if (ctx->symbols[i].is_defined) def_count++;
        else undef_count++;
        if (ctx->symbols[i].is_external) ext_count++;
    }
    
    if (def_count > 0) {
        ctx->defined_indices = (uint32_t*)malloc(def_count * sizeof(uint32_t));
        ctx->defined_count = 0;
    }
    if (undef_count > 0) {
        ctx->undefined_indices = (uint32_t*)malloc(undef_count * sizeof(uint32_t));
        ctx->undefined_count = 0;
    }
    if (ext_count > 0) {
        ctx->external_indices = (uint32_t*)malloc(ext_count * sizeof(uint32_t));
        ctx->external_count = 0;
    }
    
    for (uint32_t i = 0; i < ctx->symbol_count; i++) {
        if (ctx->symbols[i].is_defined && ctx->defined_indices) {
            ctx->defined_indices[ctx->defined_count++] = i;
        }
        if (!ctx->symbols[i].is_defined && ctx->undefined_indices) {
            ctx->undefined_indices[ctx->undefined_count++] = i;
        }
        if (ctx->symbols[i].is_external && ctx->external_indices) {
            ctx->external_indices[ctx->external_count++] = i;
        }
    }
    
    return true;
}

uint32_t symbol_table_extract_functions(SymbolTableContext *ctx) {
    if (!ctx || !ctx->symbols) return 0;
    
    uint32_t func_count = 0;
    for (uint32_t i = 0; i < ctx->symbol_count; i++) {
        SymbolInfo *sym = &ctx->symbols[i];
        if (sym->type == SYMBOL_TYPE_SECTION && sym->address > 0 && !sym->is_debug) {
            func_count++;
        }
    }
    
    if (func_count == 0) return 0;
    
    ctx->function_indices = (uint32_t*)malloc(func_count * sizeof(uint32_t));
    if (!ctx->function_indices) return 0;
    
    ctx->function_count = 0;
    for (uint32_t i = 0; i < ctx->symbol_count; i++) {
        SymbolInfo *sym = &ctx->symbols[i];
        if (sym->type == SYMBOL_TYPE_SECTION && sym->address > 0 && !sym->is_debug) {
            ctx->function_indices[ctx->function_count++] = i;
        }
    }
    
    return ctx->function_count;
}

#pragma mark - Symbol Search

int32_t symbol_table_find_by_name(SymbolTableContext *ctx, const char *name) {
    if (!ctx || !ctx->symbols || !name) return -1;
    
    for (uint32_t i = 0; i < ctx->symbol_count; i++) {
        if (ctx->symbols[i].name && strcmp(ctx->symbols[i].name, name) == 0) {
            return (int32_t)i;
        }
    }
    
    return -1;
}

int32_t symbol_table_find_by_address(SymbolTableContext *ctx, uint64_t address) {
    if (!ctx || !ctx->symbols) return -1;
    
    int32_t best = -1;
    uint64_t best_diff = UINT64_MAX;
    
    for (uint32_t i = 0; i < ctx->symbol_count; i++) {
        if (ctx->symbols[i].address <= address) {
            uint64_t diff = address - ctx->symbols[i].address;
            if (diff < best_diff) {
                best_diff = diff;
                best = (int32_t)i;
            }
        }
    }
    
    return best;
}

#pragma mark - Sorting

static int compare_symbols_by_address(const void *a, const void *b) {
    const SymbolInfo *sym_a = (const SymbolInfo*)a;
    const SymbolInfo *sym_b = (const SymbolInfo*)b;
    if (sym_a->address < sym_b->address) return -1;
    if (sym_a->address > sym_b->address) return 1;
    return 0;
}

static int compare_symbols_by_name(const void *a, const void *b) {
    const SymbolInfo *sym_a = (const SymbolInfo*)a;
    const SymbolInfo *sym_b = (const SymbolInfo*)b;
    if (!sym_a->name) return 1;
    if (!sym_b->name) return -1;
    return strcmp(sym_a->name, sym_b->name);
}

void symbol_table_sort_by_address(SymbolTableContext *ctx) {
    if (!ctx || !ctx->symbols) return;
    qsort(ctx->symbols, ctx->symbol_count, sizeof(SymbolInfo), compare_symbols_by_address);
}

void symbol_table_sort_by_name(SymbolTableContext *ctx) {
    if (!ctx || !ctx->symbols) return;
    qsort(ctx->symbols, ctx->symbol_count, sizeof(SymbolInfo), compare_symbols_by_name);
}

#pragma mark - Dynamic Symbol Table Parsing

bool symbol_table_parse_dysymtab(SymbolTableContext *ctx) {
    if (!ctx || !ctx->macho_ctx) return false;
    
    FILE *file = ctx->macho_ctx->file;
    bool is_64bit = ctx->macho_ctx->header.is_64bit;
    bool is_swapped = ctx->macho_ctx->header.is_swapped;
    
    uint32_t header_size = is_64bit ? sizeof(struct mach_header_64) : sizeof(struct mach_header);
    fseek(file, header_size, SEEK_SET);
    
    for (uint32_t i = 0; i < ctx->macho_ctx->header.ncmds; i++) {
        uint32_t cmd, cmdsize;
        long cmd_start = ftell(file);
        
        fread(&cmd, sizeof(uint32_t), 1, file);
        fread(&cmdsize, sizeof(uint32_t), 1, file);
        
        if (is_swapped) {
            cmd = __builtin_bswap32(cmd);
            cmdsize = __builtin_bswap32(cmdsize);
        }
        
        if (cmd == LC_DYSYMTAB) {
            struct {
                uint32_t ilocalsym;
                uint32_t nlocalsym;
                uint32_t iextdefsym;
                uint32_t nextdefsym;
                uint32_t iundefsym;
                uint32_t nundefsym;
                uint32_t tocoff;
                uint32_t ntoc;
                uint32_t modtaboff;
                uint32_t nmodtab;
                uint32_t extrefsymoff;
                uint32_t nextrefsyms;
                uint32_t indirectsymoff;
                uint32_t nindirectsyms;
                uint32_t extreloff;
                uint32_t nextrel;
                uint32_t locreloff;
                uint32_t nlocrel;
            } dysymtab;
            
            fread(&dysymtab, sizeof(dysymtab), 1, file);
            
            if (is_swapped) {
                dysymtab.ilocalsym = __builtin_bswap32(dysymtab.ilocalsym);
                dysymtab.nlocalsym = __builtin_bswap32(dysymtab.nlocalsym);
                dysymtab.iextdefsym = __builtin_bswap32(dysymtab.iextdefsym);
                dysymtab.nextdefsym = __builtin_bswap32(dysymtab.nextdefsym);
                dysymtab.iundefsym = __builtin_bswap32(dysymtab.iundefsym);
                dysymtab.nundefsym = __builtin_bswap32(dysymtab.nundefsym);
                dysymtab.indirectsymoff = __builtin_bswap32(dysymtab.indirectsymoff);
                dysymtab.nindirectsyms = __builtin_bswap32(dysymtab.nindirectsyms);
            }
            
            if (ctx->symbols && ctx->symbol_count > 0) {
                for (uint32_t j = dysymtab.ilocalsym; 
                     j < dysymtab.ilocalsym + dysymtab.nlocalsym && j < ctx->symbol_count; 
                     j++) {
                    ctx->symbols[j].scope = 0x00;
                }
                
                for (uint32_t j = dysymtab.iextdefsym; 
                     j < dysymtab.iextdefsym + dysymtab.nextdefsym && j < ctx->symbol_count; 
                     j++) {
                    ctx->symbols[j].scope = 0x01;
                    ctx->symbols[j].is_external = true;
                }
                
                for (uint32_t j = dysymtab.iundefsym; 
                     j < dysymtab.iundefsym + dysymtab.nundefsym && j < ctx->symbol_count; 
                     j++) {
                    ctx->symbols[j].is_defined = false;
                    ctx->symbols[j].is_external = true;
                }
            }
            
            return true;
        }
        
        fseek(file, cmd_start + cmdsize, SEEK_SET);
    }
    
    return false;
}

bool symbol_table_parse_dyld_info(SymbolTableContext *ctx) {
    if (!ctx || !ctx->macho_ctx) return false;
    //dyldinfo.c has it
    return true;
}

