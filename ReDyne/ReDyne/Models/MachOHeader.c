#include "MachOHeader.h"
#include <stdlib.h>
#include <string.h>
#include <mach/machine.h>

///# magic: "bpli" which is a first 4 bytes of "bplist00" read as LE uint32
#define BPLIST_MAGIC_LE 0x696C7062U

#pragma mark - Byte Swapping Utilities

uint16_t swap_uint16(uint16_t val) {
    return (val << 8) | (val >> 8);
}

uint32_t swap_uint32(uint32_t val) {
    return ((val << 24) & 0xFF000000) |
           ((val <<  8) & 0x00FF0000) |
           ((val >>  8) & 0x0000FF00) |
           ((val >> 24) & 0x000000FF);
}

uint64_t swap_uint64(uint64_t val) {
    return ((uint64_t)swap_uint32((uint32_t)val) << 32) |
           (uint64_t)swap_uint32((uint32_t)(val >> 32));
}

#pragma mark - Magic Number Validation

bool macho_is_valid_magic(uint32_t magic) {
    return (magic == MH_MAGIC_64 || magic == MH_MAGIC ||
            magic == MH_CIGAM_64 || magic == MH_CIGAM ||
            magic == FAT_MAGIC || magic == FAT_CIGAM ||
            magic == 0xcafebabf || magic == 0xbfbafeca);
}

const char* macho_magic_string(uint32_t magic) {
    switch (magic) {
        case MH_MAGIC_64: return "MH_MAGIC_64 (64-bit Mach-O)";
        case MH_MAGIC: return "MH_MAGIC (32-bit Mach-O)";
        case MH_CIGAM_64: return "MH_CIGAM_64 (64-bit Mach-O, swapped)";
        case MH_CIGAM: return "MH_CIGAM (32-bit Mach-O, swapped)";
        case FAT_MAGIC: return "FAT_MAGIC (Universal Binary)";
        case FAT_CIGAM: return "FAT_CIGAM (Universal Binary, swapped)";
        case 0xcafebabf: return "FAT_MAGIC_64 (64-bit Universal Binary)";
        case 0xbfbafeca: return "FAT_CIGAM_64 (64-bit Universal Binary, swapped)";
        case BPLIST_MAGIC_LE: return "Binary Property List (bplist container)";
        default: return "Unknown/Invalid";
    }
}

#pragma mark - String Helpers

const char* macho_cpu_type_string(uint32_t cputype) {
    uint32_t base_type = cputype & 0x00FFFFFF;
    
    switch (base_type) {
        case CPU_TYPE_ARM: return "ARM";
        case CPU_TYPE_ARM64:
            if (cputype == 0x0200000C) return "ARM64_32";
            return "ARM64";
        case CPU_TYPE_X86: return "i386";
        case CPU_TYPE_X86_64: return "x86_64";
        case CPU_TYPE_POWERPC: return "PowerPC";
        case CPU_TYPE_POWERPC64: return "PowerPC64";
        default: 
            return "Unknown";
    }
}

const char* macho_cpu_subtype_string(uint32_t cputype, uint32_t cpusubtype) {
    cpusubtype &= ~CPU_SUBTYPE_MASK;
    
    switch (cputype) {
        case CPU_TYPE_ARM64:
            switch (cpusubtype) {
                case 0: return "ARM64_ALL";
                case 1: return "ARM64_V8";
                case 2: return "ARM64E";
                default: return "ARM64_UNKNOWN";
            }
        case CPU_TYPE_ARM:
            switch (cpusubtype) {
                case 5: return "ARMv4T";
                case 6: return "ARMv6";
                case 7: return "ARMv5TEJ";
                case 8: return "XSCALE";
                case 9: return "ARMv7";
                case 10: return "ARMv7F";
                case 11: return "ARMv7S";
                case 12: return "ARMv7K";
                case 14: return "ARMv6M";
                case 15: return "ARMv7M";
                case 16: return "ARMv7EM";
                default: return "ARM_UNKNOWN";
            }
        case CPU_TYPE_X86_64:
            switch (cpusubtype) {
                case 3: return "x86_64_ALL";
                case 4: return "x86_64_ARCH1";
                case 8: return "x86_64_H (Haswell)";
                default: return "x86_64_UNKNOWN";
            }
        case CPU_TYPE_X86:
            return "i386";
        default:
            return "";
    }
}

const char* macho_filetype_string(uint32_t filetype) {
    switch (filetype) {
        case MH_OBJECT: return "Object File";
        case MH_EXECUTE: return "Executable";
        case MH_FVMLIB: return "Fixed VM Library";
        case MH_CORE: return "Core Dump";
        case MH_PRELOAD: return "Preloaded Executable";
        case MH_DYLIB: return "Dynamic Library";
        case MH_DYLINKER: return "Dynamic Linker";
        case MH_BUNDLE: return "Bundle";
        case MH_DYLIB_STUB: return "Dynamic Library Stub";
        case MH_DSYM: return "dSYM Debug Symbols";
        case MH_KEXT_BUNDLE: return "Kernel Extension";
        case 0xC: return "File Set";
        default:
            return "Unknown File Type";
    }
}

#pragma mark - Parse Warning System

void macho_add_warning(MachOContext *ctx, const char *message, uint32_t offset, uint32_t severity) {
    if (!ctx || ctx->warning_count >= MAX_PARSE_WARNINGS) return;
    ParseWarning *w = &ctx->warnings[ctx->warning_count++];
    strncpy(w->message, message, MAX_WARNING_LENGTH - 1);
    w->message[MAX_WARNING_LENGTH - 1] = '\0';
    w->offset = offset;
    w->severity = severity;
}

#pragma mark - Load Command Name

