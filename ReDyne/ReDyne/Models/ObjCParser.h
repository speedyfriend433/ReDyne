#ifndef OBJC_PARSER_H
#define OBJC_PARSER_H

#include <stdint.h>
#include <stdbool.h>
#include "MachOHeader.h"

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - ObjC Runtime Structures (64-bit)

typedef struct {
    uint64_t name_ptr;
    uint64_t types_ptr;
    uint64_t imp;
} objc_method_64_t;

typedef struct {
    uint32_t entsize;
    uint32_t count;
} objc_method_list_t;

typedef struct {
    uint64_t name_ptr;
    uint64_t attributes_ptr;
} objc_property_64_t;

typedef struct {
    uint32_t entsize;
    uint32_t count;
} objc_property_list_t;

typedef struct {
    uint64_t offset_ptr;
    uint64_t name_ptr;
    uint64_t type_ptr;
    uint32_t alignment;
    uint32_t size;
} objc_ivar_64_t;

typedef struct {
    uint32_t entsize;
    uint32_t count;
} objc_ivar_list_t;

typedef struct {
    uint32_t flags;
    uint32_t instanceStart;
    uint32_t instanceSize;
    uint32_t reserved;
    uint64_t ivarLayout_ptr;
    uint64_t name_ptr;
    uint64_t baseMethods_ptr;
    uint64_t baseProtocols_ptr;
    uint64_t ivars_ptr;
    uint64_t weakIvarLayout_ptr;
    uint64_t baseProperties_ptr;
} objc_class_ro_64_t;

typedef struct {
    uint64_t isa;
    uint64_t superclass;
    uint64_t cache;
    uint64_t vtable;
    uint64_t data_ptr;
} objc_class_64_t;

typedef struct {
    uint64_t name_ptr;
    uint64_t class_ptr;
    uint64_t instanceMethods_ptr;
    uint64_t classMethods_ptr;
    uint64_t protocols_ptr;
    uint64_t instanceProperties_ptr;
} objc_category_64_t;

// MARK: - Parsed ObjC Data Structures

typedef struct ObjCMethodInfo {
    char name[256];
    char types[128];
    uint64_t implementation;
    bool is_class_method;
} ObjCMethodInfo;

typedef struct ObjCPropertyInfo {
    char name[128];
    char attributes[256];
} ObjCPropertyInfo;

typedef struct ObjCIvarInfo {
    char name[128];
    char type[128];
    uint64_t offset;
} ObjCIvarInfo;

typedef struct ObjCProtocolInfo {
    char name[128];
    int method_count;
    ObjCMethodInfo *methods;
} ObjCProtocolInfo;

typedef struct ObjCClassInfo {
    char name[256];
    char superclass_name[256];
    uint64_t address;
    
    int instance_method_count;
    ObjCMethodInfo *instance_methods;
    
    int class_method_count;
    ObjCMethodInfo *class_methods;
    
    int property_count;
    ObjCPropertyInfo *properties;
    
    int ivar_count;
    ObjCIvarInfo *ivars;
    
    int protocol_count;
    char **protocols;
    
    bool is_swift;
    bool is_meta_class;
} ObjCClassInfo;

typedef struct ObjCCategoryInfo {
    char name[256];
    char class_name[256];
    
    int instance_method_count;
    ObjCMethodInfo *instance_methods;
    
    int class_method_count;
    ObjCMethodInfo *class_methods;
    
    int property_count;
    ObjCPropertyInfo *properties;
    
    int protocol_count;
    char **protocols;
} ObjCCategoryInfo;

typedef struct ObjCRuntimeInfo {
    int class_count;
    ObjCClassInfo *classes;
    
    int category_count;
    ObjCCategoryInfo *categories;
    
    int protocol_count;
    ObjCProtocolInfo *protocols;
} ObjCRuntimeInfo;

// MARK: - Public Functions

ObjCRuntimeInfo* objc_parse_runtime(MachOContext *ctx);

void objc_free_runtime_info(ObjCRuntimeInfo *info);

bool objc_has_runtime_data(MachOContext *ctx);

int objc_get_class_count(MachOContext *ctx);

#ifdef __cplusplus
}
#endif

#endif

