#include "ObjCParser.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// MARK: - Helper Functions

static bool is_valid_address(MachOContext *ctx, uint64_t addr) {
    return addr != 0 && addr != 0xFFFFFFFFFFFFFFFF;
}

static uint64_t read_ptr_at_offset(MachOContext *ctx, uint64_t file_offset) {
    if (!ctx || !ctx->file) return 0;
    
    uint64_t value = 0;
    fseek(ctx->file, file_offset, SEEK_SET);
    fread(&value, sizeof(uint64_t), 1, ctx->file);
    
    return ctx->header.is_swapped ? __builtin_bswap64(value) : value;
}

static uint32_t read_uint32_at_offset(MachOContext *ctx, uint64_t file_offset) {
    if (!ctx || !ctx->file) return 0;
    
    uint32_t value = 0;
    fseek(ctx->file, file_offset, SEEK_SET);
    fread(&value, sizeof(uint32_t), 1, ctx->file);
    
    return ctx->header.is_swapped ? __builtin_bswap32(value) : value;
}

static void read_string_at_offset(MachOContext *ctx, uint64_t file_offset, char *buffer, size_t max_len) {
    if (!ctx || !ctx->file || !buffer) return;
    
    memset(buffer, 0, max_len);
    fseek(ctx->file, file_offset, SEEK_SET);
    
    size_t i = 0;
    while (i < max_len - 1) {
        char c = fgetc(ctx->file);
        if (c == 0 || c == EOF) break;
        buffer[i++] = c;
    }
    buffer[i] = '\0';
}

static uint64_t vm_addr_to_file_offset(MachOContext *ctx, uint64_t vm_addr) {
    if (!ctx) return 0;
    
    for (int i = 0; i < ctx->segment_count; i++) {
        SegmentInfo *seg = &ctx->segments[i];
        if (vm_addr >= seg->vmaddr && vm_addr < seg->vmaddr + seg->vmsize) {
            uint64_t offset_in_segment = vm_addr - seg->vmaddr;
            return seg->fileoff + offset_in_segment;
        }
    }
    
    return 0;
}

// MARK: - Section Finding

static SectionInfo* find_section(MachOContext *ctx, const char *segname, const char *sectname) {
    if (!ctx) return NULL;
    
    for (int i = 0; i < ctx->section_count; i++) {
        SectionInfo *sect = &ctx->sections[i];
        if (strcmp(sect->segname, segname) == 0 && strcmp(sect->sectname, sectname) == 0) {
            return sect;
        }
    }
    
    return NULL;
}

// MARK: - Protocol Parsing

typedef struct {
    uint64_t isa;
    uint64_t name_ptr;
    uint64_t protocols_ptr;
    uint64_t instance_methods_ptr;
    uint64_t class_methods_ptr;
    uint64_t optional_instance_methods_ptr;
    uint64_t optional_class_methods_ptr;
    uint64_t instance_properties_ptr;
    uint32_t size;
    uint32_t flags;
} objc_protocol_64_t;