const char* macho_load_command_name(uint32_t cmd) {
    switch (cmd) {
        case LC_SEGMENT: return "LC_SEGMENT";
        case LC_SYMTAB: return "LC_SYMTAB";
        case LC_SYMSEG: return "LC_SYMSEG";
        case LC_THREAD: return "LC_THREAD";
        case LC_UNIXTHREAD: return "LC_UNIXTHREAD";
        case LC_LOADFVMLIB: return "LC_LOADFVMLIB";
        case LC_IDFVMLIB: return "LC_IDFVMLIB";
        case LC_IDENT: return "LC_IDENT";
        case LC_FVMFILE: return "LC_FVMFILE";
        case LC_PREPAGE: return "LC_PREPAGE";
        case LC_DYSYMTAB: return "LC_DYSYMTAB";
        case LC_LOAD_DYLIB: return "LC_LOAD_DYLIB";
        case LC_ID_DYLIB: return "LC_ID_DYLIB";
        case LC_LOAD_DYLINKER: return "LC_LOAD_DYLINKER";
        case LC_ID_DYLINKER: return "LC_ID_DYLINKER";
        case LC_PREBOUND_DYLIB: return "LC_PREBOUND_DYLIB";
        case LC_ROUTINES: return "LC_ROUTINES";
        case LC_SUB_FRAMEWORK: return "LC_SUB_FRAMEWORK";
        case LC_SUB_UMBRELLA: return "LC_SUB_UMBRELLA";
        case LC_SUB_CLIENT: return "LC_SUB_CLIENT";
        case LC_SUB_LIBRARY: return "LC_SUB_LIBRARY";
        case LC_TWOLEVEL_HINTS: return "LC_TWOLEVEL_HINTS";
        case LC_PREBIND_CKSUM: return "LC_PREBIND_CKSUM";
        case LC_LOAD_WEAK_DYLIB: return "LC_LOAD_WEAK_DYLIB";
        case LC_SEGMENT_64: return "LC_SEGMENT_64";
        case LC_ROUTINES_64: return "LC_ROUTINES_64";
        case LC_UUID: return "LC_UUID";
        case LC_RPATH: return "LC_RPATH";
        case LC_CODE_SIGNATURE: return "LC_CODE_SIGNATURE";
        case LC_SEGMENT_SPLIT_INFO: return "LC_SEGMENT_SPLIT_INFO";
        case LC_REEXPORT_DYLIB: return "LC_REEXPORT_DYLIB";
        case LC_LAZY_LOAD_DYLIB: return "LC_LAZY_LOAD_DYLIB";
        case LC_ENCRYPTION_INFO: return "LC_ENCRYPTION_INFO";
        case LC_DYLD_INFO: return "LC_DYLD_INFO";
        case LC_DYLD_INFO_ONLY: return "LC_DYLD_INFO_ONLY";
        case LC_LOAD_UPWARD_DYLIB: return "LC_LOAD_UPWARD_DYLIB";
        case LC_VERSION_MIN_MACOSX: return "LC_VERSION_MIN_MACOSX";
        case LC_VERSION_MIN_IPHONEOS: return "LC_VERSION_MIN_IPHONEOS";
        case LC_FUNCTION_STARTS: return "LC_FUNCTION_STARTS";
        case LC_DYLD_ENVIRONMENT: return "LC_DYLD_ENVIRONMENT";
        case LC_MAIN: return "LC_MAIN";
        case LC_DATA_IN_CODE: return "LC_DATA_IN_CODE";
        case LC_SOURCE_VERSION: return "LC_SOURCE_VERSION";
        case LC_DYLIB_CODE_SIGN_DRS: return "LC_DYLIB_CODE_SIGN_DRS";
        case LC_ENCRYPTION_INFO_64: return "LC_ENCRYPTION_INFO_64";
        case LC_LINKER_OPTION: return "LC_LINKER_OPTION";
        case LC_LINKER_OPTIMIZATION_HINT: return "LC_LINKER_OPTIMIZATION_HINT";
        case LC_VERSION_MIN_TVOS: return "LC_VERSION_MIN_TVOS";
        case LC_VERSION_MIN_WATCHOS: return "LC_VERSION_MIN_WATCHOS";
        case LC_NOTE: return "LC_NOTE";
        case LC_BUILD_VERSION: return "LC_BUILD_VERSION";
        case LC_DYLD_EXPORTS_TRIE: return "LC_DYLD_EXPORTS_TRIE";
        case LC_DYLD_CHAINED_FIXUPS: return "LC_DYLD_CHAINED_FIXUPS";
        case LC_FILESET_ENTRY: return "LC_FILESET_ENTRY";
        default: return "LC_UNKNOWN";
    }
}

#pragma mark - Flags Description

const char* macho_flags_description(uint32_t flags, char *buffer, size_t bufsize) {
    if (!buffer || bufsize == 0) return "";
    buffer[0] = '\0';

    struct { uint32_t flag; const char *name; } flag_table[] = {
        { MH_NOUNDEFS, "MH_NOUNDEFS" },
        { MH_INCRLINK, "MH_INCRLINK" },
        { MH_DYLDLINK, "MH_DYLDLINK" },
        { MH_BINDATLOAD, "MH_BINDATLOAD" },
        { MH_PREBOUND, "MH_PREBOUND" },
        { MH_SPLIT_SEGS, "MH_SPLIT_SEGS" },
        { MH_LAZY_INIT, "MH_LAZY_INIT" },
        { MH_TWOLEVEL, "MH_TWOLEVEL" },
        { MH_FORCE_FLAT, "MH_FORCE_FLAT" },
        { MH_NOMULTIDEFS, "MH_NOMULTIDEFS" },
        { MH_NOFIXPREBINDING, "MH_NOFIXPREBINDING" },
        { MH_PREBINDABLE, "MH_PREBINDABLE" },
        { MH_ALLMODSBOUND, "MH_ALLMODSBOUND" },
        { MH_SUBSECTIONS_VIA_SYMBOLS, "MH_SUBSECTIONS_VIA_SYMBOLS" },
        { MH_CANONICAL, "MH_CANONICAL" },
        { MH_WEAK_DEFINES, "MH_WEAK_DEFINES" },
        { MH_BINDS_TO_WEAK, "MH_BINDS_TO_WEAK" },
        { MH_ALLOW_STACK_EXECUTION, "MH_ALLOW_STACK_EXECUTION" },
        { MH_ROOT_SAFE, "MH_ROOT_SAFE" },
        { MH_SETUID_SAFE, "MH_SETUID_SAFE" },
        { MH_NO_REEXPORTED_DYLIBS, "MH_NO_REEXPORTED_DYLIBS" },
        { MH_PIE, "MH_PIE" },
        { MH_HAS_TLV_DESCRIPTORS, "MH_HAS_TLV_DESCRIPTORS" },
        { MH_NO_HEAP_EXECUTION, "MH_NO_HEAP_EXECUTION" },
        { MH_APP_EXTENSION_SAFE, "MH_APP_EXTENSION_SAFE" },
        { MH_DYLIB_IN_CACHE, "MH_DYLIB_IN_CACHE" },
    };

    size_t count = sizeof(flag_table) / sizeof(flag_table[0]);
    size_t pos = 0;
    bool first = true;

    for (size_t i = 0; i < count; i++) {
        if (flags & flag_table[i].flag) {
            size_t needed = strlen(flag_table[i].name) + (first ? 0 : 2);
            if (pos + needed + 1 >= bufsize) break;
            if (!first) {
                buffer[pos++] = ',';
                buffer[pos++] = ' ';
            }
            strcpy(buffer + pos, flag_table[i].name);
            pos += strlen(flag_table[i].name);
            first = false;
        }
    }
    buffer[pos] = '\0';
    return buffer;
}

#pragma mark - Platform String

const char* macho_platform_string(uint32_t platform) {
    switch (platform) {
        case PLATFORM_UNKNOWN: return "Unknown";
        case PLATFORM_MACOS: return "macOS";
        case PLATFORM_IOS: return "iOS";
        case PLATFORM_TVOS: return "tvOS";
        case PLATFORM_WATCHOS: return "watchOS";
        case PLATFORM_BRIDGEOS: return "bridgeOS";
        case PLATFORM_MACCATALYST: return "Mac Catalyst";
        case PLATFORM_IOSSIMULATOR: return "iOS Simulator";
        case PLATFORM_TVOSSIMULATOR: return "tvOS Simulator";
        case PLATFORM_WATCHOSSIMULATOR: return "watchOS Simulator";
        case PLATFORM_DRIVERKIT: return "DriverKit";
        case PLATFORM_VISIONOS: return "visionOS";
        case PLATFORM_VISIONOSSIMULATOR: return "visionOS Simulator";
        case PLATFORM_FIRMWARE: return "Firmware";
        case PLATFORM_SEPOS: return "SepOS";
        default: return "Unknown Platform";
    }
}

