#include "DyldInfo.h"
#include <stdlib.h>
#include <string.h>
#include <mach-o/loader.h>

#define MAX_IMPORTS 10000
#define MAX_EXPORTS 10000
#define MAX_LIBRARIES 500

// MARK: - Helper Functions

static uint64_t read_uleb128(const uint8_t **ptr, const uint8_t *end) {
    uint64_t result = 0;
    int shift = 0;
    uint8_t byte;
    
    do {
        if (*ptr >= end) return 0;
        byte = **ptr;
        (*ptr)++;
        result |= ((uint64_t)(byte & 0x7f)) << shift;
        shift += 7;
    } while (byte & 0x80);
    
    return result;
}

static int64_t read_sleb128(const uint8_t **ptr, const uint8_t *end) {
    int64_t result = 0;
    int shift = 0;
    uint8_t byte;
    
    do {
        if (*ptr >= end) return 0;
        byte = **ptr;
        (*ptr)++;
        result |= ((int64_t)(byte & 0x7f)) << shift;
        shift += 7;
    } while (byte & 0x80);
    
    if ((shift < 64) && (byte & 0x40)) {
        result |= -(1LL << shift);
    }
    
    return result;
}

// MARK: - Library Parsing

LibraryList* dyld_parse_libraries(MachOContext *ctx) {
    if (!ctx) return NULL;
    
    printf("  Parsing linked libraries...\n");
    
    LibraryList *list = (LibraryList*)calloc(1, sizeof(LibraryList));
    if (!list) return NULL;
    
    list->library_names = (char**)calloc(MAX_LIBRARIES, sizeof(char*));
    list->timestamps = (uint32_t*)calloc(MAX_LIBRARIES, sizeof(uint32_t));
    list->current_versions = (uint32_t*)calloc(MAX_LIBRARIES, sizeof(uint32_t));
    list->compatibility_versions = (uint32_t*)calloc(MAX_LIBRARIES, sizeof(uint32_t));
    list->library_count = 0;
    
    uint32_t header_size = ctx->header.is_64bit ? sizeof(struct mach_header_64) : sizeof(struct mach_header);
    fseek(ctx->file, header_size, SEEK_SET);
    
    for (uint32_t i = 0; i < ctx->header.ncmds; i++) {
        uint32_t cmd, cmdsize;
        long cmd_start = ftell(ctx->file);
        
        fread(&cmd, sizeof(uint32_t), 1, ctx->file);
        fread(&cmdsize, sizeof(uint32_t), 1, ctx->file);
        
        if (ctx->header.is_swapped) {
            cmd = __builtin_bswap32(cmd);
            cmdsize = __builtin_bswap32(cmdsize);
        }
        
        if (cmd == LC_LOAD_DYLIB || cmd == LC_LOAD_WEAK_DYLIB || cmd == LC_REEXPORT_DYLIB) {
            struct dylib_command dylib_cmd;
            fseek(ctx->file, cmd_start, SEEK_SET);
            fread(&dylib_cmd, sizeof(struct dylib_command), 1, ctx->file);
            
            if (ctx->header.is_swapped) {
                dylib_cmd.dylib.name.offset = __builtin_bswap32(dylib_cmd.dylib.name.offset);
                dylib_cmd.dylib.timestamp = __builtin_bswap32(dylib_cmd.dylib.timestamp);
                dylib_cmd.dylib.current_version = __builtin_bswap32(dylib_cmd.dylib.current_version);
                dylib_cmd.dylib.compatibility_version = __builtin_bswap32(dylib_cmd.dylib.compatibility_version);
            }
            
            fseek(ctx->file, cmd_start + dylib_cmd.dylib.name.offset, SEEK_SET);
            list->library_names[list->library_count] = (char*)calloc(256, 1);
            fgets(list->library_names[list->library_count], 255, ctx->file);
            
            list->timestamps[list->library_count] = dylib_cmd.dylib.timestamp;
            list->current_versions[list->library_count] = dylib_cmd.dylib.current_version;
            list->compatibility_versions[list->library_count] = dylib_cmd.dylib.compatibility_version;
            
            list->library_count++;
            if (list->library_count >= MAX_LIBRARIES) break;
        }
        
        fseek(ctx->file, cmd_start + cmdsize, SEEK_SET);
    }
    
    printf("   Found %d linked libraries\n", list->library_count);
    return list;
}

