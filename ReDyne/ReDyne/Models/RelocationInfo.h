#ifndef RelocationInfo_h
#define RelocationInfo_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "MachOHeader.h"

#pragma mark - Relocation Types

typedef enum {
    REDYNE_REBASE_TYPE_POINTER = 1,
    REDYNE_REBASE_TYPE_TEXT_ABSOLUTE32 = 2,
    REDYNE_REBASE_TYPE_TEXT_PCREL32 = 3
} RebaseType;

typedef enum {
    REDYNE_BIND_TYPE_POINTER = 1,
    REDYNE_BIND_TYPE_TEXT_ABSOLUTE32 = 2,
    REDYNE_BIND_TYPE_TEXT_PCREL32 = 3
} BindType;

typedef enum {
    REDYNE_BIND_SPECIAL_DYLIB_SELF = 0,
    REDYNE_BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE = -1,
    REDYNE_BIND_SPECIAL_DYLIB_FLAT_LOOKUP = -2
} BindSpecialDylib;

#pragma mark - Structures

typedef struct {
    uint64_t address;
    RebaseType type;
} RebaseEntry;

typedef struct {
    uint64_t address;
    BindType type;
    int32_t library_ordinal;
    int64_t addend;
    char *symbol_name;
    uint8_t symbol_flags;
    bool is_weak;
    bool is_lazy;
} BindEntry;

typedef struct {
    uint64_t address;
    char *symbol_name;
    uint64_t flags;
} ExportEntry;

typedef struct {
    MachOContext *macho_ctx;
    
    RebaseEntry *rebases;
    uint32_t rebase_count;
    
    BindEntry *binds;
    uint32_t bind_count;
    
    BindEntry *lazy_binds;
    uint32_t lazy_bind_count;
    
    BindEntry *weak_binds;
    uint32_t weak_bind_count;
    
    ExportEntry *exports;
    uint32_t export_count;
    
    int64_t slide;
    
} RelocationContext;

#pragma mark - Function Declarations

RelocationContext* reloc_create(MachOContext *macho_ctx);

bool reloc_parse_rebase(RelocationContext *ctx);

bool reloc_parse_bind(RelocationContext *ctx);

bool reloc_parse_lazy_bind(RelocationContext *ctx);

bool reloc_parse_weak_bind(RelocationContext *ctx);

bool reloc_parse_exports(RelocationContext *ctx);

uint64_t reloc_apply_slide(RelocationContext *ctx, uint64_t address);

BindEntry* reloc_find_bind(RelocationContext *ctx, uint64_t address);

ExportEntry* reloc_find_export(RelocationContext *ctx, const char *name);

void reloc_free(RelocationContext *ctx);

#endif

