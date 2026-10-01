#include "RelocationInfo.h"
#include <stdlib.h>
#include <string.h>
#include <mach-o/loader.h>

#pragma mark - Context Management

RelocationContext* reloc_create(MachOContext *macho_ctx) {
    if (!macho_ctx) return NULL;
    
    RelocationContext *ctx = (RelocationContext*)calloc(1, sizeof(RelocationContext));
    if (!ctx) return NULL;
    
    ctx->macho_ctx = macho_ctx;
    ctx->slide = 0;
    
    return ctx;
}

void reloc_free(RelocationContext *ctx) {
    if (!ctx) return;
    
    if (ctx->rebases) free(ctx->rebases);
    
    if (ctx->binds) {
        for (uint32_t i = 0; i < ctx->bind_count; i++) {
            if (ctx->binds[i].symbol_name) free(ctx->binds[i].symbol_name);
        }
        free(ctx->binds);
    }
    
    if (ctx->lazy_binds) {
        for (uint32_t i = 0; i < ctx->lazy_bind_count; i++) {
            if (ctx->lazy_binds[i].symbol_name) free(ctx->lazy_binds[i].symbol_name);
        }
        free(ctx->lazy_binds);
    }
    
    if (ctx->weak_binds) {
        for (uint32_t i = 0; i < ctx->weak_bind_count; i++) {
            if (ctx->weak_binds[i].symbol_name) free(ctx->weak_binds[i].symbol_name);
        }
        free(ctx->weak_binds);
    }
    
    if (ctx->exports) {
        for (uint32_t i = 0; i < ctx->export_count; i++) {
            if (ctx->exports[i].symbol_name) free(ctx->exports[i].symbol_name);
        }
        free(ctx->exports);
    }
    
    free(ctx);
}

#pragma mark - Growable Arrays

// Hard ceilings keep a hostile binary from forcing unbounded allocation, while staying
// far above what real-world binaries need (the old fixed 500-10000 entry arrays silently
// dropped entries). Hitting a ceiling sets ctx->truncated so callers can tell.
#define RELOC_MAX_REBASES 4000000u
#define RELOC_MAX_BINDS   1000000u
#define RELOC_MAX_EXPORTS 100000u
#define RELOC_MAX_TRIE_NODES 200000u

/// Makes room for one more element at index `count`. Returns false when the array was
/// never allocated, the hard ceiling is reached (sets *truncated) or realloc fails.
static bool reloc_ensure(void **array, uint32_t *capacity, uint32_t count,
                         size_t elem_size, uint32_t hard_max, bool *truncated) {
    if (!*array) return false;
    if (count < *capacity) return true;
    if (count >= hard_max) {
        if (truncated) *truncated = true;
        return false;
    }
    uint64_t new_cap = (uint64_t)(*capacity ? *capacity : 16) * 2;
    if (new_cap > hard_max) new_cap = hard_max;
    void *grown = realloc(*array, (size_t)new_cap * elem_size);
    if (!grown) return false;
    memset((uint8_t*)grown + (size_t)(*capacity) * elem_size, 0,
           (size_t)(new_cap - *capacity) * elem_size);
    *array = grown;
    *capacity = (uint32_t)new_cap;
    return true;
}

/// dyld-info blob sizes come from the binary; validate against the real file size before
/// sizing a buffer from them.
static bool reloc_range_ok(const MachOContext *m, uint64_t off, uint64_t size) {
    uint64_t fsize = (uint64_t)m->file_size;
    return off <= fsize && size <= fsize - off;
}

#pragma mark - Rebase Parsing

