#include "StringExtractor.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdio.h>
#include <sys/stat.h>

#define MIN_STRING_LENGTH 4
#define MAX_STRING_LENGTH 4096

#pragma mark - Helper Functions

/// True when [offset, offset+size) lies inside the file. Section/segment sizes come from
/// the (untrusted) binary, so they must be validated before being used to size a buffer.
static bool range_within_file(FILE *file, uint64_t offset, uint64_t size) {
    struct stat st;
    if (!file || fstat(fileno(file), &st) != 0 || st.st_size < 0) return false;
    uint64_t fsize = (uint64_t)st.st_size;
    return offset <= fsize && size <= fsize - offset;
}

bool redyne_is_printable(char c) {
    return (c >= 0x20 && c <= 0x7E) || c == '\t' || c == '\n' || c == '\r';
}

static bool string_context_resize(StringContext *ctx) {
    uint32_t new_capacity = ctx->capacity * 2;
    void *new_ptr = realloc(ctx->strings, new_capacity * sizeof(StringInfo));
    if (!new_ptr) return false;
    ctx->strings = new_ptr;
    ctx->capacity = new_capacity;
    return true;
}

static void add_string(StringContext *ctx, uint64_t address, uint64_t offset, 
                      const char *content, uint32_t length, const char *section_name,
                      bool is_cstring) {
    if (ctx->count >= ctx->capacity) {
        if (!string_context_resize(ctx)) return;
    }

    StringInfo *info = &ctx->strings[ctx->count++];
    info->address = address;
    info->offset = offset;
    info->length = length;
    info->is_cstring = is_cstring;
    info->is_unicode = false;
    
    info->content = malloc(length + 1);
    if (!info->content) {
        ctx->count--;
        return;
    }
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
        
        if (redyne_is_printable((char)byte)) {
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
                                  uint64_t size, uint64_t vmaddr,
                                  const char *section_name) {
    if (!ctx || !file || size == 0) return 0;
    const char *sect_name = section_name ? section_name : "__cstring";
    
    if (!range_within_file(file, offset, size)) return 0;
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
                if (!redyne_is_printable(str[i])) {
                    all_printable = false;
                    break;
                }
            }
            
            if (all_printable) {
                add_string(ctx, vmaddr + pos, offset + pos, str, (uint32_t)len, sect_name, true);
                found++;
            }
        }
        pos += len + 1;
    }
    
    free(data);
    return found;
}

uint32_t string_extract_cfstrings(StringContext *ctx, FILE *file,
                                   uint64_t section_offset, uint64_t section_size,
                                   uint64_t section_vmaddr, bool is_64bit,
                                   const uint8_t *file_data, size_t file_data_size,
                                   uint64_t text_segment_vmaddr, uint64_t text_segment_fileoff) {
    if (!ctx || !file || section_size == 0) return 0;

    /* CFString struct layout:
     * 64-bit: { uint64_t isa, uint64_t flags, uint64_t str_ptr, uint64_t length } = 32 bytes
     * 32-bit: { uint32_t isa, uint32_t flags, uint32_t str_ptr, uint32_t length } = 16 bytes
     */
    size_t entry_size = is_64bit ? 32 : 16;

    if (section_size % entry_size != 0) return 0;

    if (!range_within_file(file, section_offset, section_size)) return 0;
    uint8_t *data = malloc(section_size);
    if (!data) return 0;

    fseek(file, section_offset, SEEK_SET);
    if (fread(data, 1, section_size, file) != section_size) {
        free(data);
        return 0;
    }

    uint32_t found = 0;
    uint64_t num_entries = section_size / entry_size;

    for (uint64_t i = 0; i < num_entries; i++) {
        uint8_t *entry = data + (i * entry_size);
        uint64_t str_ptr;
        uint64_t str_len;

        if (is_64bit) {
            memcpy(&str_ptr, entry + 16, sizeof(uint64_t));
            memcpy(&str_len, entry + 24, sizeof(uint64_t));
        } else {
            uint32_t ptr32, len32;
            memcpy(&ptr32, entry + 8, sizeof(uint32_t));
            memcpy(&len32, entry + 12, sizeof(uint32_t));
            str_ptr = ptr32;
            str_len = len32;
        }

        if (str_len == 0 || str_len >= MAX_STRING_LENGTH) continue;

        /* Convert VM address to file offset — guard against underflow (CWE-191):
         * if str_ptr is below text_segment_vmaddr the subtraction wraps to a
         * huge value; adding text_segment_fileoff can wrap back to a small value
         * that slips past the bounds check, causing reads from wrong file regions. */
        if (str_ptr < text_segment_vmaddr) continue;
        uint64_t str_file_offset = (str_ptr - text_segment_vmaddr) + text_segment_fileoff;

        if (str_file_offset >= file_data_size) continue;
        if (str_file_offset + str_len > file_data_size) continue;

        char *buf = malloc(str_len + 1);
        if (!buf) continue;

        fseek(file, str_file_offset, SEEK_SET);
        if (fread(buf, 1, str_len, file) != str_len) {
            free(buf);
            continue;
        }
        buf[str_len] = '\0';

        /* Verify all characters are printable */
        bool all_printable = true;
        for (uint64_t j = 0; j < str_len; j++) {
            if (!redyne_is_printable(buf[j])) {
                all_printable = false;
                break;
            }
        }

        if (all_printable && str_len >= MIN_STRING_LENGTH) {
            uint64_t entry_vmaddr = section_vmaddr + (i * entry_size);
            add_string(ctx, entry_vmaddr, section_offset + (i * entry_size),
                      buf, (uint32_t)str_len, "__cfstring", false);
            found++;
        }

        free(buf);
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

