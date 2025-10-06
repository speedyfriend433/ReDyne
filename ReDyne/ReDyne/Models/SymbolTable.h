#ifndef SymbolTable_h
#define SymbolTable_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "MachOHeader.h"

#pragma mark - Symbol Types and Constants

typedef enum {
    SYMBOL_TYPE_UNDEFINED = 0,
    SYMBOL_TYPE_ABSOLUTE,
    SYMBOL_TYPE_SECTION,
    SYMBOL_TYPE_PREBOUND,
    SYMBOL_TYPE_INDIRECT
} SymbolType;

typedef enum {
    SYMBOL_SCOPE_LOCAL = 0,
    SYMBOL_SCOPE_GLOBAL,
    SYMBOL_SCOPE_WEAK,
    SYMBOL_SCOPE_EXTERNAL
} SymbolScope;

#pragma mark - Symbol Information Structure

typedef struct {
    char *name;
    uint64_t address;
    uint64_t size;
    SymbolType type;
    SymbolScope scope;
    uint8_t section;
    uint16_t desc;
    uint8_t n_type;
    bool is_defined;
    bool is_external;
    bool is_debug;
    bool is_thumb;
    bool is_weak;
} SymbolInfo;

typedef struct {
    MachOContext *macho_ctx;
    SymbolInfo *symbols;
    uint32_t symbol_count;
    
    char *string_table;
    uint32_t string_table_size;
    uint32_t *defined_indices;
    uint32_t defined_count;
    uint32_t *undefined_indices;
    uint32_t undefined_count;
    uint32_t *external_indices;
    uint32_t external_count;
    uint32_t *function_indices;
    uint32_t function_count;
    
} SymbolTableContext;

#pragma mark - Function Declarations

SymbolTableContext* symbol_table_create(MachOContext *macho_ctx);

bool symbol_table_parse(SymbolTableContext *ctx);

bool symbol_table_load_strings(SymbolTableContext *ctx);

const char* symbol_table_get_string(SymbolTableContext *ctx, uint32_t strx);

bool symbol_table_categorize(SymbolTableContext *ctx);

uint32_t symbol_table_extract_functions(SymbolTableContext *ctx);

int32_t symbol_table_find_by_name(SymbolTableContext *ctx, const char *name);

int32_t symbol_table_find_by_address(SymbolTableContext *ctx, uint64_t address);

const char* symbol_type_string(SymbolType type);

const char* symbol_scope_string(SymbolScope scope);

bool symbol_table_parse_dysymtab(SymbolTableContext *ctx);

bool symbol_table_parse_dyld_info(SymbolTableContext *ctx);

void symbol_table_sort_by_address(SymbolTableContext *ctx);

void symbol_table_sort_by_name(SymbolTableContext *ctx);

void symbol_table_free(SymbolTableContext *ctx);

#endif