static uint32_t parse_protocol_list(MachOContext *ctx, uint64_t protocol_list_addr, char ***protocols_out) {
    *protocols_out = NULL;
    
    if (!is_valid_address(ctx, protocol_list_addr)) {
        return 0;
    }
    
    uint64_t file_offset = vm_addr_to_file_offset(ctx, protocol_list_addr);
    if (file_offset == 0) {
        return 0;
    }
    
    uint64_t count = read_ptr_at_offset(ctx, file_offset);
    if (count == 0 || count > 1000) {
        return 0;
    }
    
    char **protocol_names = calloc(count, sizeof(char*));
    if (!protocol_names) {
        return 0;
    }
    
    uint64_t ptr_offset = file_offset + 8;
    for (uint32_t i = 0; i < count; i++) {
        uint64_t protocol_ptr = read_ptr_at_offset(ctx, ptr_offset);
        ptr_offset += 8;
        
        if (!is_valid_address(ctx, protocol_ptr)) {
            continue;
        }
        
        uint64_t protocol_offset = vm_addr_to_file_offset(ctx, protocol_ptr);
        if (protocol_offset == 0) {
            continue;
        }
        
        objc_protocol_64_t protocol;
        fseek(ctx->file, protocol_offset, SEEK_SET);
        fread(&protocol, sizeof(objc_protocol_64_t), 1, ctx->file);
        
        if (ctx->header.is_swapped) {
            protocol.name_ptr = __builtin_bswap64(protocol.name_ptr);
        }
        
        if (is_valid_address(ctx, protocol.name_ptr)) {
            uint64_t name_offset = vm_addr_to_file_offset(ctx, protocol.name_ptr);
            if (name_offset > 0) {
                char name_buffer[256] = {0};
                read_string_at_offset(ctx, name_offset, name_buffer, sizeof(name_buffer));
                protocol_names[i] = strdup(name_buffer);
            }
        }
    }
    
    *protocols_out = protocol_names;
    return (uint32_t)count;
}

// MARK: - Method Parsing

static int parse_method_list(MachOContext *ctx, uint64_t method_list_vm_addr, ObjCMethodInfo **methods_out, bool is_class_method) {
    if (!is_valid_address(ctx, method_list_vm_addr)) {
        *methods_out = NULL;
        return 0;
    }
    
    uint64_t file_offset = vm_addr_to_file_offset(ctx, method_list_vm_addr);
    if (file_offset == 0) {
        *methods_out = NULL;
        return 0;
    }
    
    uint32_t entsize = read_uint32_at_offset(ctx, file_offset);
    uint32_t count = read_uint32_at_offset(ctx, file_offset + 4);
    
    if (count == 0 || count > 10000) {
        *methods_out = NULL;
        return 0;
    }
    
    ObjCMethodInfo *methods = calloc(count, sizeof(ObjCMethodInfo));
    if (!methods) {
        *methods_out = NULL;
        return 0;
    }
    
    uint64_t method_offset = file_offset + 8;
    for (uint32_t i = 0; i < count; i++) {
        objc_method_64_t method;
        fseek(ctx->file, method_offset, SEEK_SET);
        fread(&method, sizeof(objc_method_64_t), 1, ctx->file);
        
        if (ctx->header.is_swapped) {
            method.name_ptr = __builtin_bswap64(method.name_ptr);
            method.types_ptr = __builtin_bswap64(method.types_ptr);
            method.imp = __builtin_bswap64(method.imp);
        }
        
        if (is_valid_address(ctx, method.name_ptr)) {
            uint64_t name_offset = vm_addr_to_file_offset(ctx, method.name_ptr);
            if (name_offset > 0) {
                read_string_at_offset(ctx, name_offset, methods[i].name, sizeof(methods[i].name));
            }
        }
        
        if (is_valid_address(ctx, method.types_ptr)) {
            uint64_t types_offset = vm_addr_to_file_offset(ctx, method.types_ptr);
            if (types_offset > 0) {
                read_string_at_offset(ctx, types_offset, methods[i].types, sizeof(methods[i].types));
            }
        }
        
        methods[i].implementation = method.imp;
        methods[i].is_class_method = is_class_method;
        
        method_offset += sizeof(objc_method_64_t);
    }
    
    *methods_out = methods;
    return count;
}

// MARK: - Property Parsing

