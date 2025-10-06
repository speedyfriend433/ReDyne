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
#define PREFERRED_ARCH_ARM64E CPU_TYPE_ARM64
#define PREFERRED_ARCH_ARM64 CPU_TYPE_ARM64
#define PREFERRED_ARCH_X86_64 CPU_TYPE_X86_64

#pragma mark - Structures

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
    char segname[16];
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
    char sectname[16];
    char segname[16];
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
    uint32_t symtab_offset;
    uint32_t nsyms;
    uint32_t stroff;
    uint32_t strsize;
    uint32_t dysymtab_offset;
    
    bool has_dyld_info;
    uint32_t rebase_off, rebase_size;
    uint32_t bind_off, bind_size;
    uint32_t weak_bind_off, weak_bind_size;
    uint32_t lazy_bind_off, lazy_bind_size;
    uint32_t export_off, export_size;
    
    bool is_encrypted;
    uint32_t cryptoff;
    uint32_t cryptsize;
    uint32_t cryptid;
    uint8_t uuid[16];
    
    bool has_uuid;
    uint32_t min_version;
    uint32_t sdk_version;
    
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

uint16_t swap_uint16(uint16_t val);
uint32_t swap_uint32(uint32_t val);
uint64_t swap_uint64(uint64_t val);

#endif

