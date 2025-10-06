#ifndef CodeSignature_h
#define CodeSignature_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "MachOHeader.h"

// MARK: - Structures

typedef struct {
    char team_id[128];
    char bundle_id[256];
    bool is_signed;
    bool is_adhoc_signed;
    bool has_entitlements;
    uint32_t signature_size;
    uint32_t code_directory_offset;
} CodeSignatureInfo;

typedef struct {
    char **entitlement_keys;
    char **entitlement_values;
    int entitlement_count;
    char *entitlements_xml;
    size_t xml_length;
} EntitlementsInfo;

// MARK: - Public API

CodeSignatureInfo* codesign_parse_signature(MachOContext *ctx);
EntitlementsInfo* codesign_parse_entitlements(MachOContext *ctx);

bool codesign_is_signed(MachOContext *ctx);
void codesign_free_signature(CodeSignatureInfo *info);
void codesign_free_entitlements(EntitlementsInfo *info);

#endif 