static int parse_property_list(MachOContext *ctx, uint64_t property_list_vm_addr, ObjCPropertyInfo **properties_out) {
    if (!is_valid_address(ctx, property_list_vm_addr)) {
        *properties_out = NULL;
        return 0;
    }
    
    uint64_t file_offset = vm_addr_to_file_offset(ctx, property_list_vm_addr);
    if (file_offset == 0) {
        *properties_out = NULL;
        return 0;
    }
    
    uint32_t entsize = read_uint32_at_offset(ctx, file_offset);
    uint32_t count = read_uint32_at_offset(ctx, file_offset + 4);
    
    if (count == 0 || count > 10000) {
        *properties_out = NULL;
        return 0;
    }
    
    ObjCPropertyInfo *properties = calloc(count, sizeof(ObjCPropertyInfo));
    if (!properties) {
        *properties_out = NULL;
        return 0;
    }
    
    uint64_t property_offset = file_offset + 8;
    for (uint32_t i = 0; i < count; i++) {
        objc_property_64_t property;
        fseek(ctx->file, property_offset, SEEK_SET);
        fread(&property, sizeof(objc_property_64_t), 1, ctx->file);
        
        if (ctx->header.is_swapped) {
            property.name_ptr = __builtin_bswap64(property.name_ptr);
            property.attributes_ptr = __builtin_bswap64(property.attributes_ptr);
        }
        
        if (is_valid_address(ctx, property.name_ptr)) {
            uint64_t name_offset = vm_addr_to_file_offset(ctx, property.name_ptr);
            if (name_offset > 0) {
                read_string_at_offset(ctx, name_offset, properties[i].name, sizeof(properties[i].name));
            }
        }
        
        if (is_valid_address(ctx, property.attributes_ptr)) {
            uint64_t attr_offset = vm_addr_to_file_offset(ctx, property.attributes_ptr);
            if (attr_offset > 0) {
                read_string_at_offset(ctx, attr_offset, properties[i].attributes, sizeof(properties[i].attributes));
            }
        }
        
        property_offset += sizeof(objc_property_64_t);
    }
    
    *properties_out = properties;
    return count;
}

// MARK: - Ivar Parsing

static int parse_ivar_list(MachOContext *ctx, uint64_t ivar_list_vm_addr, ObjCIvarInfo **ivars_out) {
    if (!is_valid_address(ctx, ivar_list_vm_addr)) {
        *ivars_out = NULL;
        return 0;
    }
    
    uint64_t file_offset = vm_addr_to_file_offset(ctx, ivar_list_vm_addr);
    if (file_offset == 0) {
        *ivars_out = NULL;
        return 0;
    }
    
    uint32_t entsize = read_uint32_at_offset(ctx, file_offset);
    uint32_t count = read_uint32_at_offset(ctx, file_offset + 4);
    
    if (count == 0 || count > 10000) {
        *ivars_out = NULL;
        return 0;
    }
    
    ObjCIvarInfo *ivars = calloc(count, sizeof(ObjCIvarInfo));
    if (!ivars) {
        *ivars_out = NULL;
        return 0;
    }
    
    uint64_t ivar_offset = file_offset + 8;
    for (uint32_t i = 0; i < count; i++) {
        objc_ivar_64_t ivar;
        fseek(ctx->file, ivar_offset, SEEK_SET);
        fread(&ivar, sizeof(objc_ivar_64_t), 1, ctx->file);
        
        if (ctx->header.is_swapped) {
            ivar.offset_ptr = __builtin_bswap64(ivar.offset_ptr);
            ivar.name_ptr = __builtin_bswap64(ivar.name_ptr);
            ivar.type_ptr = __builtin_bswap64(ivar.type_ptr);
            ivar.alignment = __builtin_bswap32(ivar.alignment);
            ivar.size = __builtin_bswap32(ivar.size);
        }
        
        if (is_valid_address(ctx, ivar.offset_ptr)) {
            uint64_t offset_file = vm_addr_to_file_offset(ctx, ivar.offset_ptr);
            if (offset_file > 0) {
                ivars[i].offset = read_uint32_at_offset(ctx, offset_file);
            }
        }
        
        if (is_valid_address(ctx, ivar.name_ptr)) {
            uint64_t name_offset = vm_addr_to_file_offset(ctx, ivar.name_ptr);
            if (name_offset > 0) {
                read_string_at_offset(ctx, name_offset, ivars[i].name, sizeof(ivars[i].name));
            }
        }
        
        if (is_valid_address(ctx, ivar.type_ptr)) {
            uint64_t type_offset = vm_addr_to_file_offset(ctx, ivar.type_ptr);
            if (type_offset > 0) {
                read_string_at_offset(ctx, type_offset, ivars[i].type, sizeof(ivars[i].type));
            }
        }
        
        ivar_offset += sizeof(objc_ivar_64_t);
    }
    
    *ivars_out = ivars;
    return count;
}