#pragma mark - Entry Point Resolution

bool macho_resolve_entry_point(MachOContext *ctx) {
    if (!ctx || !ctx->has_entry_point) return false;

    // Find __TEXT segment vmaddr
    for (uint32_t i = 0; i < ctx->segment_count; i++) {
        if (strncmp(ctx->segments[i].segname, "__TEXT", 16) == 0) {
            ctx->entry_point_address = ctx->segments[i].vmaddr + ctx->entry_point_offset;
            return true;
        }
    }
    return false;
}

#pragma mark - Load Command Validation

/// Minimum cmdsize required before the command payload may be cast to its struct.
static uint32_t macho_min_cmdsize(uint32_t cmd) {
    switch (cmd) {
        case LC_SYMTAB: return sizeof(struct symtab_command);
        case LC_DYLD_INFO:
        case LC_DYLD_INFO_ONLY: return sizeof(struct dyld_info_command);
        case LC_ENCRYPTION_INFO: return sizeof(struct encryption_info_command);
        case LC_ENCRYPTION_INFO_64: return sizeof(struct encryption_info_command_64);
        case LC_UUID: return sizeof(struct uuid_command);
        case LC_MAIN: return sizeof(struct entry_point_command);
        case LC_FUNCTION_STARTS:
        case LC_DATA_IN_CODE:
        case LC_DYLD_CHAINED_FIXUPS:
        case LC_DYLD_EXPORTS_TRIE:
        case LC_CODE_SIGNATURE: return sizeof(struct linkedit_data_command);
        case LC_BUILD_VERSION: return sizeof(struct build_version_command);
        case LC_SOURCE_VERSION: return sizeof(struct source_version_command);
        case LC_RPATH: return sizeof(struct rpath_command);
        case LC_SEGMENT: return sizeof(struct segment_command);
        case LC_SEGMENT_64: return sizeof(struct segment_command_64);
        case LC_VERSION_MIN_MACOSX:
        case LC_VERSION_MIN_IPHONEOS:
        case LC_VERSION_MIN_TVOS:
        case LC_VERSION_MIN_WATCHOS: return sizeof(struct version_min_command);
        default: return 8;
    }
}

bool macho_validate_load_commands(MachOContext *ctx) {
    if (!ctx) return false;

    if (ctx->header.ncmds > MAX_LOAD_COMMANDS) {
        char msg[MAX_WARNING_LENGTH];
        snprintf(msg, sizeof(msg), "Excessive load command count: %u (max %d)", ctx->header.ncmds, MAX_LOAD_COMMANDS);
        macho_add_warning(ctx, msg, 0, 2);
        return false;
    }

    if (ctx->header.sizeofcmds > (uint32_t)ctx->file_size) {
        char msg[MAX_WARNING_LENGTH];
        snprintf(msg, sizeof(msg), "sizeofcmds (%u) exceeds file size (%ld)", ctx->header.sizeofcmds, ctx->file_size);
        macho_add_warning(ctx, msg, 0, 2);
        return false;
    }

    return true;
}

#pragma mark - Embedded Mach-O Search

static uint64_t macho_find_embedded_macho(FILE *file, long file_size) {
    static const uint32_t macho_magics[] = {
        MH_MAGIC_64, MH_CIGAM_64, MH_MAGIC, MH_CIGAM,
        FAT_MAGIC, FAT_CIGAM, 0xcafebabf, 0xbfbafeca
    };
    static const int num_magics = 8;

    long scan_limit = (file_size < (16 * 1024 * 1024)) ? file_size : (16 * 1024 * 1024);
    uint32_t candidate;

    for (long off = 8; off + (long)sizeof(uint32_t) <= scan_limit; off += 4) {
        fseek(file, off, SEEK_SET);
        if (fread(&candidate, sizeof(uint32_t), 1, file) != 1) break;
        for (int i = 0; i < num_magics; i++) {
            if (candidate == macho_magics[i]) {
                return (uint64_t)off;
            }
        }
    }
    return UINT64_MAX;
}

#pragma mark - Context Management

MachOContext* macho_open(const char *filepath, char *error_msg) {
    MachOContext *ctx = (MachOContext*)calloc(1, sizeof(MachOContext));
    if (!ctx) {
        if (error_msg) strcpy(error_msg, "Memory allocation failed");
        return NULL;
    }
    
    ctx->file = fopen(filepath, "rb");
    if (!ctx->file) {
        if (error_msg) strcpy(error_msg, "Failed to open file - file may not exist or you don't have permission");
        free(ctx);
        return NULL;
    }
    
    fseek(ctx->file, 0, SEEK_END);
    ctx->file_size = ftell(ctx->file);
    fseek(ctx->file, 0, SEEK_SET);
    
    if (ctx->file_size <= 0) {
        if (error_msg) strcpy(error_msg, "File is empty");
        fclose(ctx->file);
        free(ctx);
        return NULL;
    }
    
    if (ctx->file_size < 4) {
        if (error_msg) strcpy(error_msg, "File too small to be a valid Mach-O binary");
        fclose(ctx->file);
        free(ctx);
        return NULL;
    }
    
    if (ctx->file_size > MAX_FILE_SIZE) {
        if (error_msg) snprintf(error_msg, 256, "File too large: %ld bytes (max: %d MB)", ctx->file_size, MAX_FILE_SIZE / (1024 * 1024));
        fclose(ctx->file);
        free(ctx);
        return NULL;
    }
    
    uint32_t magic;
    if (fread(&magic, sizeof(uint32_t), 1, ctx->file) != 1) {
        if (error_msg) strcpy(error_msg, "Failed to read magic number from file");
        fclose(ctx->file);
        free(ctx);
        return NULL;
    }
    fseek(ctx->file, 0, SEEK_SET);
    
    if (!macho_is_valid_magic(magic)) {
        if (magic == BPLIST_MAGIC_LE) {
            uint64_t embedded = macho_find_embedded_macho(ctx->file, ctx->file_size);
            if (embedded != UINT64_MAX) {
                ctx->base_offset = embedded;
                return ctx;
            }
            if (error_msg) {
                strcpy(error_msg, "File is a binary property list (system stub library).\n"
                                  "Stub libraries contain only export metadata and no executable code.\n"
                                  "To analyze the actual binary, extract it from the dyld shared cache.");
            }
        } else {
            if (error_msg) {
                snprintf(error_msg, 256, "Invalid magic number: 0x%08X (%s)\nExpected Mach-O or Universal Binary format",
                        magic, macho_magic_string(magic));
            }
        }
        fclose(ctx->file);
        free(ctx);
        return NULL;
    }
    
    return ctx;
}

