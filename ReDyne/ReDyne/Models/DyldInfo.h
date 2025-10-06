#ifndef DyldInfo_h
#define DyldInfo_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "MachOHeader.h"

// MARK: - Import (Binding) Information

typedef struct {
    char name[256];
    char library_name[256];
    int library_ordinal;
    uint64_t address;
    int bind_type;
    bool is_weak;
    int64_t addend;
} ImportInfo;

typedef struct {
    ImportInfo *imports;
    int import_count;
} ImportList;

// MARK: - Export Information

typedef struct {
    char name[256];
    uint64_t address;
    uint64_t flags;
    bool is_reexport;
    char reexport_lib[256];
    char reexport_name[256];
    bool is_weak_def;
    bool is_thread_local;
} ExportInfo;

typedef struct {
    ExportInfo *exports;
    int export_count;
} ExportList;

// MARK: - Library Dependencies

typedef struct {
    char **library_names;
    uint32_t *timestamps;
    uint32_t *current_versions;
    uint32_t *compatibility_versions;
    int library_count;
} LibraryList;

// MARK: - Public API

ImportList* dyld_parse_imports(MachOContext *ctx);

ExportList* dyld_parse_exports(MachOContext *ctx);

LibraryList* dyld_parse_libraries(MachOContext *ctx);

void dyld_free_imports(ImportList *list);

void dyld_free_exports(ExportList *list);

void dyld_free_libraries(LibraryList *list);

#endif

