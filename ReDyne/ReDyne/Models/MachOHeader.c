#include "MachOHeader.h"
#include <stdlib.h>
#include <string.h>
#include <mach/machine.h>

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
        if (error_msg) sprintf(error_msg, "File too large: %ld bytes (max: %d MB)", ctx->file_size, MAX_FILE_SIZE / (1024 * 1024));
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
        if (error_msg) {
            sprintf(error_msg, "Invalid magic number: 0x%08X (%s)\nExpected Mach-O or Universal Binary format", 
                    magic, macho_magic_string(magic));
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
    
    free(ctx);
}

#pragma mark - Fat Binary Handling

bool macho_is_fat_binary(MachOContext *ctx) {
    uint32_t magic;
    fseek(ctx->file, 0, SEEK_SET);
    if (fread(&magic, sizeof(uint32_t), 1, ctx->file) != 1) return false;
    return (magic == FAT_MAGIC || magic == FAT_CIGAM || 
            magic == 0xcafebabf || magic == 0xbfbafeca);
}

uint64_t macho_select_architecture(MachOContext *ctx) {
    if (!macho_is_fat_binary(ctx)) return 0;
    
    fseek(ctx->file, 0, SEEK_SET);
    uint32_t magic;
    if (fread(&magic, sizeof(uint32_t), 1, ctx->file) != 1) return 0;
    fseek(ctx->file, 0, SEEK_SET);
    
    struct fat_header fheader;
    if (fread(&fheader, sizeof(struct fat_header), 1, ctx->file) != 1) return 0;
    
    bool swap = (fheader.magic == FAT_CIGAM || fheader.magic == 0xbfbafeca);
    bool is_64 = (fheader.magic == 0xcafebabf || fheader.magic == 0xbfbafeca);
    uint32_t nfat_arch = swap ? swap_uint32(fheader.nfat_arch) : fheader.nfat_arch;
    
    if (nfat_arch > 20) return 0;
    
    uint64_t offset = 0;
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
        
        if (!archs_64) return 0;
        if (fread(archs_64, sizeof(struct fat_arch_64), nfat_arch, ctx->file) != nfat_arch) {
            free(archs_64);
            return 0;
        }
        
        for (uint32_t i = 0; i < nfat_arch; i++) {
            uint32_t cputype = swap ? swap_uint32(archs_64[i].cputype) : archs_64[i].cputype;
            uint32_t cpusubtype = swap ? swap_uint32(archs_64[i].cpusubtype) : archs_64[i].cpusubtype;
            uint64_t arch_offset = swap ? swap_uint64(archs_64[i].offset) : archs_64[i].offset;
            
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
        if (!archs) return 0;
        
        if (fread(archs, sizeof(struct fat_arch), nfat_arch, ctx->file) != nfat_arch) {
            free(archs);
            return 0;
        }
        
        for (uint32_t i = 0; i < nfat_arch; i++) {
            uint32_t cputype = swap ? swap_uint32(archs[i].cputype) : archs[i].cputype;
            uint32_t cpusubtype = swap ? swap_uint32(archs[i].cpusubtype) : archs[i].cpusubtype;
            uint32_t arch_offset = swap ? swap_uint32(archs[i].offset) : archs[i].offset;
            
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
    
    ctx->load_command_count = ctx->header.ncmds;
    ctx->load_commands = calloc(ctx->load_command_count, sizeof(LoadCommandInfo));
    if (!ctx->load_commands) return false;
    
    for (uint32_t i = 0; i < ctx->header.ncmds; i++) {
        struct load_command lc;
        long cmd_offset = ftell(ctx->file);
        
        if (fread(&lc, sizeof(struct load_command), 1, ctx->file) != 1) return false;
        
        if (ctx->header.is_swapped) {
            lc.cmd = swap_uint32(lc.cmd);
            lc.cmdsize = swap_uint32(lc.cmdsize);
        }
        
        ctx->load_commands[i].cmd = lc.cmd;
        ctx->load_commands[i].cmdsize = lc.cmdsize;
        ctx->load_commands[i].data = malloc(lc.cmdsize);
        if (!ctx->load_commands[i].data) return false;
        
        fseek(ctx->file, cmd_offset, SEEK_SET);
        if (fread(ctx->load_commands[i].data, lc.cmdsize, 1, ctx->file) != 1) return false;
        
        switch (lc.cmd) {
            case LC_SYMTAB: {
                struct symtab_command *symtab = (struct symtab_command*)ctx->load_commands[i].data;
                ctx->symtab_offset = ctx->header.is_swapped ? swap_uint32(symtab->symoff) : symtab->symoff;
                ctx->nsyms = ctx->header.is_swapped ? swap_uint32(symtab->nsyms) : symtab->nsyms;
                ctx->stroff = ctx->header.is_swapped ? swap_uint32(symtab->stroff) : symtab->stroff;
                ctx->strsize = ctx->header.is_swapped ? swap_uint32(symtab->strsize) : symtab->strsize;
                break;
            }
            case LC_DYSYMTAB: {
                struct dysymtab_command *dysym = (struct dysymtab_command*)ctx->load_commands[i].data;
                ctx->dysymtab_offset = ftell(ctx->file);
                break;
            }
            case LC_DYLD_INFO:
            case LC_DYLD_INFO_ONLY: {
                struct dyld_info_command *dyld = (struct dyld_info_command*)ctx->load_commands[i].data;
                ctx->has_dyld_info = true;
                ctx->rebase_off = ctx->header.is_swapped ? swap_uint32(dyld->rebase_off) : dyld->rebase_off;
                ctx->rebase_size = ctx->header.is_swapped ? swap_uint32(dyld->rebase_size) : dyld->rebase_size;
                ctx->bind_off = ctx->header.is_swapped ? swap_uint32(dyld->bind_off) : dyld->bind_off;
                ctx->bind_size = ctx->header.is_swapped ? swap_uint32(dyld->bind_size) : dyld->bind_size;
                ctx->export_off = ctx->header.is_swapped ? swap_uint32(dyld->export_off) : dyld->export_off;
                ctx->export_size = ctx->header.is_swapped ? swap_uint32(dyld->export_size) : dyld->export_size;
                break;
            }
            case LC_ENCRYPTION_INFO:
            case LC_ENCRYPTION_INFO_64: {
                struct encryption_info_command *enc = (struct encryption_info_command*)ctx->load_commands[i].data;
                ctx->cryptid = ctx->header.is_swapped ? swap_uint32(enc->cryptid) : enc->cryptid;
                ctx->is_encrypted = (ctx->cryptid != 0);
                ctx->cryptoff = ctx->header.is_swapped ? swap_uint32(enc->cryptoff) : enc->cryptoff;
                ctx->cryptsize = ctx->header.is_swapped ? swap_uint32(enc->cryptsize) : enc->cryptsize;
                break;
            }
            case LC_UUID: {
                struct uuid_command *uuid = (struct uuid_command*)ctx->load_commands[i].data;
                memcpy(ctx->uuid, uuid->uuid, 16);
                ctx->has_uuid = true;
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
    
    ctx->segments = calloc(seg_count, sizeof(SegmentInfo));
    if (!ctx->segments) return 0;
    
    ctx->segment_count = 0;
    for (uint32_t i = 0; i < ctx->load_command_count; i++) {
        if (ctx->load_commands[i].cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64*)ctx->load_commands[i].data;
            SegmentInfo *info = &ctx->segments[ctx->segment_count++];
            
            strncpy(info->segname, seg->segname, 16);
            info->vmaddr = ctx->header.is_swapped ? swap_uint64(seg->vmaddr) : seg->vmaddr;
            info->vmsize = ctx->header.is_swapped ? swap_uint64(seg->vmsize) : seg->vmsize;
            info->fileoff = ctx->header.is_swapped ? swap_uint64(seg->fileoff) : seg->fileoff;
            info->filesize = ctx->header.is_swapped ? swap_uint64(seg->filesize) : seg->filesize;
            info->maxprot = ctx->header.is_swapped ? swap_uint32(seg->maxprot) : seg->maxprot;
            info->initprot = ctx->header.is_swapped ? swap_uint32(seg->initprot) : seg->initprot;
            info->nsects = ctx->header.is_swapped ? swap_uint32(seg->nsects) : seg->nsects;
            info->flags = ctx->header.is_swapped ? swap_uint32(seg->flags) : seg->flags;
        } else if (ctx->load_commands[i].cmd == LC_SEGMENT) {
            struct segment_command *seg = (struct segment_command*)ctx->load_commands[i].data;
            SegmentInfo *info = &ctx->segments[ctx->segment_count++];
            
            strncpy(info->segname, seg->segname, 16);
            info->vmaddr = ctx->header.is_swapped ? swap_uint32(seg->vmaddr) : seg->vmaddr;
            info->vmsize = ctx->header.is_swapped ? swap_uint32(seg->vmsize) : seg->vmsize;
            info->fileoff = ctx->header.is_swapped ? swap_uint32(seg->fileoff) : seg->fileoff;
            info->filesize = ctx->header.is_swapped ? swap_uint32(seg->filesize) : seg->filesize;
            info->maxprot = ctx->header.is_swapped ? swap_uint32(seg->maxprot) : seg->maxprot;
            info->initprot = ctx->header.is_swapped ? swap_uint32(seg->initprot) : seg->initprot;
            info->nsects = ctx->header.is_swapped ? swap_uint32(seg->nsects) : seg->nsects;
            info->flags = ctx->header.is_swapped ? swap_uint32(seg->flags) : seg->flags;
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
    
    ctx->sections = calloc(sect_count, sizeof(SectionInfo));
    if (!ctx->sections) return 0;
    
    ctx->section_count = 0;
    
    for (uint32_t i = 0; i < ctx->load_command_count; i++) {
        if (ctx->load_commands[i].cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64*)ctx->load_commands[i].data;
            uint32_t nsects = ctx->header.is_swapped ? swap_uint32(seg->nsects) : seg->nsects;
            struct section_64 *sections = (struct section_64*)((char*)seg + sizeof(struct segment_command_64));
            
            for (uint32_t j = 0; j < nsects; j++) {
                SectionInfo *info = &ctx->sections[ctx->section_count++];
                strncpy(info->sectname, sections[j].sectname, 16);
                strncpy(info->segname, sections[j].segname, 16);
                info->addr = ctx->header.is_swapped ? swap_uint64(sections[j].addr) : sections[j].addr;
                info->size = ctx->header.is_swapped ? swap_uint64(sections[j].size) : sections[j].size;
                info->offset = ctx->header.is_swapped ? swap_uint32(sections[j].offset) : sections[j].offset;
                info->align = ctx->header.is_swapped ? swap_uint32(sections[j].align) : sections[j].align;
                info->flags = ctx->header.is_swapped ? swap_uint32(sections[j].flags) : sections[j].flags;
            }
        }
    }
    
    return ctx->section_count;
}