bool reloc_parse_rebase(RelocationContext *ctx) {
    if (!ctx || !ctx->macho_ctx || !ctx->macho_ctx->has_dyld_info) return false;
    if (ctx->macho_ctx->rebase_size == 0) return true;
    
    if (!reloc_range_ok(ctx->macho_ctx, ctx->macho_ctx->rebase_off, ctx->macho_ctx->rebase_size)) return false;
    uint8_t *rebase_data = (uint8_t*)malloc(ctx->macho_ctx->rebase_size);
    if (!rebase_data) return false;
    
    fseek(ctx->macho_ctx->file, ctx->macho_ctx->rebase_off, SEEK_SET);
    if (fread(rebase_data, 1, ctx->macho_ctx->rebase_size, ctx->macho_ctx->file) != ctx->macho_ctx->rebase_size) {
        free(rebase_data);
        return false;
    }
    
    uint32_t estimated_count = 10000;
    ctx->rebases = (RebaseEntry*)calloc(estimated_count, sizeof(RebaseEntry));
    ctx->rebase_count = 0;
    
    RebaseType type = REBASE_TYPE_POINTER;
    uint32_t segment_index = 0;
    uint64_t segment_offset = 0;
    uint32_t ptr_size = ctx->macho_ctx->header.is_64bit ? 8 : 4;
    
    uint32_t i = 0;
    while (i < ctx->macho_ctx->rebase_size) {
        uint8_t byte = rebase_data[i++];
        uint8_t opcode = byte & 0xF0;
        uint8_t immediate = byte & 0x0F;
        
        switch (opcode) {
            case 0x00:
                goto done_rebase;
                
            case 0x10:
                type = (RebaseType)immediate;
                break;
                
            case 0x20:
                segment_index = immediate;
                segment_offset = 0;
                for (int shift = 0; i < ctx->macho_ctx->rebase_size && shift < 64; shift += 7) {
                    uint8_t b = rebase_data[i++];
                    segment_offset |= ((uint64_t)(b & 0x7F) << shift);
                    if ((b & 0x80) == 0) break;
                }
                break;
                
            case 0x30:
                {
                    uint64_t delta = 0;
                    for (int shift = 0; i < ctx->macho_ctx->rebase_size && shift < 64; shift += 7) {
                        uint8_t b = rebase_data[i++];
                        delta |= ((uint64_t)(b & 0x7F) << shift);
                        if ((b & 0x80) == 0) break;
                    }
                    segment_offset += delta;
                }
                break;
                
            case 0x40:
                segment_offset += (immediate * ptr_size);
                break;
                
            case 0x50:
                for (uint8_t count = 0; count < immediate && reloc_ensure((void**)&ctx->rebases, &estimated_count, ctx->rebase_count, sizeof(RebaseEntry), RELOC_MAX_REBASES, &ctx->truncated); count++) {
                    ctx->rebases[ctx->rebase_count].address = segment_offset;
                    ctx->rebases[ctx->rebase_count].type = type;
                    ctx->rebase_count++;
                    segment_offset += ptr_size;
                }
                break;
                
            case 0x60:
                {
                    uint64_t count = 0;
                    for (int shift = 0; i < ctx->macho_ctx->rebase_size && shift < 64; shift += 7) {
                        uint8_t b = rebase_data[i++];
                        count |= ((uint64_t)(b & 0x7F) << shift);
                        if ((b & 0x80) == 0) break;
                    }
                    for (uint64_t j = 0; j < count && reloc_ensure((void**)&ctx->rebases, &estimated_count, ctx->rebase_count, sizeof(RebaseEntry), RELOC_MAX_REBASES, &ctx->truncated); j++) {
                        ctx->rebases[ctx->rebase_count].address = segment_offset;
                        ctx->rebases[ctx->rebase_count].type = type;
                        ctx->rebase_count++;
                        segment_offset += ptr_size;
                    }
                }
                break;
                
            case 0x70:
                if (reloc_ensure((void**)&ctx->rebases, &estimated_count, ctx->rebase_count, sizeof(RebaseEntry), RELOC_MAX_REBASES, &ctx->truncated)) {
                    ctx->rebases[ctx->rebase_count].address = segment_offset;
                    ctx->rebases[ctx->rebase_count].type = type;
                    ctx->rebase_count++;
                }
                {
                    uint64_t delta = 0;
                    for (int shift = 0; i < ctx->macho_ctx->rebase_size && shift < 64; shift += 7) {
                        uint8_t b = rebase_data[i++];
                        delta |= ((uint64_t)(b & 0x7F) << shift);
                        if ((b & 0x80) == 0) break;
                    }
                    segment_offset += delta + ptr_size;
                }
                break;
                
            case 0x80:
                {
                    uint64_t count = 0, skip = 0;
                    for (int shift = 0; i < ctx->macho_ctx->rebase_size && shift < 64; shift += 7) {
                        uint8_t b = rebase_data[i++];
                        count |= ((uint64_t)(b & 0x7F) << shift);
                        if ((b & 0x80) == 0) break;
                    }
                    for (int shift = 0; i < ctx->macho_ctx->rebase_size && shift < 64; shift += 7) {
                        uint8_t b = rebase_data[i++];
                        skip |= ((uint64_t)(b & 0x7F) << shift);
                        if ((b & 0x80) == 0) break;
                    }
                    for (uint64_t j = 0; j < count && reloc_ensure((void**)&ctx->rebases, &estimated_count, ctx->rebase_count, sizeof(RebaseEntry), RELOC_MAX_REBASES, &ctx->truncated); j++) {
                        ctx->rebases[ctx->rebase_count].address = segment_offset;
                        ctx->rebases[ctx->rebase_count].type = type;
                        ctx->rebase_count++;
                        segment_offset += skip + ptr_size;
                    }
                }
                break;
        }
    }
    
done_rebase:
    free(rebase_data);
    return true;
}