void macho_close(MachOContext *ctx) {
    if (!ctx) return;
    
    if (ctx->file) fclose(ctx->file);
    if (ctx->load_commands) {
        for (uint32_t i = 0; i < ctx->load_command_count; i++) {
            if (ctx->load_commands[i].data) free(ctx->load_commands[i].data);
        }
        free(ctx->load_commands);
    }
    if (ctx->segments) free(ctx->segments);
    if (ctx->sections) free(ctx->sections);
    for (uint32_t i = 0; i < ctx->rpath_count; i++) {
        if (ctx->rpaths[i]) free(ctx->rpaths[i]);
    }

    free(ctx);
}

#pragma mark - Fat Binary Handling

bool macho_is_fat_binary(MachOContext *ctx) {
    uint32_t magic;
    fseek(ctx->file, (long)ctx->base_offset, SEEK_SET);
    if (fread(&magic, sizeof(uint32_t), 1, ctx->file) != 1) return false;
    return (magic == FAT_MAGIC || magic == FAT_CIGAM ||
            magic == 0xcafebabf || magic == 0xbfbafeca);
}

uint64_t macho_select_architecture(MachOContext *ctx) {
    if (!macho_is_fat_binary(ctx)) return ctx->base_offset;

    fseek(ctx->file, (long)ctx->base_offset, SEEK_SET);
    uint32_t magic;
    if (fread(&magic, sizeof(uint32_t), 1, ctx->file) != 1) return ctx->base_offset;
    fseek(ctx->file, (long)ctx->base_offset, SEEK_SET);

    struct fat_header fheader;
    if (fread(&fheader, sizeof(struct fat_header), 1, ctx->file) != 1) return ctx->base_offset;

    bool swap = (fheader.magic == FAT_CIGAM || fheader.magic == 0xbfbafeca);
    bool is_64 = (fheader.magic == 0xcafebabf || fheader.magic == 0xbfbafeca);
    uint32_t nfat_arch = swap ? swap_uint32(fheader.nfat_arch) : fheader.nfat_arch;

    if (nfat_arch > 20) return ctx->base_offset;
    uint64_t offset = ctx->base_offset;
    uint64_t arm64_offset = 0, arm64e_offset = 0, x86_64_offset = 0, arm_offset = 0, i386_offset = 0;

    if (is_64) {
        struct fat_arch_64 {
            uint32_t cputype;
            uint32_t cpusubtype;
            uint64_t offset;
            uint64_t size;
            uint32_t align;
            uint32_t reserved;
        } *archs_64 = malloc(sizeof(struct fat_arch_64) * nfat_arch);

        if (!archs_64) return ctx->base_offset;
        if (fread(archs_64, sizeof(struct fat_arch_64), nfat_arch, ctx->file) != nfat_arch) {
            free(archs_64);
            return ctx->base_offset;
        }

        for (uint32_t i = 0; i < nfat_arch; i++) {
            uint32_t cputype = swap ? swap_uint32(archs_64[i].cputype) : archs_64[i].cputype;
            uint32_t cpusubtype = swap ? swap_uint32(archs_64[i].cpusubtype) : archs_64[i].cpusubtype;
            uint64_t arch_offset = ctx->base_offset +
                (swap ? swap_uint64(archs_64[i].offset) : archs_64[i].offset);

            cpusubtype &= ~CPU_SUBTYPE_MASK;

            if (cputype == CPU_TYPE_ARM64) {
                if (cpusubtype == 2) {
                    arm64e_offset = arch_offset;
                } else if (arm64_offset == 0) {
                    arm64_offset = arch_offset;
                }
            } else if (cputype == CPU_TYPE_X86_64 && x86_64_offset == 0) {
                x86_64_offset = arch_offset;
            } else if (cputype == CPU_TYPE_ARM && arm_offset == 0) {
                arm_offset = arch_offset;
            } else if (cputype == CPU_TYPE_X86 && i386_offset == 0) {
                i386_offset = arch_offset;
            }
        }
        free(archs_64);
    } else {
        struct fat_arch *archs = malloc(sizeof(struct fat_arch) * nfat_arch);
        if (!archs) return ctx->base_offset;

        if (fread(archs, sizeof(struct fat_arch), nfat_arch, ctx->file) != nfat_arch) {
            free(archs);
            return ctx->base_offset;
        }

        for (uint32_t i = 0; i < nfat_arch; i++) {
            uint32_t cputype = swap ? swap_uint32(archs[i].cputype) : archs[i].cputype;
            uint32_t cpusubtype = swap ? swap_uint32(archs[i].cpusubtype) : archs[i].cpusubtype;
            uint64_t arch_offset = ctx->base_offset +
                (uint64_t)(swap ? swap_uint32(archs[i].offset) : archs[i].offset);

            cpusubtype &= ~CPU_SUBTYPE_MASK;

            if (cputype == CPU_TYPE_ARM64) {
                if (cpusubtype == 2) {
                    arm64e_offset = arch_offset;
                } else if (arm64_offset == 0) {
                    arm64_offset = arch_offset;
                }
            } else if (cputype == CPU_TYPE_X86_64 && x86_64_offset == 0) {
                x86_64_offset = arch_offset;
            } else if (cputype == CPU_TYPE_ARM && arm_offset == 0) {
                arm_offset = arch_offset;
            } else if (cputype == CPU_TYPE_X86 && i386_offset == 0) {
                i386_offset = arch_offset;
            }
        }
        free(archs);
    }
    
    if (arm64e_offset > 0) {
        offset = arm64e_offset;
    } else if (arm64_offset > 0) {
        offset = arm64_offset;
    } else if (x86_64_offset > 0) {
        offset = x86_64_offset;
    } else if (arm_offset > 0) {
        offset = arm_offset;
    } else if (i386_offset > 0) {
        offset = i386_offset;
    }
    
    return offset;
}

#pragma mark - Header Parsing

