#include "StringExtractor.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MIN_STRING_LENGTH 4
#define MAX_STRING_LENGTH 4096

#pragma mark - Helper Functions

bool is_printable(char c) {
    return (c >= 0x20 && c <= 0x7E) || c == '\t' || c == '\n' || c == '\r';
}

static void string_context_resize(StringContext *ctx) {
    ctx->capacity *= 2;
    ctx->strings = realloc(ctx->strings, ctx->capacity * sizeof(StringInfo));
}

static void add_string(StringContext *ctx, uint64_t address, uint64_t offset, 
                      const char *content, uint32_t length, const char *section_name,
                      bool is_cstring) {
    if (ctx->count >= ctx->capacity) {
        string_context_resize(ctx);
    }
    
    StringInfo *info = &ctx->strings[ctx->count++];
    info->address = address;
    info->offset = offset;
    info->length = length;
    info->is_cstring = is_cstring;
    info->is_unicode = false;
    
    info->content = malloc(length + 1);
    memcpy(info->content, content, length);
    info->content[length] = '\0';
    
    strncpy(info->section, section_name, sizeof(info->section) - 1);
    info->section[sizeof(info->section) - 1] = '\0';
}

#pragma mark - Public Functions

StringContext* string_context_create(uint32_t initial_capacity) {
    StringContext *ctx = calloc(1, sizeof(StringContext));
    if (!ctx) return NULL;
    
    ctx->capacity = initial_capacity > 0 ? initial_capacity : 256;
    ctx->strings = calloc(ctx->capacity, sizeof(StringInfo));
    ctx->count = 0;
    
    if (!ctx->strings) {
        free(ctx);
        return NULL;
    }
    
    return ctx;
}

uint32_t string_extract_from_data(StringContext *ctx, const uint8_t *data, size_t size,
                                   uint64_t base_address, const char *section_name,
                                   uint32_t min_length) {
    if (!ctx || !data || size == 0) return 0;
    if (min_length < MIN_STRING_LENGTH) min_length = MIN_STRING_LENGTH;
    
    uint32_t found = 0;
    char buffer[MAX_STRING_LENGTH];
    uint32_t buf_pos = 0;
    uint64_t string_start = 0;
    
    for (size_t i = 0; i < size; i++) {
        uint8_t byte = data[i];
        
        if (is_printable((char)byte)) {
            if (buf_pos == 0) {
                string_start = i;
            }
            
            if (buf_pos < MAX_STRING_LENGTH - 1) {
                buffer[buf_pos++] = (char)byte;
            }
        } else if (byte == 0 && buf_pos >= min_length) {
            buffer[buf_pos] = '\0';
            
            add_string(ctx, base_address + string_start, string_start,
                      buffer, buf_pos, section_name, false);
            
            found++;
            buf_pos = 0;
        } else {
            buf_pos = 0;
        }
    }
    
    return found;
}

uint32_t string_extract_cstrings(StringContext *ctx, FILE *file, uint64_t offset,
                                  uint64_t size, uint64_t vmaddr) {
    if (!ctx || !file || size == 0) return 0;
    
    uint8_t *data = malloc(size);
    if (!data) return 0;
    
    fseek(file, offset, SEEK_SET);
    if (fread(data, 1, size, file) != size) {
        free(data);
        return 0;
    }
    
    uint32_t found = 0;
    uint64_t pos = 0;
    
    while (pos < size) {
        const char *str = (const char *)(data + pos);
        size_t len = strnlen(str, size - pos);
        
        if (len >= MIN_STRING_LENGTH && len < MAX_STRING_LENGTH) {
            bool all_printable = true;
            for (size_t i = 0; i < len; i++) {
                if (!is_printable(str[i])) {
                    all_printable = false;
                    break;
                }
            }
            
            if (all_printable) {
                add_string(ctx, vmaddr + pos, offset + pos, str, len, "__cstring", true);
                found++;
            }
        }
        pos += len + 1;
    }
    
    free(data);
    return found;
}

static int compare_strings_by_address(const void *a, const void *b) {
    const StringInfo *sa = (const StringInfo *)a;
    const StringInfo *sb = (const StringInfo *)b;
    
    if (sa->address < sb->address) return -1;
    if (sa->address > sb->address) return 1;
    return 0;
}

void string_context_sort(StringContext *ctx) {
    if (!ctx || ctx->count == 0) return;
    qsort(ctx->strings, ctx->count, sizeof(StringInfo), compare_strings_by_address);
}

void string_context_free(StringContext *ctx) {
    if (!ctx) return;
    
    if (ctx->strings) {
        for (uint32_t i = 0; i < ctx->count; i++) {
            if (ctx->strings[i].content) {
                free(ctx->strings[i].content);
            }
        }
        free(ctx->strings);
    }
    
    free(ctx);
}