#pragma mark - Bind Parsing

bool reloc_parse_bind(RelocationContext *ctx) {
    if (!ctx || !ctx->macho_ctx || !ctx->macho_ctx->has_dyld_info) return false;
    if (ctx->macho_ctx->bind_size == 0) return true;
    
    uint32_t estimated_count = 1000;
    ctx->binds = (BindEntry*)calloc(estimated_count, sizeof(BindEntry));
    ctx->bind_count = 0;
    
    fseek(ctx->macho_ctx->file, ctx->macho_ctx->bind_off, SEEK_SET);
    if (!reloc_range_ok(ctx->macho_ctx, ctx->macho_ctx->bind_off, ctx->macho_ctx->bind_size)) return false;
    uint8_t *bind_data = malloc(ctx->macho_ctx->bind_size);
    if (!bind_data) return false;
    if (fread(bind_data, 1, ctx->macho_ctx->bind_size, ctx->macho_ctx->file) != ctx->macho_ctx->bind_size) {
        free(bind_data);
        return false;
    }
    
    BindType type = REDYNE_BIND_TYPE_POINTER;
    int32_t library_ordinal = 0;
    int64_t addend = 0;
    uint32_t segment_index = 0;
    uint64_t segment_offset = 0;
    char *symbol_name = NULL;
    uint8_t symbol_flags = 0;
    uint64_t count = 0;
    uint64_t skip = 0;
    
    uint32_t i = 0;
    while (i < ctx->macho_ctx->bind_size) {
        uint8_t byte = bind_data[i++];
        uint8_t opcode = byte & 0xF0;
        uint8_t immediate = byte & 0x0F;
        
        switch (opcode) {
            case 0x00:
                goto done_bind;
                
            case 0x10:
                library_ordinal = immediate;
                break;
                
            case 0x20:
                library_ordinal = 0;
                for (int shift = 0; i < ctx->macho_ctx->bind_size; shift += 7) {
                    uint8_t b = bind_data[i++];
                    library_ordinal |= ((b & 0x7F) << shift);
                    if ((b & 0x80) == 0) break;
                }
                break;
                
            case 0x30:
                if (immediate == 0) library_ordinal = 0;
                else library_ordinal = (int8_t)(0xF0 | immediate);
                break;
                
            case 0x40:
                symbol_flags = immediate;
                symbol_name = (char*)&bind_data[i];
                i += strlen(symbol_name) + 1;
                break;
                
            case 0x50:
                type = (BindType)immediate;
                break;
                
            case 0x60:
                addend = 0;
                for (int shift = 0; i < ctx->macho_ctx->bind_size; shift += 7) {
                    uint8_t b = bind_data[i++];
                    addend |= ((int64_t)(b & 0x7F) << shift);
                    if ((b & 0x80) == 0) {
                        if (shift < 64 && (b & 0x40)) addend |= (~0ULL << (shift + 7));
                        break;
                    }
                }
                break;
                
            case 0x70:
                segment_index = immediate;
                segment_offset = 0;
                for (int shift = 0; i < ctx->macho_ctx->bind_size; shift += 7) {
                    uint8_t b = bind_data[i++];
                    segment_offset |= ((uint64_t)(b & 0x7F) << shift);
                    if ((b & 0x80) == 0) break;
                }
                break;
                
            case 0x80:
                {
                    uint64_t delta = 0;
                    for (int shift = 0; i < ctx->macho_ctx->bind_size; shift += 7) {
                        uint8_t b = bind_data[i++];
                        delta |= ((uint64_t)(b & 0x7F) << shift);
                        if ((b & 0x80) == 0) break;
                    }
                    segment_offset += delta;
                }
                break;
                
            case 0x90:
                if (symbol_name && reloc_ensure((void**)&ctx->binds, &estimated_count, ctx->bind_count, sizeof(BindEntry), RELOC_MAX_BINDS, &ctx->truncated)) {
                    ctx->binds[ctx->bind_count].address = segment_offset;
                    ctx->binds[ctx->bind_count].type = type;
                    ctx->binds[ctx->bind_count].library_ordinal = library_ordinal;
                    ctx->binds[ctx->bind_count].addend = addend;
                    ctx->binds[ctx->bind_count].symbol_name = strdup(symbol_name);
                    ctx->binds[ctx->bind_count].symbol_flags = symbol_flags;
                    ctx->binds[ctx->bind_count].is_weak = false;
                    ctx->binds[ctx->bind_count].is_lazy = false;
                    ctx->bind_count++;
                }
                segment_offset += 8;
                break;
                
            case 0xA0:
                if (symbol_name && reloc_ensure((void**)&ctx->binds, &estimated_count, ctx->bind_count, sizeof(BindEntry), RELOC_MAX_BINDS, &ctx->truncated)) {
                    ctx->binds[ctx->bind_count].address = segment_offset;
                    ctx->binds[ctx->bind_count].type = type;
                    ctx->binds[ctx->bind_count].library_ordinal = library_ordinal;
                    ctx->binds[ctx->bind_count].addend = addend;
                    ctx->binds[ctx->bind_count].symbol_name = strdup(symbol_name);
                    ctx->binds[ctx->bind_count].symbol_flags = symbol_flags;
                    ctx->binds[ctx->bind_count].is_weak = false;
                    ctx->binds[ctx->bind_count].is_lazy = false;
                    ctx->bind_count++;
                }
                {
                    uint64_t delta = 0;
                    for (int shift = 0; i < ctx->macho_ctx->bind_size; shift += 7) {
                        uint8_t b = bind_data[i++];
                        delta |= ((uint64_t)(b & 0x7F) << shift);
                        if ((b & 0x80) == 0) break;
                    }
                    segment_offset += delta + 8;
                }
                break;
                
            case 0xB0:
                if (symbol_name && reloc_ensure((void**)&ctx->binds, &estimated_count, ctx->bind_count, sizeof(BindEntry), RELOC_MAX_BINDS, &ctx->truncated)) {
                    ctx->binds[ctx->bind_count].address = segment_offset;
                    ctx->binds[ctx->bind_count].type = type;
                    ctx->binds[ctx->bind_count].library_ordinal = library_ordinal;
                    ctx->binds[ctx->bind_count].addend = addend;
                    ctx->binds[ctx->bind_count].symbol_name = strdup(symbol_name);
                    ctx->binds[ctx->bind_count].symbol_flags = symbol_flags;
                    ctx->binds[ctx->bind_count].is_weak = false;
                    ctx->binds[ctx->bind_count].is_lazy = false;
                    ctx->bind_count++;
                }
                segment_offset += (immediate * 8) + 8;
                break;
                
            case 0xC0:
                count = 0;
                for (int shift = 0; i < ctx->macho_ctx->bind_size; shift += 7) {
                    uint8_t b = bind_data[i++];
                    count |= ((uint64_t)(b & 0x7F) << shift);
                    if ((b & 0x80) == 0) break;
                }
                
                skip = 0;
                for (int shift = 0; i < ctx->macho_ctx->bind_size; shift += 7) {
                    uint8_t b = bind_data[i++];
                    skip |= ((uint64_t)(b & 0x7F) << shift);
                    if ((b & 0x80) == 0) break;
                }
                for (uint64_t j = 0; j < count && reloc_ensure((void**)&ctx->binds, &estimated_count, ctx->bind_count, sizeof(BindEntry), RELOC_MAX_BINDS, &ctx->truncated); j++) {
                    if (symbol_name) {
                        ctx->binds[ctx->bind_count].address = segment_offset;
                        ctx->binds[ctx->bind_count].type = type;
                        ctx->binds[ctx->bind_count].library_ordinal = library_ordinal;
                        ctx->binds[ctx->bind_count].addend = addend;
                        ctx->binds[ctx->bind_count].symbol_name = strdup(symbol_name);
                        ctx->binds[ctx->bind_count].symbol_flags = symbol_flags;
                        ctx->binds[ctx->bind_count].is_weak = false;
                        ctx->binds[ctx->bind_count].is_lazy = false;
                        ctx->bind_count++;
                    }
                    segment_offset += skip + 8;
                }
                break;
        }
    }
    
done_bind:
    free(bind_data);
    return true;
}