bool macho_parse_header(MachOContext *ctx) {
    if (!ctx || !ctx->file) return false;
    
    uint64_t arch_offset = macho_select_architecture(ctx);
    fseek(ctx->file, arch_offset, SEEK_SET);
    
    if (fread(&ctx->header.magic, sizeof(uint32_t), 1, ctx->file) != 1) return false;
    fseek(ctx->file, arch_offset, SEEK_SET);
    
    if (!macho_is_valid_magic(ctx->header.magic)) return false;
    
    ctx->header.is_swapped = (ctx->header.magic == MH_CIGAM_64 || ctx->header.magic == MH_CIGAM);
    ctx->header.is_64bit = (ctx->header.magic == MH_MAGIC_64 || ctx->header.magic == MH_CIGAM_64);
    
    if (ctx->header.is_64bit) {
        struct mach_header_64 header;
        if (fread(&header, sizeof(struct mach_header_64), 1, ctx->file) != 1) return false;
        
        if (ctx->header.is_swapped) {
            ctx->header.cputype = swap_uint32(header.cputype);
            ctx->header.cpusubtype = swap_uint32(header.cpusubtype);
            ctx->header.filetype = swap_uint32(header.filetype);
            ctx->header.ncmds = swap_uint32(header.ncmds);
            ctx->header.sizeofcmds = swap_uint32(header.sizeofcmds);
            ctx->header.flags = swap_uint32(header.flags);
            ctx->header.reserved = swap_uint32(header.reserved);
        } else {
            ctx->header.cputype = header.cputype;
            ctx->header.cpusubtype = header.cpusubtype;
            ctx->header.filetype = header.filetype;
            ctx->header.ncmds = header.ncmds;
            ctx->header.sizeofcmds = header.sizeofcmds;
            ctx->header.flags = header.flags;
            ctx->header.reserved = header.reserved;
        }
    } else {
        struct mach_header header;
        if (fread(&header, sizeof(struct mach_header), 1, ctx->file) != 1) return false;
        
        if (ctx->header.is_swapped) {
            ctx->header.cputype = swap_uint32(header.cputype);
            ctx->header.cpusubtype = swap_uint32(header.cpusubtype);
            ctx->header.filetype = swap_uint32(header.filetype);
            ctx->header.ncmds = swap_uint32(header.ncmds);
            ctx->header.sizeofcmds = swap_uint32(header.sizeofcmds);
            ctx->header.flags = swap_uint32(header.flags);
        } else {
            ctx->header.cputype = header.cputype;
            ctx->header.cpusubtype = header.cpusubtype;
            ctx->header.filetype = header.filetype;
            ctx->header.ncmds = header.ncmds;
            ctx->header.sizeofcmds = header.sizeofcmds;
            ctx->header.flags = header.flags;
        }
        ctx->header.reserved = 0;
    }
    
    return true;
}

#pragma mark - Load Command Parsing