// MARK: - Category Parsing

static bool parse_category(MachOContext *ctx, uint64_t cat_vm_addr, ObjCCategoryInfo *cat_info) {
    if (!is_valid_address(ctx, cat_vm_addr)) return false;
    
    uint64_t cat_file_offset = vm_addr_to_file_offset(ctx, cat_vm_addr);
    if (cat_file_offset == 0) return false;
    
    objc_category_64_t cat_struct;
    fseek(ctx->file, cat_file_offset, SEEK_SET);
    fread(&cat_struct, sizeof(objc_category_64_t), 1, ctx->file);
    
    if (ctx->header.is_swapped) {
        cat_struct.name_ptr = __builtin_bswap64(cat_struct.name_ptr);
        cat_struct.class_ptr = __builtin_bswap64(cat_struct.class_ptr);
        cat_struct.instanceMethods_ptr = __builtin_bswap64(cat_struct.instanceMethods_ptr);
        cat_struct.classMethods_ptr = __builtin_bswap64(cat_struct.classMethods_ptr);
        cat_struct.protocols_ptr = __builtin_bswap64(cat_struct.protocols_ptr);
        cat_struct.instanceProperties_ptr = __builtin_bswap64(cat_struct.instanceProperties_ptr);
    }
    
    memset(cat_info, 0, sizeof(ObjCCategoryInfo));
    
    if (is_valid_address(ctx, cat_struct.name_ptr)) {
        uint64_t name_offset = vm_addr_to_file_offset(ctx, cat_struct.name_ptr);
        if (name_offset > 0) {
            read_string_at_offset(ctx, name_offset, cat_info->name, sizeof(cat_info->name));
        }
    }
    
    if (is_valid_address(ctx, cat_struct.class_ptr)) {
        uint64_t class_file_offset = vm_addr_to_file_offset(ctx, cat_struct.class_ptr);
        if (class_file_offset > 0) {
            objc_class_64_t class_struct;
            fseek(ctx->file, class_file_offset, SEEK_SET);
            fread(&class_struct, sizeof(objc_class_64_t), 1, ctx->file);
            
            if (ctx->header.is_swapped) {
                class_struct.data_ptr = __builtin_bswap64(class_struct.data_ptr);
            }
            
            uint64_t ro_vm_addr = class_struct.data_ptr & ~0x7ULL;
            if (is_valid_address(ctx, ro_vm_addr)) {
                uint64_t ro_file_offset = vm_addr_to_file_offset(ctx, ro_vm_addr);
                if (ro_file_offset > 0) {
                    objc_class_ro_64_t ro;
                    fseek(ctx->file, ro_file_offset, SEEK_SET);
                    fread(&ro, sizeof(objc_class_ro_64_t), 1, ctx->file);
                    
                    if (ctx->header.is_swapped) {
                        ro.name_ptr = __builtin_bswap64(ro.name_ptr);
                    }
                    
                    if (is_valid_address(ctx, ro.name_ptr)) {
                        uint64_t class_name_offset = vm_addr_to_file_offset(ctx, ro.name_ptr);
                        if (class_name_offset > 0) {
                            read_string_at_offset(ctx, class_name_offset, cat_info->class_name, sizeof(cat_info->class_name));
                        }
                    }
                }
            }
        }
    }
    
    if (strlen(cat_info->name) == 0 && strlen(cat_info->class_name) == 0) {
        return false;
    }
    
    cat_info->instance_method_count = 0;
    cat_info->instance_methods = NULL;
    if (is_valid_address(ctx, cat_struct.instanceMethods_ptr)) {
        cat_info->instance_method_count = parse_method_list(ctx, cat_struct.instanceMethods_ptr, 
                                                            &cat_info->instance_methods, false);
    }
    
    cat_info->class_method_count = 0;
    cat_info->class_methods = NULL;
    if (is_valid_address(ctx, cat_struct.classMethods_ptr)) {
        cat_info->class_method_count = parse_method_list(ctx, cat_struct.classMethods_ptr, 
                                                         &cat_info->class_methods, true);
    }
    
    cat_info->property_count = 0;
    cat_info->properties = NULL;
    if (is_valid_address(ctx, cat_struct.instanceProperties_ptr)) {
        cat_info->property_count = parse_property_list(ctx, cat_struct.instanceProperties_ptr, 
                                                       &cat_info->properties);
    }
    
    cat_info->protocol_count = 0;
    cat_info->protocols = NULL;
    if (is_valid_address(ctx, cat_struct.protocols_ptr)) {
        cat_info->protocol_count = parse_protocol_list(ctx, cat_struct.protocols_ptr, 
                                                       &cat_info->protocols);
    }
    
    return true;
}