bool reloc_parse_lazy_bind(RelocationContext *ctx) {
    if (!ctx || !ctx->macho_ctx || !ctx->macho_ctx->has_dyld_info) return false;
    if (ctx->macho_ctx->lazy_bind_size == 0) return true;
    
    uint32_t estimated_count = 1000;
    ctx->lazy_binds = (BindEntry*)calloc(estimated_count, sizeof(BindEntry));
    ctx->lazy_bind_count = 0;
    
    fseek(ctx->macho_ctx->file, ctx->macho_ctx->lazy_bind_off, SEEK_SET);
    if (!reloc_range_ok(ctx->macho_ctx, ctx->macho_ctx->lazy_bind_off, ctx->macho_ctx->lazy_bind_size)) return false;
    uint8_t *lazy_data = malloc(ctx->macho_ctx->lazy_bind_size);
    if (!lazy_data) return false;
    if (fread(lazy_data, 1, ctx->macho_ctx->lazy_bind_size, ctx->macho_ctx->file) != ctx->macho_ctx->lazy_bind_size) {
        free(lazy_data);
        return false;
    }
    
    BindType type = REDYNE_BIND_TYPE_POINTER;
    int32_t library_ordinal = 0;
    int64_t addend = 0;
    uint32_t segment_index = 0;
    uint64_t segment_offset = 0;
    char *symbol_name = NULL;
    uint8_t symbol_flags = 0;
    
    uint32_t i = 0;
    while (i < ctx->macho_ctx->lazy_bind_size) {
        uint8_t byte = lazy_data[i++];
        uint8_t opcode = byte & 0xF0;
        uint8_t immediate = byte & 0x0F;
        
        switch (opcode) {
            case 0x00:
                symbol_name = NULL;
                break;
                
            case 0x10:
                library_ordinal = immediate;
                break;
                
            case 0x30:
                if (immediate == 0) library_ordinal = 0;
                else library_ordinal = (int8_t)(0xF0 | immediate);
                break;
                
            case 0x40:
                symbol_flags = immediate;
                symbol_name = (char*)&lazy_data[i];
                i += strlen(symbol_name) + 1;
                break;
                
            case 0x70:
                segment_index = immediate;
                segment_offset = 0;
                for (int shift = 0; i < ctx->macho_ctx->lazy_bind_size; shift += 7) {
                    uint8_t b = lazy_data[i++];
                    segment_offset |= ((uint64_t)(b & 0x7F) << shift);
                    if ((b & 0x80) == 0) break;
                }
                break;
                
            case 0x90:
                if (symbol_name && reloc_ensure((void**)&ctx->lazy_binds, &estimated_count, ctx->lazy_bind_count, sizeof(BindEntry), RELOC_MAX_BINDS, &ctx->truncated)) {
                    ctx->lazy_binds[ctx->lazy_bind_count].address = segment_offset;
                    ctx->lazy_binds[ctx->lazy_bind_count].type = type;
                    ctx->lazy_binds[ctx->lazy_bind_count].library_ordinal = library_ordinal;
                    ctx->lazy_binds[ctx->lazy_bind_count].addend = addend;
                    ctx->lazy_binds[ctx->lazy_bind_count].symbol_name = strdup(symbol_name);
                    ctx->lazy_binds[ctx->lazy_bind_count].symbol_flags = symbol_flags;
                    ctx->lazy_binds[ctx->lazy_bind_count].is_weak = false;
                    ctx->lazy_binds[ctx->lazy_bind_count].is_lazy = true;
                    ctx->lazy_bind_count++;
                }
                segment_offset += 8;
                break;
        }
    }
    
    free(lazy_data);
    return true;
}