bool macho_parse_load_commands(MachOContext *ctx) {
    if (!ctx || !ctx->file || ctx->header.ncmds == 0) return false;

    // Validate load command counts before allocating
    if (!macho_validate_load_commands(ctx)) return false;

    // Extract security flags from header
    ctx->is_pie = (ctx->header.flags & MH_PIE) != 0;
    ctx->allows_stack_execution = (ctx->header.flags & MH_ALLOW_STACK_EXECUTION) != 0;
    ctx->no_heap_execution = (ctx->header.flags & MH_NO_HEAP_EXECUTION) != 0;

    ctx->load_command_count = ctx->header.ncmds;
    ctx->load_commands = calloc(ctx->load_command_count, sizeof(LoadCommandInfo));
    if (!ctx->load_commands) return false;

    uint32_t sizeofcmds_remaining = ctx->header.sizeofcmds;

    for (uint32_t i = 0; i < ctx->header.ncmds; i++) {
        struct load_command lc;
        long cmd_offset = ftell(ctx->file);

        if (fread(&lc, sizeof(struct load_command), 1, ctx->file) != 1) return false;

        if (ctx->header.is_swapped) {
            lc.cmd = swap_uint32(lc.cmd);
            lc.cmdsize = swap_uint32(lc.cmdsize);
        }

        // Validate cmdsize
        if (lc.cmdsize < 8) {
            char msg[MAX_WARNING_LENGTH];
            snprintf(msg, sizeof(msg), "Load command %u has invalid cmdsize %u (min 8)", i, lc.cmdsize);
            macho_add_warning(ctx, msg, (uint32_t)cmd_offset, 2);
            return false;
        }

        if (lc.cmdsize > sizeofcmds_remaining) {
            char msg[MAX_WARNING_LENGTH];
            snprintf(msg, sizeof(msg), "Load command %u cmdsize %u exceeds remaining sizeofcmds %u", i, lc.cmdsize, sizeofcmds_remaining);
            macho_add_warning(ctx, msg, (uint32_t)cmd_offset, 2);
            return false;
        }

        // Bounds check against file size
        if ((uint64_t)cmd_offset + lc.cmdsize > (uint64_t)ctx->file_size) {
            char msg[MAX_WARNING_LENGTH];
            snprintf(msg, sizeof(msg), "Load command %u extends beyond file (offset %ld + size %u > %ld)", i, cmd_offset, lc.cmdsize, ctx->file_size);
            macho_add_warning(ctx, msg, (uint32_t)cmd_offset, 2);
            return false;
        }

        sizeofcmds_remaining -= lc.cmdsize;

        ctx->load_commands[i].cmd = lc.cmd;
        ctx->load_commands[i].cmdsize = lc.cmdsize;
        ctx->load_commands[i].data = malloc(lc.cmdsize);
        if (!ctx->load_commands[i].data) return false;

        fseek(ctx->file, cmd_offset, SEEK_SET);
        if (fread(ctx->load_commands[i].data, lc.cmdsize, 1, ctx->file) != 1) return false;

        // The payload is cast to a fixed-size struct below, so reject truncated commands
        if (lc.cmdsize < macho_min_cmdsize(lc.cmd)) {
            char msg[MAX_WARNING_LENGTH];
            snprintf(msg, sizeof(msg), "Load command %u (0x%X) cmdsize %u is smaller than its structure (%u)",
                     i, lc.cmd, lc.cmdsize, macho_min_cmdsize(lc.cmd));
            macho_add_warning(ctx, msg, (uint32_t)cmd_offset, 2);
            ctx->load_commands[i].cmd = 0;
            continue;
        }

        switch (lc.cmd) {
            case LC_SYMTAB: {
                struct symtab_command *symtab = (struct symtab_command*)ctx->load_commands[i].data;
                ctx->symtab_offset = (ctx->header.is_swapped ? swap_uint32(symtab->symoff) : symtab->symoff)
                                     + ctx->base_offset;
                ctx->nsyms = ctx->header.is_swapped ? swap_uint32(symtab->nsyms) : symtab->nsyms;
                ctx->stroff = (ctx->header.is_swapped ? swap_uint32(symtab->stroff) : symtab->stroff)
                              + ctx->base_offset;
                ctx->strsize = ctx->header.is_swapped ? swap_uint32(symtab->strsize) : symtab->strsize;
                break;
            }
            case LC_DYSYMTAB: {
                ctx->dysymtab_offset = (uint64_t)cmd_offset;
                break;
            }
            case LC_DYLD_INFO:
            case LC_DYLD_INFO_ONLY: {
                struct dyld_info_command *dyld = (struct dyld_info_command*)ctx->load_commands[i].data;
                ctx->has_dyld_info = true;
                ctx->rebase_off = (ctx->header.is_swapped ? swap_uint32(dyld->rebase_off) : dyld->rebase_off)
                                  + ctx->base_offset;
                ctx->rebase_size = ctx->header.is_swapped ? swap_uint32(dyld->rebase_size) : dyld->rebase_size;
                ctx->bind_off = (ctx->header.is_swapped ? swap_uint32(dyld->bind_off) : dyld->bind_off)
                                + ctx->base_offset;
                ctx->bind_size = ctx->header.is_swapped ? swap_uint32(dyld->bind_size) : dyld->bind_size;
                ctx->weak_bind_off = (ctx->header.is_swapped ? swap_uint32(dyld->weak_bind_off) : dyld->weak_bind_off)
                                     + ctx->base_offset;
                ctx->weak_bind_size = ctx->header.is_swapped ? swap_uint32(dyld->weak_bind_size) : dyld->weak_bind_size;
                ctx->lazy_bind_off = (ctx->header.is_swapped ? swap_uint32(dyld->lazy_bind_off) : dyld->lazy_bind_off)
                                     + ctx->base_offset;
                ctx->lazy_bind_size = ctx->header.is_swapped ? swap_uint32(dyld->lazy_bind_size) : dyld->lazy_bind_size;
                ctx->export_off = (ctx->header.is_swapped ? swap_uint32(dyld->export_off) : dyld->export_off)
                                  + ctx->base_offset;
                ctx->export_size = ctx->header.is_swapped ? swap_uint32(dyld->export_size) : dyld->export_size;
                break;
            }
            case LC_ENCRYPTION_INFO:
            case LC_ENCRYPTION_INFO_64: {
                struct encryption_info_command *enc = (struct encryption_info_command*)ctx->load_commands[i].data;
                ctx->cryptid = ctx->header.is_swapped ? swap_uint32(enc->cryptid) : enc->cryptid;
                ctx->is_encrypted = (ctx->cryptid != 0);
                ctx->cryptoff = (ctx->header.is_swapped ? swap_uint32(enc->cryptoff) : enc->cryptoff)
                                + ctx->base_offset;
                ctx->cryptsize = ctx->header.is_swapped ? swap_uint32(enc->cryptsize) : enc->cryptsize;
                break;
            }
            case LC_UUID: {
                struct uuid_command *uuid = (struct uuid_command*)ctx->load_commands[i].data;
                memcpy(ctx->uuid, uuid->uuid, 16);
                ctx->has_uuid = true;
                break;
            }
            case LC_MAIN: {
                struct entry_point_command *ep = (struct entry_point_command*)ctx->load_commands[i].data;
                ctx->has_entry_point = true;
                ctx->entry_point_offset = ctx->header.is_swapped ? swap_uint64(ep->entryoff) : ep->entryoff;
                break;
            }
            case LC_FUNCTION_STARTS: {
                struct linkedit_data_command *ldc = (struct linkedit_data_command*)ctx->load_commands[i].data;
                ctx->has_function_starts = true;
                ctx->function_starts_offset = (ctx->header.is_swapped ? swap_uint32(ldc->dataoff) : ldc->dataoff)
                                              + ctx->base_offset;
                ctx->function_starts_size = ctx->header.is_swapped ? swap_uint32(ldc->datasize) : ldc->datasize;
                break;
            }
            case LC_DATA_IN_CODE: {
                struct linkedit_data_command *ldc = (struct linkedit_data_command*)ctx->load_commands[i].data;
                ctx->has_data_in_code = true;
                ctx->data_in_code_offset = (ctx->header.is_swapped ? swap_uint32(ldc->dataoff) : ldc->dataoff)
                                           + ctx->base_offset;
                ctx->data_in_code_size = ctx->header.is_swapped ? swap_uint32(ldc->datasize) : ldc->datasize;
                break;
            }
            case LC_DYLD_CHAINED_FIXUPS: {
                struct linkedit_data_command *ldc = (struct linkedit_data_command*)ctx->load_commands[i].data;
                ctx->has_chained_fixups = true;
                ctx->chained_fixups_offset = (ctx->header.is_swapped ? swap_uint32(ldc->dataoff) : ldc->dataoff)
                                             + ctx->base_offset;
                ctx->chained_fixups_size = ctx->header.is_swapped ? swap_uint32(ldc->datasize) : ldc->datasize;
                break;
            }
            case LC_DYLD_EXPORTS_TRIE: {
                struct linkedit_data_command *ldc = (struct linkedit_data_command*)ctx->load_commands[i].data;
                ctx->has_exports_trie = true;
                ctx->exports_trie_offset = (ctx->header.is_swapped ? swap_uint32(ldc->dataoff) : ldc->dataoff)
                                           + ctx->base_offset;
                ctx->exports_trie_size = ctx->header.is_swapped ? swap_uint32(ldc->datasize) : ldc->datasize;
                break;
            }
            case LC_BUILD_VERSION: {
                struct build_version_command *bv = (struct build_version_command*)ctx->load_commands[i].data;
                ctx->platform = ctx->header.is_swapped ? swap_uint32(bv->platform) : bv->platform;
                ctx->minos = ctx->header.is_swapped ? swap_uint32(bv->minos) : bv->minos;
                ctx->sdk = ctx->header.is_swapped ? swap_uint32(bv->sdk) : bv->sdk;
                ctx->build_tool_count = ctx->header.is_swapped ? swap_uint32(bv->ntools) : bv->ntools;
                break;
            }
            case LC_SOURCE_VERSION: {
                struct source_version_command *sv = (struct source_version_command*)ctx->load_commands[i].data;
                ctx->source_version = ctx->header.is_swapped ? swap_uint64(sv->version) : sv->version;
                ctx->has_source_version = true;
                break;
            }
            case LC_RPATH: {
                struct rpath_command *rp = (struct rpath_command*)ctx->load_commands[i].data;
                uint32_t path_offset = ctx->header.is_swapped ? swap_uint32(rp->path.offset) : rp->path.offset;
                if (path_offset < lc.cmdsize && ctx->rpath_count < MAX_RPATHS) {
                    const char *path_str = (const char*)rp + path_offset;
                    size_t max_len = lc.cmdsize - path_offset;
                    size_t path_len = strnlen(path_str, max_len);
                    ctx->rpaths[ctx->rpath_count] = malloc(path_len + 1);
                    if (ctx->rpaths[ctx->rpath_count]) {
                        memcpy(ctx->rpaths[ctx->rpath_count], path_str, path_len);
                        ctx->rpaths[ctx->rpath_count][path_len] = '\0';
                        ctx->rpath_count++;
                    }
                }
                break;
            }
            case LC_LOAD_DYLIB:
            case LC_LOAD_WEAK_DYLIB:
            case LC_LAZY_LOAD_DYLIB:
            case LC_REEXPORT_DYLIB:
                // Tracked via load_commands array; no extra extraction needed
                break;
            case LC_LINKER_OPTION: {
                ctx->linker_option_count++;
                break;
            }
            case LC_VERSION_MIN_MACOSX:
            case LC_VERSION_MIN_IPHONEOS:
            case LC_VERSION_MIN_TVOS:
            case LC_VERSION_MIN_WATCHOS: {
                // Fallback platform info for older binaries without LC_BUILD_VERSION
                if (ctx->platform == 0) {
                    struct version_min_command *vm = (struct version_min_command*)ctx->load_commands[i].data;
                    ctx->min_version = ctx->header.is_swapped ? swap_uint32(vm->version) : vm->version;
                    ctx->sdk_version = ctx->header.is_swapped ? swap_uint32(vm->sdk) : vm->sdk;
                    switch (lc.cmd) {
                        case LC_VERSION_MIN_MACOSX:    ctx->platform = PLATFORM_MACOS;   break;
                        case LC_VERSION_MIN_IPHONEOS:  ctx->platform = PLATFORM_IOS;     break;
                        case LC_VERSION_MIN_TVOS:      ctx->platform = PLATFORM_TVOS;    break;
                        case LC_VERSION_MIN_WATCHOS:   ctx->platform = PLATFORM_WATCHOS; break;
                        default: break;
                    }
                    ctx->minos = ctx->min_version;
                    ctx->sdk = ctx->sdk_version;
                }
                break;
            }
            case LC_SEGMENT:
            case LC_SEGMENT_64:
            case LC_CODE_SIGNATURE:
            case LC_SEGMENT_SPLIT_INFO:
            case LC_ID_DYLIB:
            case LC_LOAD_DYLINKER:
            case LC_ID_DYLINKER:
            case LC_PREBOUND_DYLIB:
            case LC_ROUTINES:
            case LC_ROUTINES_64:
            case LC_SUB_FRAMEWORK:
            case LC_SUB_UMBRELLA:
            case LC_SUB_CLIENT:
            case LC_SUB_LIBRARY:
            case LC_TWOLEVEL_HINTS:
            case LC_PREBIND_CKSUM:
                break;
            case LC_DYLD_ENVIRONMENT:
            case LC_THREAD:
            case LC_UNIXTHREAD:
            case LC_LOAD_UPWARD_DYLIB:
            case LC_DYLIB_CODE_SIGN_DRS:
            case LC_LINKER_OPTIMIZATION_HINT:
            case LC_NOTE:
            case LC_FILESET_ENTRY:
                // Known commands handled elsewhere or no extra data needed
                break;
            default: {
                char msg[MAX_WARNING_LENGTH];
                snprintf(msg, sizeof(msg), "Unrecognized load command 0x%X (%s) at offset %ld",
                         lc.cmd, macho_load_command_name(lc.cmd), cmd_offset);
                macho_add_warning(ctx, msg, (uint32_t)cmd_offset, 1);
                break;
            }
        }
    }

    return true;
}

