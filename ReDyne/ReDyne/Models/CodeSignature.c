#include "CodeSignature.h"
#include <stdlib.h>
#include <string.h>
#include <mach-o/loader.h>

#define MAX_ENTITLEMENTS 200

// MARK: - Helper Functions

/// Unaligned-safe 32-bit read (blob offsets are attacker-controlled and need not be 4-aligned).
static uint32_t cs_read32(const uint8_t *p) {
    uint32_t v;
    memcpy(&v, p, sizeof(v));
    return v;
}

static uint64_t find_code_signature_offset(MachOContext *ctx, uint32_t *size) {
    if (!ctx) return 0;
    
    uint32_t header_size = ctx->header.is_64bit ? sizeof(struct mach_header_64) : sizeof(struct mach_header);
    fseek(ctx->file, (long)(ctx->base_offset + header_size), SEEK_SET);
    
    for (uint32_t i = 0; i < ctx->header.ncmds; i++) {
        uint32_t cmd, cmdsize;
        long cmd_start = ftell(ctx->file);
        
        if (fread(&cmd, sizeof(uint32_t), 1, ctx->file) != 1) return 0;
        if (fread(&cmdsize, sizeof(uint32_t), 1, ctx->file) != 1) return 0;
        
        if (ctx->header.is_swapped) {
            cmd = __builtin_bswap32(cmd);
            cmdsize = __builtin_bswap32(cmdsize);
        }
        
        if (cmd == LC_CODE_SIGNATURE) {
            struct linkedit_data_command sig_cmd;
            fseek(ctx->file, cmd_start, SEEK_SET);
            if (fread(&sig_cmd, sizeof(struct linkedit_data_command), 1, ctx->file) != 1) return 0;
            
            if (ctx->header.is_swapped) {
                *size = __builtin_bswap32(sig_cmd.datasize);
                return (uint64_t)__builtin_bswap32(sig_cmd.dataoff) + ctx->base_offset;
            } else {
                *size = sig_cmd.datasize;
                return (uint64_t)sig_cmd.dataoff + ctx->base_offset;
            }
        }
        
        fseek(ctx->file, cmd_start + cmdsize, SEEK_SET);
    }
    
    return 0;
}

// MARK: - Public Functions

bool codesign_is_signed(MachOContext *ctx) {
    uint32_t size = 0;
    return find_code_signature_offset(ctx, &size) != 0;
}

CodeSignatureInfo* codesign_parse_signature(MachOContext *ctx) {
    if (!ctx) return NULL;
    
    CodeSignatureInfo *info = (CodeSignatureInfo*)calloc(1, sizeof(CodeSignatureInfo));
    if (!info) return NULL;
    
    uint32_t sig_size = 0;
    uint64_t sig_offset = find_code_signature_offset(ctx, &sig_size);
    
    if (sig_offset == 0 || sig_size == 0) {
        info->is_signed = false;
        return info;
    }
    
    info->is_signed = true;
    info->signature_size = sig_size;
    info->is_adhoc_signed = (sig_size < 4096);

    if (sig_offset + sig_size > (uint64_t)ctx->file_size) {
        info->is_signed = false;
        return info;
    }

    fseek(ctx->file, (long)sig_offset, SEEK_SET);

    uint8_t *sig_data = (uint8_t*)malloc(sig_size);
    if (!sig_data) {
        return info;
    }

    if (fread(sig_data, 1, sig_size, ctx->file) != sig_size) {
        free(sig_data);
        return info;
    }
    
    if (sig_size < 12) {
        free(sig_data);
        return info;
    }
    
    uint32_t super_magic = cs_read32(sig_data);
    uint32_t super_length = cs_read32(sig_data + 4);
    uint32_t blob_count = cs_read32(sig_data + 8);
    
    if (super_magic == 0xc00cfade) {
    } else if (super_magic == 0xfade0cc0) {
        super_length = __builtin_bswap32(super_length);
        blob_count = __builtin_bswap32(blob_count);
    } else {
        if (super_magic == 0xc00cdefa) {
            // try reading as big endian (reverse the current logic)
            super_length = __builtin_bswap32(super_length);
            blob_count = __builtin_bswap32(blob_count);
        } else {
            free(sig_data);
            info->is_signed = false;
            return info;
        }
    }
    
    uint32_t index_offset = 12;

    if (blob_count > 100 || blob_count == 0) {
        if (sig_size > 0x8c) {
            uint32_t first_blob_offset = cs_read32(sig_data + 16);
            if (super_magic == 0xc00cdefa) {
                first_blob_offset = __builtin_bswap32(first_blob_offset);
            }
            if ((uint64_t)first_blob_offset + 0x60 < sig_size) {
                const char *ident = (const char*)(sig_data + first_blob_offset + 0x60);
                if (ident[0] >= 32 && ident[0] <= 126) { // Looks like a valid string
                    size_t avail = sig_size - ((size_t)first_blob_offset + 0x60);
                    size_t n = strnlen(ident, avail);
                    if (n > sizeof(info->bundle_id) - 1) n = sizeof(info->bundle_id) - 1;
                    memcpy(info->bundle_id, ident, n);
                }
            }
        }
        free(sig_data);
        goto finish_parsing;
    }

    for (uint32_t i = 0; i < blob_count && i < 50; i++) {
        if (index_offset + 8 > sig_size) break;

        uint32_t blob_type = cs_read32(sig_data + index_offset);
        uint32_t blob_offset = cs_read32(sig_data + index_offset + 4);

        if (super_magic != 0xc00cfade) {
            blob_type = __builtin_bswap32(blob_type);
            blob_offset = __builtin_bswap32(blob_offset);
        }

        index_offset += 8;

        if ((uint64_t)blob_offset + 4 > sig_size) {
            continue;
        }

        uint8_t *blob_data = sig_data + blob_offset;
        uint32_t blob_magic = cs_read32(blob_data);
        
        if (blob_type == 5 || blob_magic == 0x71177ade || blob_magic == 0xfade7171) {
            info->has_entitlements = true;
        }
        
        if (blob_type == 0 && (uint64_t)blob_offset + 24 <= sig_size) {
            uint32_t ident_offset = cs_read32(blob_data + 20);
            if (super_magic != 0xc00cfade) {
                ident_offset = __builtin_bswap32(ident_offset);
            }
            // 64-bit sum: a uint32 sum can wrap and defeat the bounds check
            if ((uint64_t)blob_offset + ident_offset < sig_size) {
                const char *ident = (const char*)(blob_data + ident_offset);
                if (strlen(info->bundle_id) == 0) {
                    size_t avail = sig_size - ((size_t)blob_offset + ident_offset);
                    size_t n = strnlen(ident, avail);
                    if (n > sizeof(info->bundle_id) - 1) n = sizeof(info->bundle_id) - 1;
                    memcpy(info->bundle_id, ident, n);
                }
            }
        }
    }
    
    free(sig_data);
    
finish_parsing:
    if (strlen(info->team_id) == 0) {
        strncpy(info->team_id, "(not embedded)", sizeof(info->team_id) - 1);
    }
    if (strlen(info->bundle_id) == 0) {
        strncpy(info->bundle_id, "(unknown)", sizeof(info->bundle_id) - 1);
    }

    return info;
}