// MARK: - Class Parsing

static bool parse_class(MachOContext *ctx, uint64_t class_vm_addr, ObjCClassInfo *class_info) {
    if (!is_valid_address(ctx, class_vm_addr)) return false;
    
    uint64_t class_file_offset = vm_addr_to_file_offset(ctx, class_vm_addr);
    if (class_file_offset == 0) return false;
    
    objc_class_64_t class_struct;
    fseek(ctx->file, class_file_offset, SEEK_SET);
    fread(&class_struct, sizeof(objc_class_64_t), 1, ctx->file);
    
    if (ctx->header.is_swapped) {
        class_struct.isa = __builtin_bswap64(class_struct.isa);
        class_struct.superclass = __builtin_bswap64(class_struct.superclass);
        class_struct.data_ptr = __builtin_bswap64(class_struct.data_ptr);
    }
    
    class_info->address = class_vm_addr;
    
    if (!is_valid_address(ctx, class_struct.data_ptr)) return false;
    
    uint64_t ro_vm_addr = class_struct.data_ptr & ~0x7ULL;
    uint64_t ro_file_offset = vm_addr_to_file_offset(ctx, ro_vm_addr);
    if (ro_file_offset == 0) return false;
    
    objc_class_ro_64_t ro;
    fseek(ctx->file, ro_file_offset, SEEK_SET);
    fread(&ro, sizeof(objc_class_ro_64_t), 1, ctx->file);
    
    if (ctx->header.is_swapped) {
        ro.flags = __builtin_bswap32(ro.flags);
        ro.name_ptr = __builtin_bswap64(ro.name_ptr);
        ro.baseMethods_ptr = __builtin_bswap64(ro.baseMethods_ptr);
        ro.baseProperties_ptr = __builtin_bswap64(ro.baseProperties_ptr);
        ro.ivars_ptr = __builtin_bswap64(ro.ivars_ptr);
    }
    
    if (is_valid_address(ctx, ro.name_ptr)) {
        uint64_t name_offset = vm_addr_to_file_offset(ctx, ro.name_ptr);
        if (name_offset > 0) {
            read_string_at_offset(ctx, name_offset, class_info->name, sizeof(class_info->name));
        }
    }
    
    class_info->is_swift = (strncmp(class_info->name, "_Tt", 3) == 0) || (strchr(class_info->name, '.') != NULL);
    
    if (is_valid_address(ctx, class_struct.superclass)) {
        uint64_t super_file_offset = vm_addr_to_file_offset(ctx, class_struct.superclass);
        if (super_file_offset > 0) {
            objc_class_64_t super_class;
            fseek(ctx->file, super_file_offset, SEEK_SET);
            fread(&super_class, sizeof(objc_class_64_t), 1, ctx->file);
            
            if (ctx->header.is_swapped) {
                super_class.data_ptr = __builtin_bswap64(super_class.data_ptr);
            }
            
            uint64_t super_ro_addr = super_class.data_ptr & ~0x7ULL;
            uint64_t super_ro_offset = vm_addr_to_file_offset(ctx, super_ro_addr);
            if (super_ro_offset > 0) {
                objc_class_ro_64_t super_ro;
                fseek(ctx->file, super_ro_offset, SEEK_SET);
                fread(&super_ro, sizeof(objc_class_ro_64_t), 1, ctx->file);
                
                if (ctx->header.is_swapped) {
                    super_ro.name_ptr = __builtin_bswap64(super_ro.name_ptr);
                }
                
                if (is_valid_address(ctx, super_ro.name_ptr)) {
                    uint64_t super_name_offset = vm_addr_to_file_offset(ctx, super_ro.name_ptr);
                    if (super_name_offset > 0) {
                        read_string_at_offset(ctx, super_name_offset, class_info->superclass_name, sizeof(class_info->superclass_name));
                    }
                }
            }
        }
    }
    
    class_info->instance_method_count = parse_method_list(ctx, ro.baseMethods_ptr, &class_info->instance_methods, false);
    class_info->property_count = parse_property_list(ctx, ro.baseProperties_ptr, &class_info->properties);
    class_info->ivar_count = parse_ivar_list(ctx, ro.ivars_ptr, &class_info->ivars);
    class_info->protocol_count = parse_protocol_list(ctx, ro.baseProtocols_ptr, &class_info->protocols);
    
    if (is_valid_address(ctx, class_struct.isa)) {
        uint64_t metaclass_file_offset = vm_addr_to_file_offset(ctx, class_struct.isa);
        if (metaclass_file_offset > 0) {
            objc_class_64_t metaclass;
            fseek(ctx->file, metaclass_file_offset, SEEK_SET);
            fread(&metaclass, sizeof(objc_class_64_t), 1, ctx->file);
            
            if (ctx->header.is_swapped) {
                metaclass.data_ptr = __builtin_bswap64(metaclass.data_ptr);
            }
            
            uint64_t meta_ro_addr = metaclass.data_ptr & ~0x7ULL;
            uint64_t meta_ro_offset = vm_addr_to_file_offset(ctx, meta_ro_addr);
            if (meta_ro_offset > 0) {
                objc_class_ro_64_t meta_ro;
                fseek(ctx->file, meta_ro_offset, SEEK_SET);
                fread(&meta_ro, sizeof(objc_class_ro_64_t), 1, ctx->file);
                
                if (ctx->header.is_swapped) {
                    meta_ro.baseMethods_ptr = __builtin_bswap64(meta_ro.baseMethods_ptr);
                }
                
                class_info->class_method_count = parse_method_list(ctx, meta_ro.baseMethods_ptr, &class_info->class_methods, true);
            }
        }
    }
    
    return true;
}