bool reloc_parse_weak_bind(RelocationContext *ctx) {
    if (!ctx || !ctx->macho_ctx || !ctx->macho_ctx->has_dyld_info) return false;
    if (ctx->macho_ctx->weak_bind_size == 0) return true;
    
    uint32_t estimated_count = 500;
    ctx->weak_binds = (BindEntry*)calloc(estimated_count, sizeof(BindEntry));
    ctx->weak_bind_count = 0;
    
    fseek(ctx->macho_ctx->file, ctx->macho_ctx->weak_bind_off, SEEK_SET);
    if (!reloc_range_ok(ctx->macho_ctx, ctx->macho_ctx->weak_bind_off, ctx->macho_ctx->weak_bind_size)) return false;
    uint8_t *weak_data = malloc(ctx->macho_ctx->weak_bind_size);
    if (!weak_data) return false;
    if (fread(weak_data, 1, ctx->macho_ctx->weak_bind_size, ctx->macho_ctx->file) != ctx->macho_ctx->weak_bind_size) {
        free(weak_data);
        return false;
    }
    
    BindType type = REDYNE_BIND_TYPE_POINTER;
    int32_t library_ordinal = 0;
    int64_t addend = 0;
    uint32_t segment_index = 0;
    uint64_t segment_offset = 0;
    char *symbol_name = NULL;
    uint8_t symbol_flags = 0;
    uint64_t count = 0;
    uint64_t skip = 0;
    
    uint32_t i = 0;
    while (i < ctx->macho_ctx->weak_bind_size) {
        uint8_t byte = weak_data[i++];
        uint8_t opcode = byte & 0xF0;
        uint8_t immediate = byte & 0x0F;
        
        switch (opcode) {
            case 0x00:
                goto done_weak;
                
            case 0x10:
                library_ordinal = immediate;
                break;
                
            case 0x30:
                if (immediate == 0) library_ordinal = 0;
                else library_ordinal = (int8_t)(0xF0 | immediate);
                break;
                
            case 0x40:
                symbol_flags = immediate;
                symbol_name = (char*)&weak_data[i];
                i += strlen(symbol_name) + 1;
                break;
                
            case 0x50:
                type = (BindType)immediate;
                break;
                
            case 0x60:
                addend = 0;
                for (int shift = 0; i < ctx->macho_ctx->weak_bind_size; shift += 7) {
                    uint8_t b = weak_data[i++];
                    addend |= ((int64_t)(b & 0x7F) << shift);
                    if ((b & 0x80) == 0) {
                        if (shift < 64 && (b & 0x40)) addend |= (~0ULL << (shift + 7));
                        break;
                    }
                }
                break;
                
            case 0x70:
                segment_index = immediate;
                segment_offset = 0;
                for (int shift = 0; i < ctx->macho_ctx->weak_bind_size; shift += 7) {
                    uint8_t b = weak_data[i++];
                    segment_offset |= ((uint64_t)(b & 0x7F) << shift);
                    if ((b & 0x80) == 0) break;
                }
                break;
                
            case 0x80:
                {
                    uint64_t delta = 0;
                    for (int shift = 0; i < ctx->macho_ctx->weak_bind_size; shift += 7) {
                        uint8_t b = weak_data[i++];
                        delta |= ((uint64_t)(b & 0x7F) << shift);
                        if ((b & 0x80) == 0) break;
                    }
                    segment_offset += delta;
                }
                break;
                
            case 0x90:
                if (symbol_name && reloc_ensure((void**)&ctx->weak_binds, &estimated_count, ctx->weak_bind_count, sizeof(BindEntry), RELOC_MAX_BINDS, &ctx->truncated)) {
                    ctx->weak_binds[ctx->weak_bind_count].address = segment_offset;
                    ctx->weak_binds[ctx->weak_bind_count].type = type;
                    ctx->weak_binds[ctx->weak_bind_count].library_ordinal = library_ordinal;
                    ctx->weak_binds[ctx->weak_bind_count].addend = addend;
                    ctx->weak_binds[ctx->weak_bind_count].symbol_name = strdup(symbol_name);
                    ctx->weak_binds[ctx->weak_bind_count].symbol_flags = symbol_flags;
                    ctx->weak_binds[ctx->weak_bind_count].is_weak = true;
                    ctx->weak_binds[ctx->weak_bind_count].is_lazy = false;
                    ctx->weak_bind_count++;
                }
                segment_offset += 8;
                break;
                
            case 0xA0:
                if (symbol_name && reloc_ensure((void**)&ctx->weak_binds, &estimated_count, ctx->weak_bind_count, sizeof(BindEntry), RELOC_MAX_BINDS, &ctx->truncated)) {
                    ctx->weak_binds[ctx->weak_bind_count].address = segment_offset;
                    ctx->weak_binds[ctx->weak_bind_count].type = type;
                    ctx->weak_binds[ctx->weak_bind_count].library_ordinal = library_ordinal;
                    ctx->weak_binds[ctx->weak_bind_count].addend = addend;
                    ctx->weak_binds[ctx->weak_bind_count].symbol_name = strdup(symbol_name);
                    ctx->weak_binds[ctx->weak_bind_count].symbol_flags = symbol_flags;
                    ctx->weak_binds[ctx->weak_bind_count].is_weak = true;
                    ctx->weak_binds[ctx->weak_bind_count].is_lazy = false;
                    ctx->weak_bind_count++;
                }
                {
                    uint64_t delta = 0;
                    for (int shift = 0; i < ctx->macho_ctx->weak_bind_size; shift += 7) {
                        uint8_t b = weak_data[i++];
                        delta |= ((uint64_t)(b & 0x7F) << shift);
                        if ((b & 0x80) == 0) break;
                    }
                    segment_offset += delta + 8;
                }
                break;
                
            case 0xC0:
                count = 0;
                for (int shift = 0; i < ctx->macho_ctx->weak_bind_size; shift += 7) {
                    uint8_t b = weak_data[i++];
                    count |= ((uint64_t)(b & 0x7F) << shift);
                    if ((b & 0x80) == 0) break;
                }
                skip = 0;
                for (int shift = 0; i < ctx->macho_ctx->weak_bind_size; shift += 7) {
                    uint8_t b = weak_data[i++];
                    skip |= ((uint64_t)(b & 0x7F) << shift);
                    if ((b & 0x80) == 0) break;
                }
                for (uint64_t j = 0; j < count && reloc_ensure((void**)&ctx->weak_binds, &estimated_count, ctx->weak_bind_count, sizeof(BindEntry), RELOC_MAX_BINDS, &ctx->truncated); j++) {
                    if (symbol_name) {
                        ctx->weak_binds[ctx->weak_bind_count].address = segment_offset;
                        ctx->weak_binds[ctx->weak_bind_count].type = type;
                        ctx->weak_binds[ctx->weak_bind_count].library_ordinal = library_ordinal;
                        ctx->weak_binds[ctx->weak_bind_count].addend = addend;
                        ctx->weak_binds[ctx->weak_bind_count].symbol_name = strdup(symbol_name);
                        ctx->weak_binds[ctx->weak_bind_count].symbol_flags = symbol_flags;
                        ctx->weak_binds[ctx->weak_bind_count].is_weak = true;
                        ctx->weak_binds[ctx->weak_bind_count].is_lazy = false;
                        ctx->weak_bind_count++;
                    }
                    segment_offset += skip + 8;
                }
                break;
        }
    }
    
done_weak:
    free(weak_data);
    return true;
}