EntitlementsInfo* codesign_parse_entitlements(MachOContext *ctx) {
    if (!ctx) return NULL;
    
    EntitlementsInfo *info = (EntitlementsInfo*)calloc(1, sizeof(EntitlementsInfo));
    if (!info) return NULL;
    
    info->entitlement_keys = (char**)calloc(MAX_ENTITLEMENTS, sizeof(char*));
    info->entitlement_values = (char**)calloc(MAX_ENTITLEMENTS, sizeof(char*));
    info->entitlement_count = 0;
    
    uint32_t sig_size = 0;
    uint64_t sig_offset = find_code_signature_offset(ctx, &sig_size);
    
    if (sig_offset == 0) {
        return info;
    }
    
    if (sig_offset + sig_size > (uint64_t)ctx->file_size) {
        return info;
    }

    uint8_t *sig_data = (uint8_t*)malloc(sig_size);
    if (!sig_data) return info;

    fseek(ctx->file, (long)sig_offset, SEEK_SET);
    if (fread(sig_data, 1, sig_size, ctx->file) != sig_size) {
        free(sig_data);
        return info;
    }

    // Only trust entitlement blobs referenced from the SuperBlob index; scanning raw
    // bytes would let any data inside the signature masquerade as entitlements.
    // SuperBlob fields are always big-endian on disk.
    if (sig_size >= 12 && __builtin_bswap32(cs_read32(sig_data)) == 0xfade0cc0) {
        uint32_t count = __builtin_bswap32(cs_read32(sig_data + 8));
        for (uint32_t i = 0; i < count && i < 100; i++) {
            uint64_t idx = 12 + (uint64_t)i * 8;
            if (idx + 8 > sig_size) break;
            uint32_t blob_off = __builtin_bswap32(cs_read32(sig_data + idx + 4));
            if ((uint64_t)blob_off + 8 > sig_size) continue;
            if (__builtin_bswap32(cs_read32(sig_data + blob_off)) != 0xfade7171) continue;

            uint32_t length = __builtin_bswap32(cs_read32(sig_data + blob_off + 4));
            if (length > 8 && (uint64_t)blob_off + length <= sig_size) {
                size_t entitlements_len = length - 8;
                info->entitlements_xml = (char*)malloc(entitlements_len + 1);
                if (info->entitlements_xml) {
                    memcpy(info->entitlements_xml, sig_data + blob_off + 8, entitlements_len);
                    info->entitlements_xml[entitlements_len] = '\0';
                    info->xml_length = entitlements_len;
                }
                break;
            }
        }
    }
    
    free(sig_data);
    
    return info;
}

void codesign_free_signature(CodeSignatureInfo *info) {
    if (info) {
        free(info);
    }
}

void codesign_free_entitlements(EntitlementsInfo *info) {
    if (!info) return;
    
    for (int i = 0; i < info->entitlement_count; i++) {
        free(info->entitlement_keys[i]);
        free(info->entitlement_values[i]);
    }
    free(info->entitlement_keys);
    free(info->entitlement_values);
    free(info->entitlements_xml);
    free(info);
}