#pragma mark - Segment & Section Extraction

uint32_t macho_extract_segments(MachOContext *ctx) {
    if (!ctx || !ctx->load_commands) return 0;

    uint32_t seg_count = 0;
    for (uint32_t i = 0; i < ctx->load_command_count; i++) {
        if (ctx->load_commands[i].cmd == LC_SEGMENT_64 || ctx->load_commands[i].cmd == LC_SEGMENT) {
            seg_count++;
        }
    }

    if (seg_count == 0) return 0;

    // Validate segment count
    if (seg_count > MAX_SEGMENTS) {
        char msg[MAX_WARNING_LENGTH];
        snprintf(msg, sizeof(msg), "Excessive segment count: %u (max %d)", seg_count, MAX_SEGMENTS);
        macho_add_warning(ctx, msg, 0, 2);
        seg_count = MAX_SEGMENTS;
    }

    ctx->segments = calloc(seg_count, sizeof(SegmentInfo));
    if (!ctx->segments) return 0;

    ctx->segment_count = 0;
    for (uint32_t i = 0; i < ctx->load_command_count && ctx->segment_count < seg_count; i++) {
        if (ctx->load_commands[i].cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64*)ctx->load_commands[i].data;
            SegmentInfo *info = &ctx->segments[ctx->segment_count++];

            strncpy(info->segname, seg->segname, 16);
            info->segname[16] = '\0';
            info->vmaddr = ctx->header.is_swapped ? swap_uint64(seg->vmaddr) : seg->vmaddr;
            info->vmsize = ctx->header.is_swapped ? swap_uint64(seg->vmsize) : seg->vmsize;
            info->fileoff = (ctx->header.is_swapped ? swap_uint64(seg->fileoff) : seg->fileoff)
                            + ctx->base_offset;
            info->filesize = ctx->header.is_swapped ? swap_uint64(seg->filesize) : seg->filesize;
            info->maxprot = ctx->header.is_swapped ? swap_uint32(seg->maxprot) : seg->maxprot;
            info->initprot = ctx->header.is_swapped ? swap_uint32(seg->initprot) : seg->initprot;
            info->nsects = ctx->header.is_swapped ? swap_uint32(seg->nsects) : seg->nsects;
            info->flags = ctx->header.is_swapped ? swap_uint32(seg->flags) : seg->flags;

            // Validate fileoff + filesize against file size
            if (info->filesize > 0 && (info->fileoff + info->filesize > (uint64_t)ctx->file_size)) {
                char msg[MAX_WARNING_LENGTH];
                snprintf(msg, sizeof(msg), "Segment %.16s file range [0x%llx, 0x%llx) exceeds file size %ld",
                         info->segname, info->fileoff, info->fileoff + info->filesize, ctx->file_size);
                macho_add_warning(ctx, msg, (uint32_t)info->fileoff, 1);
            }

            // Warn on RWX segments (initprot has read, write, and execute)
            if ((info->initprot & 0x7) == 0x7) {
                char msg[MAX_WARNING_LENGTH];
                snprintf(msg, sizeof(msg), "Segment %.16s has RWX permissions (initprot=0x%x)", info->segname, info->initprot);
                macho_add_warning(ctx, msg, 0, 1);
            }

            // Check for __RESTRICT segment
            if (strncmp(info->segname, "__RESTRICT", 16) == 0) {
                ctx->has_restrict_segment = true;
            }
        } else if (ctx->load_commands[i].cmd == LC_SEGMENT) {
            struct segment_command *seg = (struct segment_command*)ctx->load_commands[i].data;
            SegmentInfo *info = &ctx->segments[ctx->segment_count++];

            strncpy(info->segname, seg->segname, 16);
            info->segname[16] = '\0';
            info->vmaddr = ctx->header.is_swapped ? swap_uint32(seg->vmaddr) : seg->vmaddr;
            info->vmsize = ctx->header.is_swapped ? swap_uint32(seg->vmsize) : seg->vmsize;
            info->fileoff = (uint64_t)(ctx->header.is_swapped ? swap_uint32(seg->fileoff) : seg->fileoff)
                            + ctx->base_offset;
            info->filesize = ctx->header.is_swapped ? swap_uint32(seg->filesize) : seg->filesize;
            info->maxprot = ctx->header.is_swapped ? swap_uint32(seg->maxprot) : seg->maxprot;
            info->initprot = ctx->header.is_swapped ? swap_uint32(seg->initprot) : seg->initprot;
            info->nsects = ctx->header.is_swapped ? swap_uint32(seg->nsects) : seg->nsects;
            info->flags = ctx->header.is_swapped ? swap_uint32(seg->flags) : seg->flags;

            // Validate fileoff + filesize against file size
            if (info->filesize > 0 && (info->fileoff + info->filesize > (uint64_t)ctx->file_size)) {
                char msg[MAX_WARNING_LENGTH];
                snprintf(msg, sizeof(msg), "Segment %.16s file range [0x%llx, 0x%llx) exceeds file size %ld",
                         info->segname, info->fileoff, info->fileoff + info->filesize, ctx->file_size);
                macho_add_warning(ctx, msg, (uint32_t)info->fileoff, 1);
            }

            // Warn on RWX segments
            if ((info->initprot & 0x7) == 0x7) {
                char msg[MAX_WARNING_LENGTH];
                snprintf(msg, sizeof(msg), "Segment %.16s has RWX permissions (initprot=0x%x)", info->segname, info->initprot);
                macho_add_warning(ctx, msg, 0, 1);
            }

            // Check for __RESTRICT segment
            if (strncmp(info->segname, "__RESTRICT", 16) == 0) {
                ctx->has_restrict_segment = true;
            }
        }
    }

    return ctx->segment_count;
}