#pragma mark - Export Parsing

static void walk_export_trie(const uint8_t *start, const uint8_t *p, const uint8_t *end,
                             char *symbol_name, int name_len, RelocationContext *ctx,
                             uint32_t *capacity, uint32_t *budget) {
    if (p >= end || name_len >= 255) return;
    // A crafted trie can loop back on itself and fan out exponentially; bound total work.
    if (*budget == 0) return;
    (*budget)--;

    uint64_t terminal_size = 0;
    for (int shift = 0; p < end && shift < 64; shift += 7) {
        uint8_t b = *p++;
        terminal_size |= ((uint64_t)(b & 0x7F) << shift);
        if ((b & 0x80) == 0) break;
    }
    // Compare against the remaining length so `p + huge` can never wrap.
    if (terminal_size > (uint64_t)(end - p)) return;
    const uint8_t *children_base = p + terminal_size;
    
    if (terminal_size > 0) {
        uint64_t flags = 0;
        for (int shift = 0; p < children_base && shift < 64; shift += 7) {
            uint8_t b = *p++;
            flags |= ((uint64_t)(b & 0x7F) << shift);
            if ((b & 0x80) == 0) break;
        }
        
        uint64_t address = 0;
        for (int shift = 0; p < children_base && shift < 64; shift += 7) {
            uint8_t b = *p++;
            address |= ((uint64_t)(b & 0x7F) << shift);
            if ((b & 0x80) == 0) break;
        }
        
        if (name_len > 0 && address > 0 &&
            reloc_ensure((void**)&ctx->exports, capacity, ctx->export_count,
                         sizeof(ExportEntry), RELOC_MAX_EXPORTS, &ctx->truncated)) {
            ctx->exports[ctx->export_count].address = address;
            ctx->exports[ctx->export_count].flags = flags;
            ctx->exports[ctx->export_count].symbol_name = strndup(symbol_name, name_len);
            ctx->export_count++;
        }
    }
    
    if (children_base >= end) return;
    p = children_base;
    uint8_t child_count = *p++;
    
    for (uint8_t i = 0; i < child_count && p < end; i++) {
        int edge_len = 0;
        while (p < end && *p != '\0') {
            if (name_len + edge_len < 255) {
                symbol_name[name_len + edge_len] = *p;
            }
            edge_len++;
            p++;
        }
        p++;
        
        uint32_t child_offset = 0;
        for (int shift = 0; p < end && shift < 32; shift += 7) {
            uint8_t b = *p++;
            child_offset |= ((uint32_t)(b & 0x7F) << shift);
            if ((b & 0x80) == 0) break;
        }
        
        if (child_offset < (uint64_t)(end - start)) {
            walk_export_trie(start, start + child_offset, end,
                           symbol_name, name_len + edge_len, 
                           ctx, capacity, budget);
        }
    }
}