// MARK: - Public Functions

bool objc_has_runtime_data(MachOContext *ctx) {
    return find_section(ctx, "__DATA", "__objc_classlist") != NULL ||
           find_section(ctx, "__DATA_CONST", "__objc_classlist") != NULL;
}

int objc_get_class_count(MachOContext *ctx) {
    SectionInfo *classlist = find_section(ctx, "__DATA", "__objc_classlist");
    if (!classlist) {
        classlist = find_section(ctx, "__DATA_CONST", "__objc_classlist");
    }
    
    if (!classlist) return 0;
    
    return (int)(classlist->size / sizeof(uint64_t));
}

ObjCRuntimeInfo* objc_parse_runtime(MachOContext *ctx) {
    if (!ctx || !objc_has_runtime_data(ctx)) {
        return NULL;
    }
    
    printf("Parsing Objective-C runtime...\n");
    
    SectionInfo *classlist = find_section(ctx, "__DATA", "__objc_classlist");
    if (!classlist) {
        classlist = find_section(ctx, "__DATA_CONST", "__objc_classlist");
    }
    
    if (!classlist) {
        printf("   No __objc_classlist section found\n");
        return NULL;
    }
    
    int class_count = (int)(classlist->size / sizeof(uint64_t));
    printf("   Found %d classes\n", class_count);
    
    if (class_count == 0 || class_count > 10000) {
        return NULL;
    }
    
    ObjCRuntimeInfo *runtime = calloc(1, sizeof(ObjCRuntimeInfo));
    if (!runtime) return NULL;
    
    runtime->classes = calloc(class_count, sizeof(ObjCClassInfo));
    if (!runtime->classes) {
        free(runtime);
        return NULL;
    }
    
    int parsed_count = 0;
    for (int i = 0; i < class_count; i++) {
        uint64_t class_ptr_offset = classlist->offset + (i * sizeof(uint64_t));
        uint64_t class_vm_addr = read_ptr_at_offset(ctx, class_ptr_offset);
        
        if (is_valid_address(ctx, class_vm_addr)) {
            if (parse_class(ctx, class_vm_addr, &runtime->classes[parsed_count])) {
                parsed_count++;
            }
        }
    }
    
    runtime->class_count = parsed_count;
    
    SectionInfo *cat_sect = find_section(ctx, "__DATA_CONST", "__objc_catlist");
    if (!cat_sect) {
        cat_sect = find_section(ctx, "__DATA", "__objc_catlist");
    }
    
    runtime->category_count = 0;
    runtime->categories = NULL;
    
    if (cat_sect && cat_sect->size > 0) {
        int cat_count = (int)(cat_sect->size / sizeof(uint64_t));
        if (cat_count > 0 && cat_count < 10000) {
            printf("   Found %d categories\n", cat_count);
            
            runtime->categories = calloc(cat_count, sizeof(ObjCCategoryInfo));
            if (runtime->categories) {
                int parsed_cat_count = 0;
                
                for (int i = 0; i < cat_count; i++) {
                    uint64_t cat_ptr_offset = cat_sect->offset + (i * sizeof(uint64_t));
                    uint64_t cat_vm_addr = read_ptr_at_offset(ctx, cat_ptr_offset);
                    
                    if (is_valid_address(ctx, cat_vm_addr)) {
                        if (parse_category(ctx, cat_vm_addr, &runtime->categories[parsed_cat_count])) {
                            parsed_cat_count++;
                        }
                    }
                }
                
                runtime->category_count = parsed_cat_count;
                printf("   ✅ Successfully parsed %d categories\n", parsed_cat_count);
            }
        }
    }
    
    runtime->protocol_count = 0;
    runtime->protocols = NULL;
    
    printf("   ✅ Successfully parsed %d classes\n", parsed_count);
    
    return runtime;
}

void objc_free_runtime_info(ObjCRuntimeInfo *info) {
    if (!info) return;
    
    if (info->classes) {
        for (int i = 0; i < info->class_count; i++) {
            free(info->classes[i].instance_methods);
            free(info->classes[i].class_methods);
            free(info->classes[i].properties);
            free(info->classes[i].ivars);
            
            if (info->classes[i].protocols) {
                for (int j = 0; j < info->classes[i].protocol_count; j++) {
                    free(info->classes[i].protocols[j]);
                }
                free(info->classes[i].protocols);
            }
        }
        free(info->classes);
    }
    
    if (info->categories) {
        for (int i = 0; i < info->category_count; i++) {
            free(info->categories[i].instance_methods);
            free(info->categories[i].class_methods);
            free(info->categories[i].properties);
            
            if (info->categories[i].protocols) {
                for (int j = 0; j < info->categories[i].protocol_count; j++) {
                    free(info->categories[i].protocols[j]);
                }
                free(info->categories[i].protocols);
            }
        }
        free(info->categories);
    }
    
    if (info->protocols) {
        for (int i = 0; i < info->protocol_count; i++) {
            free(info->protocols[i].methods);
        }
        free(info->protocols);
    }
    
    free(info);
}