uint32_t macho_extract_sections(MachOContext *ctx) {
    if (!ctx || !ctx->load_commands) return 0;

    uint32_t sect_count = 0;
    for (uint32_t i = 0; i < ctx->segment_count; i++) {
        sect_count += ctx->segments[i].nsects;
    }

    if (sect_count == 0) return 0;

    // Validate section count
    if (sect_count > MAX_SECTIONS) {
        char msg[MAX_WARNING_LENGTH];
        snprintf(msg, sizeof(msg), "Excessive section count: %u (max %d)", sect_count, MAX_SECTIONS);
        macho_add_warning(ctx, msg, 0, 2);
        sect_count = MAX_SECTIONS;
    }

    ctx->sections = calloc(sect_count, sizeof(SectionInfo));
    if (!ctx->sections) return 0;

    ctx->section_count = 0;

    // Build a segment index to look up parent segment info for validation
    uint32_t seg_idx = 0;

    for (uint32_t i = 0; i < ctx->load_command_count && ctx->section_count < sect_count; i++) {
        if (ctx->load_commands[i].cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64*)ctx->load_commands[i].data;
            uint32_t nsects = ctx->header.is_swapped ? swap_uint32(seg->nsects) : seg->nsects;
            struct section_64 *sections = (struct section_64*)((char*)seg + sizeof(struct segment_command_64));
            uint32_t max_sects = (ctx->load_commands[i].cmdsize - (uint32_t)sizeof(struct segment_command_64)) / (uint32_t)sizeof(struct section_64);
            if (nsects > max_sects) {
                macho_add_warning(ctx, "Segment nsects exceeds load command size; clamping", 0, 1);
                nsects = max_sects;
            }

            // Find matching parent segment for bounds checking
            uint64_t seg_fileoff = 0, seg_filesize = 0;
            if (seg_idx < ctx->segment_count) {
                seg_fileoff = ctx->segments[seg_idx].fileoff;
                seg_filesize = ctx->segments[seg_idx].filesize;
            }

            for (uint32_t j = 0; j < nsects && ctx->section_count < sect_count; j++) {
                SectionInfo *info = &ctx->sections[ctx->section_count++];
                strncpy(info->sectname, sections[j].sectname, 16);
                info->sectname[16] = '\0';
                strncpy(info->segname, sections[j].segname, 16);
                info->segname[16] = '\0';
                info->addr = ctx->header.is_swapped ? swap_uint64(sections[j].addr) : sections[j].addr;
                info->size = ctx->header.is_swapped ? swap_uint64(sections[j].size) : sections[j].size;
                info->offset = (ctx->header.is_swapped ? swap_uint32(sections[j].offset) : sections[j].offset)
                               + ctx->base_offset;
                info->align = ctx->header.is_swapped ? swap_uint32(sections[j].align) : sections[j].align;
                info->flags = ctx->header.is_swapped ? swap_uint32(sections[j].flags) : sections[j].flags;

                // Validate section offset falls within parent segment bounds
                if (info->offset > 0 && seg_filesize > 0) {
                    if (info->offset < seg_fileoff || info->offset >= seg_fileoff + seg_filesize) {
                        char msg[MAX_WARNING_LENGTH];
                        snprintf(msg, sizeof(msg), "Section %.16s,%.16s offset 0x%x outside parent segment [0x%llx, 0x%llx)",
                                 info->segname, info->sectname, info->offset, seg_fileoff, seg_fileoff + seg_filesize);
                        macho_add_warning(ctx, msg, info->offset, 1);
                    }
                }
            }
            seg_idx++;
        } else if (ctx->load_commands[i].cmd == LC_SEGMENT) {
            struct segment_command *seg = (struct segment_command*)ctx->load_commands[i].data;
            uint32_t nsects = ctx->header.is_swapped ? swap_uint32(seg->nsects) : seg->nsects;
            struct section *sections = (struct section*)((char*)seg + sizeof(struct segment_command));
            uint32_t max_sects = (ctx->load_commands[i].cmdsize - (uint32_t)sizeof(struct segment_command)) / (uint32_t)sizeof(struct section);
            if (nsects > max_sects) {
                macho_add_warning(ctx, "Segment nsects exceeds load command size; clamping", 0, 1);
                nsects = max_sects;
            }

            uint64_t seg_fileoff = 0, seg_filesize = 0;
            if (seg_idx < ctx->segment_count) {
                seg_fileoff = ctx->segments[seg_idx].fileoff;
                seg_filesize = ctx->segments[seg_idx].filesize;
            }

            for (uint32_t j = 0; j < nsects && ctx->section_count < sect_count; j++) {
                SectionInfo *info = &ctx->sections[ctx->section_count++];
                strncpy(info->sectname, sections[j].sectname, 16);
                info->sectname[16] = '\0';
                strncpy(info->segname, sections[j].segname, 16);
                info->segname[16] = '\0';
                info->addr = ctx->header.is_swapped ? swap_uint32(sections[j].addr) : sections[j].addr;
                info->size = ctx->header.is_swapped ? swap_uint32(sections[j].size) : sections[j].size;
                info->offset = (ctx->header.is_swapped ? swap_uint32(sections[j].offset) : sections[j].offset)
                               + ctx->base_offset;
                info->align = ctx->header.is_swapped ? swap_uint32(sections[j].align) : sections[j].align;
                info->flags = ctx->header.is_swapped ? swap_uint32(sections[j].flags) : sections[j].flags;

                // Validate section offset falls within parent segment bounds
                if (info->offset > 0 && seg_filesize > 0) {
                    if (info->offset < seg_fileoff || info->offset >= seg_fileoff + seg_filesize) {
                        char msg[MAX_WARNING_LENGTH];
                        snprintf(msg, sizeof(msg), "Section %.16s,%.16s offset 0x%x outside parent segment [0x%llx, 0x%llx)",
                                 info->segname, info->sectname, info->offset, seg_fileoff, seg_fileoff + seg_filesize);
                        macho_add_warning(ctx, msg, info->offset, 1);
                    }
                }
            }
            seg_idx++;
        }
    }

    return ctx->section_count;
}

