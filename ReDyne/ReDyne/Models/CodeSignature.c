#include "CodeSignature.h"
#include <stdlib.h>
#include <string.h>
#include <mach-o/loader.h>

#define MAX_ENTITLEMENTS 200

// MARK: - Helper Functions

static uint32_t find_code_signature_offset(MachOContext *ctx, uint32_t *size) {
    if (!ctx) return 0;
    
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
        
        if (cmd == LC_CODE_SIGNATURE) {
            struct linkedit_data_command sig_cmd;
            fseek(ctx->file, cmd_start, SEEK_SET);
            fread(&sig_cmd, sizeof(struct linkedit_data_command), 1, ctx->file);
            
            if (ctx->header.is_swapped) {
                *size = __builtin_bswap32(sig_cmd.datasize);
                return __builtin_bswap32(sig_cmd.dataoff);
            } else {
                *size = sig_cmd.datasize;
                return sig_cmd.dataoff;
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
    
    printf("Parsing code signature...\n");
    
    CodeSignatureInfo *info = (CodeSignatureInfo*)calloc(1, sizeof(CodeSignatureInfo));
    if (!info) return NULL;
    
    uint32_t sig_size = 0;
    uint32_t sig_offset = find_code_signature_offset(ctx, &sig_size);
    
    if (sig_offset == 0 || sig_size == 0) {
        printf("   No code signature found\n");
        info->is_signed = false;
        return info;
    }
    
    info->is_signed = true;
    info->signature_size = sig_size;
    info->is_adhoc_signed = (sig_size < 4096);
    
    fseek(ctx->file, sig_offset, SEEK_SET);
    
    uint8_t *sig_data = (uint8_t*)malloc(sig_size);
    if (!sig_data) {
        printf("   Memory allocation failed\n");
        return info;
    }
    
    if (fread(sig_data, 1, sig_size, ctx->file) != sig_size) {
        free(sig_data);
        printf("   Failed to read signature data\n");
        return info;
    }
    
    if (sig_size < 12) {
        free(sig_data);
        return info;
    }
    
    uint32_t super_magic = *(uint32_t*)sig_data;
    uint32_t super_length = *(uint32_t*)(sig_data + 4);
    uint32_t blob_count = *(uint32_t*)(sig_data + 8);
    
    if (super_magic == 0xc00cfade) {
    } else if (super_magic == 0xfade0cc0) { 
        super_length = __builtin_bswap32(super_length);
        blob_count = __builtin_bswap32(blob_count);
    } else {
        free(sig_data);
        printf("   Invalid SuperBlob magic: 0x%08x\n", super_magic);
        return info;
    }
    
    uint32_t index_offset = 12;
    for (uint32_t i = 0; i < blob_count && i < 50; i++) {
        if (index_offset + 8 > sig_size) break;
        
        uint32_t blob_type = *(uint32_t*)(sig_data + index_offset);
        uint32_t blob_offset = *(uint32_t*)(sig_data + index_offset + 4);
        
        if (super_magic != 0xc00cfade) {
            blob_type = __builtin_bswap32(blob_type);
            blob_offset = __builtin_bswap32(blob_offset);
        }
        
        index_offset += 8;
        
        if (blob_offset >= sig_size) continue;
        
        uint8_t *blob_data = sig_data + blob_offset;
        uint32_t blob_magic = *(uint32_t*)blob_data;
        
        if (blob_type == 5 || blob_magic == 0x71177ade || blob_magic == 0xfade7171) {
            info->has_entitlements = true;
        }
        
        if (blob_type == 0 && blob_offset + 20 < sig_size) { 
            uint32_t ident_offset = *(uint32_t*)(blob_data + 20);
            if (super_magic != 0xc00cfade) {
                ident_offset = __builtin_bswap32(ident_offset);
            }
            if (blob_offset + ident_offset < sig_size) {
                const char *ident = (const char*)(blob_data + ident_offset);
                strncpy(info->bundle_id, ident, sizeof(info->bundle_id) - 1);
            }
        }
    }
    
    free(sig_data);
    
    if (strlen(info->team_id) == 0) {
        strncpy(info->team_id, "(not embedded)", sizeof(info->team_id) - 1);
    }
    if (strlen(info->bundle_id) == 0) {
        strncpy(info->bundle_id, "(unknown)", sizeof(info->bundle_id) - 1);
    }
    
    printf("   Signature found (%u bytes, %s)\n", sig_size,
           info->is_adhoc_signed ? "ad-hoc" : "full");
    
    return info;
}

EntitlementsInfo* codesign_parse_entitlements(MachOContext *ctx) {
    if (!ctx) return NULL;
    
    printf("Parsing entitlements...\n");
    
    EntitlementsInfo *info = (EntitlementsInfo*)calloc(1, sizeof(EntitlementsInfo));
    if (!info) return NULL;
    
    info->entitlement_keys = (char**)calloc(MAX_ENTITLEMENTS, sizeof(char*));
    info->entitlement_values = (char**)calloc(MAX_ENTITLEMENTS, sizeof(char*));
    info->entitlement_count = 0;
    
    uint32_t sig_size = 0;
    uint32_t sig_offset = find_code_signature_offset(ctx, &sig_size);
    
    if (sig_offset == 0) {
        printf("   No code signature found\n");
        return info;
    }
    
    uint8_t *sig_data = (uint8_t*)malloc(sig_size);
    if (!sig_data) return info;
    
    fseek(ctx->file, sig_offset, SEEK_SET);
    fread(sig_data, 1, sig_size, ctx->file);
    
    for (uint32_t i = 0; i < sig_size - 8; i++) {
        uint32_t magic = __builtin_bswap32(*(uint32_t*)(sig_data + i));
        if (magic == 0xfade7171) {
            uint32_t length = __builtin_bswap32(*(uint32_t*)(sig_data + i + 4));
            
            if (length > 8 && length < sig_size - i) {
                uint8_t *entitlements_data = sig_data + i + 8;
                size_t entitlements_len = length - 8;
                
                info->entitlements_xml = (char*)malloc(entitlements_len + 1);
                if (info->entitlements_xml) {
                    memcpy(info->entitlements_xml, entitlements_data, entitlements_len);
                    info->entitlements_xml[entitlements_len] = '\0';
                    info->xml_length = entitlements_len;
                }
                
                printf("   Found entitlements (%zu bytes)\n", entitlements_len);
                break;
            }
        }
    }
    
    free(sig_data);
    
    if (info->entitlement_count == 0 && !info->entitlements_xml) {
        printf("   No entitlements found\n");
    }
    
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