bool reloc_parse_exports(RelocationContext *ctx) {
    if (!ctx || !ctx->macho_ctx || !ctx->macho_ctx->has_dyld_info) return false;
    if (ctx->macho_ctx->export_size == 0) return true;
    
    uint32_t estimated_count = 5000;
    ctx->exports = (ExportEntry*)calloc(estimated_count, sizeof(ExportEntry));
    ctx->export_count = 0;
    
    fseek(ctx->macho_ctx->file, ctx->macho_ctx->export_off, SEEK_SET);
    if (!reloc_range_ok(ctx->macho_ctx, ctx->macho_ctx->export_off, ctx->macho_ctx->export_size)) return false;
    uint8_t *export_data = malloc(ctx->macho_ctx->export_size);
    if (!export_data) return false;
    
    if (fread(export_data, 1, ctx->macho_ctx->export_size, ctx->macho_ctx->file) != ctx->macho_ctx->export_size) {
        free(export_data);
        return false;
    }
    
    char symbol_buffer[256] = {0};
    uint32_t trie_budget = RELOC_MAX_TRIE_NODES;
    walk_export_trie(export_data, export_data, export_data + ctx->macho_ctx->export_size,
                    symbol_buffer, 0, ctx, &estimated_count, &trie_budget);
    
    free(export_data);
    return true;
}

#pragma mark - Utility Functions

uint64_t reloc_apply_slide(RelocationContext *ctx, uint64_t address) {
    if (!ctx) return address;
    return address + ctx->slide;
}

BindEntry* reloc_find_bind(RelocationContext *ctx, uint64_t address) {
    if (!ctx || !ctx->binds) return NULL;
    
    for (uint32_t i = 0; i < ctx->bind_count; i++) {
        if (ctx->binds[i].address == address) {
            return &ctx->binds[i];
        }
    }
    
    return NULL;
}

ExportEntry* reloc_find_export(RelocationContext *ctx, const char *name) {
    if (!ctx || !ctx->exports || !name) return NULL;
    
    for (uint32_t i = 0; i < ctx->export_count; i++) {
        if (ctx->exports[i].symbol_name && strcmp(ctx->exports[i].symbol_name, name) == 0) {
            return &ctx->exports[i];
        }
    }
    
    return NULL;
}