// MARK: - Import (Binding) Parsing

ImportList* dyld_parse_imports(MachOContext *ctx) {
    if (!ctx) return NULL;
    
    printf("Parsing imports (binding info)...\n");
    
    ImportList *list = (ImportList*)calloc(1, sizeof(ImportList));
    if (!list) return NULL;
    
    list->imports = (ImportInfo*)calloc(MAX_IMPORTS, sizeof(ImportInfo));
    list->import_count = 0;
    
    if (!ctx->has_dyld_info || ctx->bind_size == 0) {
        printf("   No binding info found\n");
        return list;
    }
    
    uint32_t bind_offset = ctx->bind_off;
    uint32_t bind_size = ctx->bind_size;
    
    uint8_t *bind_data = (uint8_t*)malloc(bind_size);
    fseek(ctx->file, bind_offset, SEEK_SET);
    fread(bind_data, 1, bind_size, ctx->file);
    
    const uint8_t *ptr = bind_data;
    const uint8_t *end = bind_data + bind_size;
    
    int type = 0;
    int library_ordinal = 0;
    const char *symbol_name = "";
    int64_t addend = 0;
    uint64_t address = 0;
    bool done = false;
    
    while (!done && ptr < end) {
        uint8_t opcode = *ptr;
        uint8_t immediate = opcode & 0x0F;
        opcode = opcode & 0xF0;
        ptr++;
        
        switch (opcode) {
            case 0x00:
                done = true;
                break;
                
            case 0x10:
                library_ordinal = immediate;
                break;
                
            case 0x20:
                library_ordinal = (int)read_uleb128(&ptr, end);
                break;
                
            case 0x40:
                symbol_name = (const char*)ptr;
                while (ptr < end && *ptr) ptr++;
                if (ptr < end) ptr++;
                break;
                
            case 0x50:
                type = immediate;
                break;
                
            case 0x60:
                addend = read_sleb128(&ptr, end);
                break;
                
            case 0x70:
                address = read_uleb128(&ptr, end);
                break;
                
            case 0x90:
                if (list->import_count < MAX_IMPORTS) {
                    ImportInfo *imp = &list->imports[list->import_count];
                    strncpy(imp->name, symbol_name, 255);
                    snprintf(imp->library_name, 255, "dylib[%d]", library_ordinal);
                    imp->library_ordinal = library_ordinal;
                    imp->address = address;
                    imp->bind_type = type;
                    imp->is_weak = false;
                    imp->addend = addend;
                    list->import_count++;
                }
                address += 8;
                break;
                
            default:
                break;
        }
    }
    
    free(bind_data);
    printf("   Found %d imports\n", list->import_count);
    return list;
}

// MARK: - Export Parsing

typedef struct {
    const uint8_t *data;
    uint32_t size;
    uint32_t export_count;
    ExportInfo *exports;
} TrieContext;

