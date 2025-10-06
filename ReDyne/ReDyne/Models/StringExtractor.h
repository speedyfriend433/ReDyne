#ifndef StringExtractor_h
#define StringExtractor_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#pragma mark - String Information

typedef struct {
    uint64_t address;
    uint64_t offset;
    char *content;
    uint32_t length;
    char section[64];
    bool is_cstring;
    bool is_unicode;
} StringInfo;

typedef struct {
    StringInfo *strings;
    uint32_t count;
    uint32_t capacity;
} StringContext;

#pragma mark - Function Declarations

StringContext* string_context_create(uint32_t initial_capacity);

uint32_t string_extract_from_data(StringContext *ctx, const uint8_t *data, size_t size, 
                                   uint64_t base_address, const char *section_name, 
                                   uint32_t min_length);

uint32_t string_extract_cstrings(StringContext *ctx, FILE *file, uint64_t offset, 
                                  uint64_t size, uint64_t vmaddr);

void string_context_sort(StringContext *ctx);

void string_context_free(StringContext *ctx);

bool is_printable(char c);

#endif

