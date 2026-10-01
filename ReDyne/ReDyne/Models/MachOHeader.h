#ifndef MachOHeader_h
#define MachOHeader_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <mach-o/nlist.h>

#pragma mark - Constants

#define MAX_FILE_SIZE (200 * 1024 * 1024)
#define MAX_LOAD_COMMANDS 10000
#define MAX_SEGMENTS 256
#define MAX_SECTIONS 4096
#define MAX_PARSE_WARNINGS 64
#define MAX_WARNING_LENGTH 256
#define MAX_RPATHS 64
#define PREFERRED_ARCH_ARM64E CPU_TYPE_ARM64
#define PREFERRED_ARCH_ARM64 CPU_TYPE_ARM64
#define PREFERRED_ARCH_X86_64 CPU_TYPE_X86_64

#pragma mark - Structures

typedef struct {
    char message[MAX_WARNING_LENGTH];
    uint32_t offset;     // file offset where issue was found
    uint32_t severity;   // 0=info, 1=warning, 2=error
} ParseWarning;

typedef struct {
    uint32_t magic;
    uint32_t cputype;
    uint32_t cpusubtype;
    uint32_t filetype;
    uint32_t ncmds;
    uint32_t sizeofcmds;
    uint32_t flags;
    uint64_t reserved;
    bool is_64bit;
    bool is_swapped;
} MachOHeaderInfo;

typedef struct {
    char segname[17];
    uint64_t vmaddr;
    uint64_t vmsize;
    uint64_t fileoff;
    uint64_t filesize;
    uint32_t maxprot;
    uint32_t initprot;
    uint32_t nsects;
    uint32_t flags;
} SegmentInfo;

typedef struct {
    char sectname[17];
    char segname[17];
    uint64_t addr;
    uint64_t size;
    uint32_t offset;
    uint32_t align;
    uint32_t reloff;
    uint32_t nreloc;
    uint32_t flags;
} SectionInfo;

typedef struct {
    uint32_t cmd;
    uint32_t cmdsize;
    void *data;
} LoadCommandInfo;

typedef struct {
    FILE *file;
    long file_size;
    MachOHeaderInfo header;
    
    uint32_t load_command_count;
    LoadCommandInfo *load_commands;
    uint32_t segment_count;
    SegmentInfo *segments;
    uint32_t section_count;
    SectionInfo *sections;
    uint64_t symtab_offset;    // file offsets are 64-bit (CWE-197 fix)
    uint32_t nsyms;
    uint64_t stroff;
    uint32_t strsize;
    uint64_t dysymtab_offset;

    bool has_dyld_info;
    uint64_t rebase_off;   uint32_t rebase_size;
    uint64_t bind_off;     uint32_t bind_size;
    uint64_t weak_bind_off; uint32_t weak_bind_size;
    uint64_t lazy_bind_off; uint32_t lazy_bind_size;
    uint64_t export_off;   uint32_t export_size;

    bool is_encrypted;
    uint64_t cryptoff;
    uint32_t cryptsize;
    uint32_t cryptid;
    uint8_t uuid[16];
    
    bool has_uuid;
    uint32_t min_version;
    uint32_t sdk_version;

    // Parse warnings
    ParseWarning warnings[MAX_PARSE_WARNINGS];
    uint32_t warning_count;

    // Entry point
    bool has_entry_point;
    uint64_t entry_point_offset;  // from LC_MAIN
    uint64_t entry_point_address; // resolved VA

    // Function starts
    bool has_function_starts;
    uint64_t function_starts_offset;
    uint32_t function_starts_size;

    // Data in code
    bool has_data_in_code;
    uint64_t data_in_code_offset;
    uint32_t data_in_code_size;

    // Chained fixups (modern iOS 15+ binaries)
    bool has_chained_fixups;
    uint64_t chained_fixups_offset;
    uint32_t chained_fixups_size;

    // Exports trie (new style, separate from LC_DYLD_INFO)
    bool has_exports_trie;
    uint64_t exports_trie_offset;
    uint32_t exports_trie_size;

    // Build version info
    uint32_t platform;
    uint32_t minos;
    uint32_t sdk;
    uint32_t build_tool_count;

    // Source version
    uint64_t source_version;
    bool has_source_version;

    // Non-zero when the Mach-O is embedded inside a container (e.g. bplist wrapper)
    uint64_t base_offset;

    // Security-relevant flags
    bool is_pie;
    bool has_restrict_segment;
    bool allows_stack_execution;
    bool no_heap_execution;

    // RPaths
    char *rpaths[MAX_RPATHS];
    uint32_t rpath_count;

    // Linker option strings
    uint32_t linker_option_count;

} MachOContext;

#pragma mark - Function Declarations

MachOContext* macho_open(const char *filepath, char *error_msg);

bool macho_parse_header(MachOContext *ctx);

bool macho_parse_load_commands(MachOContext *ctx);

uint32_t macho_extract_segments(MachOContext *ctx);

uint32_t macho_extract_sections(MachOContext *ctx);

bool macho_is_fat_binary(MachOContext *ctx);

uint64_t macho_select_architecture(MachOContext *ctx);

bool macho_is_valid_magic(uint32_t magic);

const char* macho_magic_string(uint32_t magic);

const char* macho_cpu_type_string(uint32_t cputype);

const char* macho_cpu_subtype_string(uint32_t cputype, uint32_t cpusubtype);

const char* macho_filetype_string(uint32_t filetype);

void macho_close(MachOContext *ctx);

void macho_add_warning(MachOContext *ctx, const char *message, uint32_t offset, uint32_t severity);
bool macho_validate_load_commands(MachOContext *ctx);
bool macho_resolve_entry_point(MachOContext *ctx);
const char* macho_flags_description(uint32_t flags, char *buffer, size_t bufsize);
const char* macho_platform_string(uint32_t platform);
const char* macho_load_command_name(uint32_t cmd);

uint16_t swap_uint16(uint16_t val);
uint32_t swap_uint32(uint32_t val);
uint64_t swap_uint64(uint64_t val);

#endif