static void traverse_export_trie(TrieContext *tctx, const uint8_t *p, const char *prefix, uint32_t prefix_len);
static void traverse_export_trie(TrieContext *tctx, const uint8_t *p, const char *prefix, uint32_t prefix_len) {
    
    if (!tctx || !p || !prefix) return;
    if (p < tctx->data || p >= tctx->data + tctx->size) return;
    if (tctx->export_count >= MAX_EXPORTS) return;
    if (prefix_len > 255) return;
    
    uint64_t terminal_size = 0;
    const uint8_t *term_ptr = p;
    for (int shift = 0; shift < 64 && term_ptr < tctx->data + tctx->size; shift += 7) {
        uint8_t b = *term_ptr++;
        terminal_size |= ((uint64_t)(b & 0x7F) << shift);
        if ((b & 0x80) == 0) break;
    }
    
    if (terminal_size > 0 && term_ptr + terminal_size <= tctx->data + tctx->size) {
        const uint8_t *info_ptr = term_ptr;
        
        uint64_t flags = 0;
        for (int shift = 0; shift < 64 && info_ptr < term_ptr + terminal_size; shift += 7) {
            uint8_t b = *info_ptr++;
            flags |= ((uint64_t)(b & 0x7F) << shift);
            if ((b & 0x80) == 0) break;
        }
        
        uint64_t address = 0;
        for (int shift = 0; shift < 64 && info_ptr < term_ptr + terminal_size; shift += 7) {
            uint8_t b = *info_ptr++;
            address |= ((uint64_t)(b & 0x7F) << shift);
            if ((b & 0x80) == 0) break;
        }
        
        if (tctx->export_count < MAX_EXPORTS && prefix) {
            tctx->exports[tctx->export_count].address = address;
            tctx->exports[tctx->export_count].flags = flags;
            size_t copy_len = strnlen(prefix, 255);
            memcpy(tctx->exports[tctx->export_count].name, prefix, copy_len);
            tctx->exports[tctx->export_count].name[copy_len] = '\0';
            
            tctx->export_count++;
        }
        
        term_ptr += terminal_size;
    }
    
    uint8_t child_count = *term_ptr++;
    
    for (uint8_t i = 0; i < child_count && term_ptr < tctx->data + tctx->size; i++) {
        const uint8_t *label_start = term_ptr;
        size_t max_label_len = tctx->data + tctx->size - term_ptr;
        
        if (max_label_len == 0) break;
        size_t label_len = 0;
        while (label_len < max_label_len && term_ptr[label_len] != 0 && label_len < 255) {
            label_len++;
        }
        
        if (label_len >= max_label_len || term_ptr[label_len] != 0) {
            break;
        }
        
        term_ptr += label_len + 1;
        
        if (term_ptr >= tctx->data + tctx->size) break;
        
        uint64_t child_offset = 0;
        for (int shift = 0; shift < 64 && term_ptr < tctx->data + tctx->size; shift += 7) {
            uint8_t b = *term_ptr++;
            child_offset |= ((uint64_t)(b & 0x7F) << shift);
            if ((b & 0x80) == 0) break;
        }
        
        size_t prefix_len = strlen(prefix);
        if (prefix_len + label_len >= 255) {
            continue;
        }
        
        char new_prefix[256];
        memset(new_prefix, 0, sizeof(new_prefix));
        
        if (prefix_len > 0) {
            memcpy(new_prefix, prefix, prefix_len);
        }
        
        if (label_len > 0) {
            memcpy(new_prefix + prefix_len, label_start, label_len);
        }
        new_prefix[prefix_len + label_len] = '\0';
        
        if (child_offset < tctx->size) {
            traverse_export_trie(tctx, tctx->data + child_offset, new_prefix, prefix_len + label_len);
        }
    }
}

ExportList* dyld_parse_exports(MachOContext *ctx) {
    if (!ctx) return NULL;
    
    printf("   Parsing exports...\n");
    
    ExportList *list = (ExportList*)calloc(1, sizeof(ExportList));
    if (!list) return NULL;
    
    list->exports = (ExportInfo*)calloc(MAX_EXPORTS, sizeof(ExportInfo));
    list->export_count = 0;
    
    if (!ctx->has_dyld_info || ctx->export_size == 0) {
        printf("   No export info found\n");
        return list;
    }
    
    uint32_t export_offset = ctx->export_off;
    uint32_t export_size = ctx->export_size;
    uint8_t *export_data = (uint8_t*)malloc(export_size);
    fseek(ctx->file, export_offset, SEEK_SET);
    fread(export_data, 1, export_size, ctx->file);
    
    TrieContext tctx = {
        .data = export_data,
        .size = export_size,
        .export_count = 0,
        .exports = list->exports
    };
    
    if (export_size > 0) {
        traverse_export_trie(&tctx, export_data, "", 0);
    }
    
    list->export_count = tctx.export_count;
    printf("   Parsed %u exports from trie\n", list->export_count);
    
    free(export_data);
    return list;
}

// MARK: - Cleanup

void dyld_free_imports(ImportList *list) {
    if (!list) return;
    free(list->imports);
    free(list);
}

void dyld_free_exports(ExportList *list) {
    if (!list) return;
    free(list->exports);
    free(list);
}

void dyld_free_libraries(LibraryList *list) {
    if (!list) return;
    for (int i = 0; i < list->library_count; i++) {
        free(list->library_names[i]);
    }
    free(list->library_names);
    free(list->timestamps);
    free(list->current_versions);
    free(list->compatibility_versions);
    free(list);
}

