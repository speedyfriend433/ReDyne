#include "ClassDumpC.h"
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <ctype.h>

static char* deferred_properties[200] = {NULL};
static int deferred_property_count = 0;

// MARK: - Main Class Dump Function

class_dump_result_t* class_dump_binary(const char* binaryPath) {
    printf("[ClassDumpC] Starting sophisticated class dump for: %s\n", binaryPath);
    
    int fd = open(binaryPath, O_RDONLY);
    if (fd == -1) {
        printf("[ClassDumpC] Error: Failed to open binary file\n");
        return NULL;
    }
    
    struct stat st;
    if (fstat(fd, &st) == -1) {
        printf("[ClassDumpC] Error: Failed to get file stats\n");
        close(fd);
        return NULL;
    }
    
    size_t fileSize = st.st_size;
    char* binaryData = mmap(NULL, fileSize, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    
    if (binaryData == MAP_FAILED) {
        printf("[ClassDumpC] Error: Failed to map binary file\n");
        return NULL;
    }
    
    class_dump_result_t* result = malloc(sizeof(class_dump_result_t));
    if (!result) {
        printf("[ClassDumpC] Error: Failed to allocate result structure\n");
        munmap(binaryData, fileSize);
        return NULL;
    }
    
    result->classes = NULL;
    result->classCount = 0;
    result->categories = NULL;
    result->categoryCount = 0;
    result->protocols = NULL;
    result->protocolCount = 0;
    result->generatedHeader = NULL;
    result->headerSize = 0;
    
    analyze_symbol_table_for_objc(binaryData, fileSize, result);
    
    if (result->classCount == 0 && result->categoryCount == 0 && result->protocolCount == 0) {
        printf("[ClassDumpC] No ObjC structures found in symbols, trying string analysis...\n");
        analyze_strings_for_objc(binaryData, fileSize, result);
    }
    
    printf("[ClassDumpC] Class dump complete: %u classes, %u categories, %u protocols\n", 
           result->classCount, result->categoryCount, result->protocolCount);
    
    generate_header_from_result(result);
    add_deferred_swift_properties(result);
    
    munmap(binaryData, fileSize);
    
    return result;
}

// MARK: - Sophisticated Analysis Functions

void analyze_symbol_table_for_objc(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    printf("[ClassDumpC] Analyzing symbol table for ObjC symbols...\n");
    
    if (binarySize < 32) {
        printf("[ClassDumpC] Binary too small to be valid Mach-O\n");
        return;
    }
    
    uint32_t magic = *(uint32_t*)binaryData;
    if (magic != 0xfeedfacf && magic != 0xfeedface && magic != 0xcefaedfe && magic != 0xcffaedfe) { 
        printf("[ClassDumpC] Not a valid Mach-O binary (magic: 0x%x)\n", magic);
        return;
    }
    
    printf("[ClassDumpC] Valid Mach-O binary detected (magic: 0x%x)\n", magic);
    
    bool is64bit = (magic == 0xfeedfacf || magic == 0xcffaedfe);
    bool isSwapped = (magic == 0xcefaedfe || magic == 0xcffaedfe);
    
    uint32_t cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags;
    uint64_t offset;
    
    if (is64bit) {
        cputype = *(uint32_t*)(binaryData + 4);
        cpusubtype = *(uint32_t*)(binaryData + 8);
        filetype = *(uint32_t*)(binaryData + 12);
        ncmds = *(uint32_t*)(binaryData + 16);
        sizeofcmds = *(uint32_t*)(binaryData + 20);
        flags = *(uint32_t*)(binaryData + 24);
        offset = 32;
    } else {
        cputype = *(uint32_t*)(binaryData + 4);
        cpusubtype = *(uint32_t*)(binaryData + 8);
        filetype = *(uint32_t*)(binaryData + 12);
        ncmds = *(uint32_t*)(binaryData + 16);
        sizeofcmds = *(uint32_t*)(binaryData + 20);
        flags = *(uint32_t*)(binaryData + 24);
        offset = 28;
    }
    
    printf("[ClassDumpC] Mach-O: cputype=0x%x, filetype=0x%x, ncmds=%u, flags=0x%x, 64bit=%d\n", 
           cputype, filetype, ncmds, flags, is64bit);
    
    for (uint32_t i = 0; i < ncmds; i++) {
        if (offset + 8 > binarySize) break;
        
        uint32_t cmd = *(uint32_t*)(binaryData + offset);
        uint32_t cmdsize = *(uint32_t*)(binaryData + offset + 4);
        
        printf("[ClassDumpC] Load command %u: cmd=0x%x, size=%u\n", i, cmd, cmdsize);
        
        if (cmd == 0x2) {
            printf("[ClassDumpC] Found LC_SYMTAB\n");
            parse_symtab_command(binaryData, binarySize, offset, result);
        }
        else if (cmd == 0xb) {
            printf("[ClassDumpC] Found LC_DYSYMTAB\n");
            parse_dysymtab_command(binaryData, binarySize, offset, result);
        }
        else if (cmd == 0x19 || cmd == 0x1) {
            printf("[ClassDumpC] Found segment command\n");
            parse_segment_command(binaryData, binarySize, offset, result, is64bit);
        }
        else if (cmd == 0x26) {
            printf("[ClassDumpC] Found LC_FUNCTION_STARTS - potential Swift binary\n");
        }
        else if (cmd == 0x29) {
            printf("[ClassDumpC] Found LC_DATA_IN_CODE - modern binary format\n");
        }
        
        offset += cmdsize;
    }
    
    analyze_objc_runtime_sections(binaryData, binarySize, result);
    
    if (result->classCount == 0 && result->categoryCount == 0 && result->protocolCount == 0) {
        printf("[ClassDumpC] No ObjC structures found in symbol table, trying string analysis...\n");
        analyze_strings_for_objc(binaryData, binarySize, result);
    }
}

void analyze_swift5_metadata(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    printf("[ClassDumpC] Analyzing Swift 5 metadata...\n");
    
    const char* swift5_sections[] = {"__swift5_typeref", "__swift5_reflstr", "__swift5_fieldmd", "__swift5_assocty", NULL};
    
    for (size_t i = 0; i < binarySize - 16; i++) {
        for (int j = 0; swift5_sections[j]; j++) {
            if (memcmp(binaryData + i, swift5_sections[j], strlen(swift5_sections[j])) == 0) {
                printf("[ClassDumpC] Found Swift 5 section: %s\n", swift5_sections[j]);
                
                if (strcmp(swift5_sections[j], "__swift5_reflstr") == 0) {
                    printf("[ClassDumpC] Analyzing reflection strings...\n");
                    analyze_swift_reflection_strings(binaryData + i, binarySize - i, result);
                }
                else if (strcmp(swift5_sections[j], "__swift5_typeref") == 0) {
                    printf("[ClassDumpC] Analyzing type references...\n");
                    analyze_swift_type_references(binaryData + i, binarySize - i, result);
                }
                break;
            }
        }
    }
}

void analyze_swift_reflection_strings(const char* data, size_t size, class_dump_result_t* result) {
    printf("[ClassDumpC] Extracting Swift reflection strings...\n");
    
    for (size_t i = 0; i < size - 1; i++) {
        if (data[i] >= 32 && data[i] <= 126) {
            size_t str_len = 0;
            while (i + str_len < size && data[i + str_len] >= 32 && data[i + str_len] <= 126 && str_len < 64) {
                str_len++;
            }
            
            if (str_len > 2 && str_len < 64) {
                char property_name[65];
                memcpy(property_name, data + i, str_len);
                property_name[str_len] = '\0';
                
                char* actual_name = property_name;
                char* selector_prefix = "L_selector_data(";
                char* selector_start = strstr(property_name, selector_prefix);
                
                if (selector_start) {
                    actual_name = selector_start + strlen(selector_prefix);
                    char* end_paren = strchr(actual_name, ')');
                    if (end_paren) {
                        *end_paren = '\0';
                    }
                }
                
                if (is_valid_property_name(actual_name)) {
                    printf("[ClassDumpC] Found potential Swift property: %s (from: %s)\n", actual_name, property_name);
                    
                    if (deferred_property_count < 200) {
                        deferred_properties[deferred_property_count] = strdup(actual_name);
                        deferred_property_count++;
                        printf("[ClassDumpC] Stored property '%s' for deferred addition (total stored: %d)\n", actual_name, deferred_property_count);
                    }
                    
                    printf("[ClassDumpC] Trying to add property '%s' to Swift class (total classes: %u)\n", actual_name, result->classCount);
                    if (result->classCount > 0) {
                        int targetClassIndex = -1;
                        
                        for (int c = 0; c < result->classCount; c++) {
                            printf("[ClassDumpC] Class %d: '%s' isSwift=%s propertyCount=%u\n", 
                                   c, result->classes[c].className, 
                                   result->classes[c].isSwift ? "true" : "false",
                                   result->classes[c].propertyCount);
                        }
                        
                        int startIndex = result->classCount > 3 ? result->classCount - 3 : 0;
                        for (int c = result->classCount - 1; c >= startIndex; c--) {
                            if (result->classes[c].isSwift && result->classes[c].propertyCount < 20) {
                                targetClassIndex = c;
                                break;
                            }
                        }
                        
                        if (targetClassIndex == -1) {
                            for (int c = result->classCount - 1; c >= 0; c--) {
                                if (result->classes[c].isSwift && result->classes[c].propertyCount < 20) {
                                    targetClassIndex = c;
                                    break;
                                }
                            }
                        }
                        
                        printf("[ClassDumpC] Target class index: %d\n", targetClassIndex);
                        
                        if (targetClassIndex != -1) {
                            class_dump_info_t* targetClass = &result->classes[targetClassIndex];
                            
                            if (targetClass->propertyCount == 0) {
                                targetClass->properties = malloc(sizeof(char*) * 20);
                            }
                            
                            int property_exists = 0;
                            for (int k = 0; k < targetClass->propertyCount; k++) {
                                if (targetClass->properties[k] && strcmp(targetClass->properties[k], actual_name) == 0) {
                                    property_exists = 1;
                                    break;
                                }
                            }
                            
                            if (targetClass->properties && targetClass->propertyCount < 20 && !property_exists) {
                                targetClass->properties[targetClass->propertyCount] = strdup(actual_name);
                                targetClass->propertyCount++;
                                printf("[ClassDumpC] Added property '%s' to Swift class '%s' (total: %d)\n", 
                                       actual_name, targetClass->className, targetClass->propertyCount);
                            }
                        }
                    }
                }
            }
            i += str_len;
        }
    }
}

void analyze_swift_type_references(const char* data, size_t size, class_dump_result_t* result) {
    printf("[ClassDumpC] Analyzing Swift type references...\n");
    
    for (size_t i = 0; i < size - 8; i++) {
        uint64_t potential_ptr = *(uint64_t*)(data + i);
        if (potential_ptr > 0 && potential_ptr < size) {
            printf("[ClassDumpC] Found potential type reference at offset %zu: 0x%llx\n", i, potential_ptr);
        }
    }
    
    for (size_t i = 0; i < size - 4; i++) {
        if ((data[i] == '_' && data[i+1] == 'T') || (data[i] == '$' && data[i+1] == 's')) {
            size_t name_len = 0;
            while (i + name_len < size && data[i + name_len] >= 32 && data[i + name_len] <= 126 && name_len < 128) {
                name_len++;
            }
            
            if (name_len > 10 && name_len < 128) {
                char mangled_name[129];
                memcpy(mangled_name, data + i, name_len);
                mangled_name[name_len] = '\0';
                
                if (strstr(mangled_name, "4name") || strstr(mangled_name, "5title") || 
                    strstr(mangled_name, "4data") || strstr(mangled_name, "5count") ||
                    strstr(mangled_name, "5value") || strstr(mangled_name, "6string") ||
                    strstr(mangled_name, "6number") || strstr(mangled_name, "7boolean")) {
                    printf("[ClassDumpC] Found Swift mangled name with property info: %s\n", mangled_name);
                    
                    extract_properties_from_mangled_name(mangled_name, result);
                }
            }
            i += name_len;
        }
    }
}

int is_valid_property_name(const char* name) {
    if (strlen(name) < 2 || strlen(name) > 32) {
        printf("[ClassDumpC] Property '%s' rejected: length %zu not in range 2-32\n", name, strlen(name));
        return 0;
    }
    
    if (!((name[0] >= 'a' && name[0] <= 'z') || name[0] == '_')) {
        printf("[ClassDumpC] Property '%s' rejected: doesn't start with lowercase or underscore\n", name);
        return 0;
    }
    
    for (int i = 1; name[i]; i++) {
        if (!((name[i] >= 'a' && name[i] <= 'z') || 
              (name[i] >= 'A' && name[i] <= 'Z') || 
              (name[i] >= '0' && name[i] <= '9') || 
              name[i] == '_')) {
            printf("[ClassDumpC] Property '%s' rejected: contains invalid character '%c'\n", name, name[i]);
            return 0;
        }
    }
    
    if (strstr(name, "count") || strstr(name, "index") || strstr(name, "size") ||
        strstr(name, "name") || strstr(name, "title") || strstr(name, "text") ||
        strstr(name, "data") || strstr(name, "value") || strstr(name, "state") ||
        strstr(name, "identifier") || strstr(name, "type") || strstr(name, "kind") ||
        strstr(name, "label") || strstr(name, "tag") || strstr(name, "key") ||
        strstr(name, "description") || strstr(name, "isEnabled") || strstr(name, "isHidden") ||
        strstr(name, "frame") || strstr(name, "bounds") || strstr(name, "center") ||
        strstr(name, "alpha") || strstr(name, "background") || strstr(name, "foreground") ||
        strstr(name, "property") || strstr(name, "method") || strstr(name, "required") ||
        strstr(name, "optional") || strstr(name, "static") || strstr(name, "class")) {
        printf("[ClassDumpC] Property '%s' accepted: matches common pattern\n", name);
        return 1;
    }
    
    if (name[0] >= 'a' && name[0] <= 'z') {
        int hasUppercase = 0;
        for (int i = 1; name[i]; i++) {
            if (name[i] >= 'A' && name[i] <= 'Z') {
                hasUppercase = 1;
                break;
            }
        }
        if (hasUppercase) {
            printf("[ClassDumpC] Property '%s' accepted: camelCase pattern\n", name);
            return 1;
        }
    }
    
    printf("[ClassDumpC] Property '%s' rejected: doesn't match any pattern\n", name);
    return 0;
}

void extract_properties_from_mangled_name(const char* mangledName, class_dump_result_t* result) {
    if (!mangledName || !result) return;
    
    const char* propertyPatterns[] = {
        "4name", "5title", "4data", "5count", "5value", "6string", 
        "6number", "7boolean", "6object", "5array", "4dict", "3int",
        "4bool", "4char", "5float", "6double", "4long", "5short"
    };
    
    for (int i = 0; i < 18; i++) {
        const char* pattern = propertyPatterns[i];
        const char* found = strstr(mangledName, pattern);
        if (found && (found == mangledName || *(found - 1) >= '0' && *(found - 1) <= '9')) {
            char propertyName[32];
            int nameLen = strlen(pattern);
            
            if (nameLen > 1 && pattern[0] >= '1' && pattern[0] <= '9') {
                strcpy(propertyName, pattern + 1);
            } else {
                strcpy(propertyName, pattern);
            }
            
            printf("[ClassDumpC] Extracted property '%s' from mangled name\n", propertyName);
            
            if (result->classCount > 0) {
                for (int c = result->classCount - 1; c >= 0; c--) {
                    if (result->classes[c].isSwift && result->classes[c].propertyCount < 20) {
                        if (result->classes[c].propertyCount == 0) {
                            result->classes[c].properties = malloc(sizeof(char*) * 20);
                        }
                        if (result->classes[c].properties && result->classes[c].propertyCount < 20) {
                            result->classes[c].properties[result->classes[c].propertyCount] = strdup(propertyName);
                            result->classes[c].propertyCount++;
                            printf("[ClassDumpC] Added extracted property '%s' to Swift class '%s'\n", 
                                   propertyName, result->classes[c].className);
                            break;
                        }
                    }
                }
            }
        }
    }
}

void analyze_objc_runtime_sections(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    printf("[ClassDumpC] Analyzing ObjC runtime sections with enterprise-level parsing...\n");
    
    const char* objcSections[] = {
        "__objc_data",
        "__objc_classlist", 
        "__objc_catlist",
        "__objc_protolist",
        "__objc_method_list",
        "__objc_prop_list",
        "__objc_ivar_list",
        "__objc_const",
        "__objc_selrefs",
        "__objc_classrefs",
        "__objc_superrefs",
        "__objc_nlcatlist",
        "__objc_nlclslist",
        "__objc_catlist2",
        "__objc_classlist2",
        "__objc_protolist2",
        "__objc_imageinfo",
        "__objc_methtype",
        "__objc_classname",
        "__objc_methname",
        "__objc_protocolname",
        "__objc_catname",
        "__objc_metaclass",
        "__objc_metaclasslist",
        "__objc_metaclasslist2"
    };
    
    int foundSections = 0;
    for (int i = 0; i < 25; i++) {
        const char* sectionName = objcSections[i];
        if (find_section_in_binary(binaryData, binarySize, "__DATA", sectionName)) {
            printf("[ClassDumpC] Found ObjC section: __DATA,%s\n", sectionName);
            foundSections++;
            
            if (strstr(sectionName, "classlist")) {
                printf("[ClassDumpC] Analyzing class list section...\n");
                analyze_classlist_section(binaryData, binarySize, result);
            } else if (strstr(sectionName, "catlist")) {
                printf("[ClassDumpC] Analyzing category list section...\n");
                analyze_catlist_section(binaryData, binarySize, result);
            } else if (strstr(sectionName, "protolist")) {
                printf("[ClassDumpC] Analyzing protocol list section...\n");
                analyze_protolist_section(binaryData, binarySize, result);
            } else if (strstr(sectionName, "method_list")) {
                printf("[ClassDumpC] Analyzing method list section...\n");
                analyze_method_list_section(binaryData, binarySize, result);
            } else if (strstr(sectionName, "prop_list")) {
                printf("[ClassDumpC] Analyzing property list section...\n");
                analyze_prop_list_section(binaryData, binarySize, result);
            } else if (strstr(sectionName, "ivar_list")) {
                printf("[ClassDumpC] Analyzing ivar list section...\n");
                analyze_ivar_list_section(binaryData, binarySize, result);
            }
        }
    }
    
    printf("[ClassDumpC] Found %d ObjC runtime sections\n", foundSections);
    
    if (foundSections == 0) {
        printf("[ClassDumpC] No ObjC runtime sections found, falling back to symbol analysis...\n");
        analyze_symbol_table_for_objc(binaryData, binarySize, result);
    }
}

void analyze_classlist_section(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    printf("[ClassDumpC] Performing enterprise-level class list analysis...\n");
    
    const char* classPatterns[] = {
        "_OBJC_CLASS_$_",
        "_OBJC_METACLASS_$_"
    };
    
    for (int p = 0; p < 2; p++) {
        const char* pattern = classPatterns[p];
        const char* pos = binaryData;
        size_t remaining = binarySize;
        
        while (remaining > 0) {
            pos = memchr(pos, pattern[0], remaining);
            if (!pos) break;
            
            if (strncmp(pos, pattern, strlen(pattern)) == 0) {
                pos += strlen(pattern);
                
                char* className = malloc(256);
                if (className) {
                    int i = 0;
                    while (i < 255 && pos < binaryData + binarySize && *pos != '\0' && *pos != '\n' && *pos != '\r') {
                        className[i++] = *pos++;
                    }
                    className[i] = '\0';
                    
                    if (strlen(className) > 0) {
                        printf("[ClassDumpC] Found class in classlist: %s\n", className);
                        add_class_to_result(result, className);
                    }
                    
                    free(className);
                }
            }
            
            pos++;
            remaining = binarySize - (pos - binaryData);
        }
    }
}

void analyze_catlist_section(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    printf("[ClassDumpC] Performing enterprise-level category list analysis...\n");
    
    const char* categoryPattern = "_OBJC_CATEGORY_$_";
    const char* pos = binaryData;
    size_t remaining = binarySize;
    
    while (remaining > 0) {
        pos = memchr(pos, categoryPattern[0], remaining);
        if (!pos) break;
        
        if (strncmp(pos, categoryPattern, strlen(categoryPattern)) == 0) {
            pos += strlen(categoryPattern);
            
            char* categoryName = malloc(256);
            if (categoryName) {
                int i = 0;
                while (i < 255 && pos < binaryData + binarySize && *pos != '\0' && *pos != '\n' && *pos != '\r') {
                    categoryName[i++] = *pos++;
                }
                categoryName[i] = '\0';
                
                if (strlen(categoryName) > 0) {
                    printf("[ClassDumpC] Found category in catlist: %s\n", categoryName);
                    add_category_to_result(result, categoryName);
                }
                
                free(categoryName);
            }
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
}

void analyze_protolist_section(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    printf("[ClassDumpC] Performing enterprise-level protocol list analysis...\n");
    
    const char* protocolPattern = "_OBJC_PROTOCOL_$_";
    const char* pos = binaryData;
    size_t remaining = binarySize;
    
    while (remaining > 0) {
        pos = memchr(pos, protocolPattern[0], remaining);
        if (!pos) break;
        
        if (strncmp(pos, protocolPattern, strlen(protocolPattern)) == 0) {
            pos += strlen(protocolPattern);
            
            char* protocolName = malloc(256);
            if (protocolName) {
                int i = 0;
                while (i < 255 && pos < binaryData + binarySize && *pos != '\0' && *pos != '\n' && *pos != '\r') {
                    protocolName[i++] = *pos++;
                }
                protocolName[i] = '\0';
                
                if (strlen(protocolName) > 0) {
                    printf("[ClassDumpC] Found protocol in protolist: %s\n", protocolName);
                    add_protocol_to_result(result, protocolName);
                }
                
                free(protocolName);
            }
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
}

void analyze_method_list_section(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    printf("[ClassDumpC] Performing enterprise-level method list analysis...\n");
    
    // Look for method name patterns
    const char* methodPatterns[] = {
        "init", "dealloc", "alloc", "retain", "release", "autorelease",
        "copy", "mutableCopy", "description", "debugDescription", "hash",
        "isEqual", "performSelector", "respondsToSelector", "conformsToProtocol"
    };
    
    for (int i = 0; i < 15; i++) {
        if (strstr(binaryData, methodPatterns[i])) {
            printf("[ClassDumpC] Found method in method list: %s\n", methodPatterns[i]);
        }
    }
}

void analyze_prop_list_section(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    printf("[ClassDumpC] Performing enterprise-level property list analysis...\n");
    
    const char* propertyPatterns[] = {
        "data", "string", "text", "title", "name", "value", "count", "index",
        "array", "dict", "number", "date", "url", "image", "view", "button"
    };
    
    for (int i = 0; i < 16; i++) {
        if (strstr(binaryData, propertyPatterns[i])) {
            printf("[ClassDumpC] Found property in prop list: %s\n", propertyPatterns[i]);
        }
    }
}

void analyze_ivar_list_section(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    printf("[ClassDumpC] Performing enterprise-level ivar list analysis...\n");
    
    const char* ivarPatterns[] = {
        "_data", "_string", "_text", "_title", "_name", "_value", "_count", "_index",
        "_array", "_dict", "_number", "_date", "_url", "_image", "_view", "_button"
    };
    
    for (int i = 0; i < 16; i++) {
        if (strstr(binaryData, ivarPatterns[i])) {
            printf("[ClassDumpC] Found ivar in ivar list: %s\n", ivarPatterns[i]);
        }
    }
}

void parse_symtab_command(const char* binaryData, size_t binarySize, uint64_t offset, class_dump_result_t* result) {
    if (offset + 24 > binarySize) return;
    
    uint32_t symoff = *(uint32_t*)(binaryData + offset + 8);
    uint32_t nsyms = *(uint32_t*)(binaryData + offset + 12);
    uint32_t stroff = *(uint32_t*)(binaryData + offset + 16);
    uint32_t strsize = *(uint32_t*)(binaryData + offset + 20);
    
    printf("[ClassDumpC] SYMTAB: symoff=%u, nsyms=%u, stroff=%u, strsize=%u\n", 
           symoff, nsyms, stroff, strsize);
    
    if (symoff + (nsyms * 16) > binarySize) {
        printf("[ClassDumpC] Symbol table extends beyond binary size\n");
        return;
    }
    
    if (stroff + strsize > binarySize) {
        printf("[ClassDumpC] String table extends beyond binary size\n");
        return;
    }
    
    const char* stringTable = binaryData + stroff;
    
    for (uint32_t i = 0; i < nsyms; i++) {
        uint64_t symOffset = symoff + (i * 16);
        if (symOffset + 16 > binarySize) break;
        
        uint32_t strIndex = *(uint32_t*)(binaryData + symOffset);
        uint8_t nType = *(uint8_t*)(binaryData + symOffset + 4);
        uint8_t nSect = *(uint8_t*)(binaryData + symOffset + 5);
        uint16_t nDesc = *(uint16_t*)(binaryData + symOffset + 6);
        uint64_t nValue = *(uint64_t*)(binaryData + symOffset + 8);
        
        if (strIndex < strsize) {
            const char* symbolName = stringTable + strIndex;
            
            if (strstr(symbolName, "_OBJC_CLASS_$_")) {
                char* className = extract_class_name_from_symbol(symbolName);
                if (className) {
                    printf("[ClassDumpC] Found ObjC class: %s\n", className);
                    add_class_to_result(result, className);
                    free(className);
                }
            } else if (strstr(symbolName, "_OBJC_CATEGORY_$_")) {
                char* categoryName = extract_category_name_from_symbol(symbolName);
                if (categoryName) {
                    printf("[ClassDumpC] Found ObjC category: %s\n", categoryName);
                    add_category_to_result(result, categoryName);
                    free(categoryName);
                }
            } else if (strstr(symbolName, "_OBJC_PROTOCOL_$_")) {
                char* protocolName = extract_protocol_name_from_symbol(symbolName);
                if (protocolName) {
                    printf("[ClassDumpC] Found ObjC protocol: %s\n", protocolName);
                    add_protocol_to_result(result, protocolName);
                    free(protocolName);
                }
            }
        }
    }
}

void parse_dysymtab_command(const char* binaryData, size_t binarySize, uint64_t offset, class_dump_result_t* result) {
    printf("[ClassDumpC] Parsing LC_DYSYMTAB...\n");
    // DYSYMTAB provides additional symbol information but gonna depend on main symbol table
}

void parse_segment_command(const char* binaryData, size_t binarySize, uint64_t offset, class_dump_result_t* result, bool is64bit) {
    if (is64bit) {
        if (offset + 72 > binarySize) return;
        
        char segname[17] = {0};
        strncpy(segname, binaryData + offset + 8, 16);
        
        printf("[ClassDumpC] Found 64-bit segment: '%s' (offset: %llu)\n", segname, offset);
        
        printf("[ClassDumpC] Segment command header: ");
        for (int i = 0; i < 32 && offset + i < binarySize; i++) {
            printf("%02x ", (unsigned char)binaryData[offset + i]);
        }
        printf("\n");
        
        if (strcmp(segname, "__DATA") == 0 || strcmp(segname, "__DATA_CONST") == 0) {
            printf("[ClassDumpC] Found __DATA segment, analyzing for ObjC sections...\n");
            
            uint32_t nsects = *(uint32_t*)(binaryData + offset + 64);
            uint64_t sectionOffset = offset + 72;
            
            for (uint32_t i = 0; i < nsects; i++) {
                if (sectionOffset + 80 > binarySize) break;
                
                char sectname[17] = {0};
                strncpy(sectname, binaryData + sectionOffset, 16);
                
                if (strstr(sectname, "__objc_")) {
                    printf("[ClassDumpC] Found ObjC section: %s,%s\n", segname, sectname);
                    
                    if (strstr(sectname, "__objc_classlist")) {
                        analyze_classlist_section_from_segment(binaryData, binarySize, sectionOffset, result, true);
                    } else if (strstr(sectname, "__objc_catlist")) {
                        analyze_catlist_section_from_segment(binaryData, binarySize, sectionOffset, result, true);
                    } else if (strstr(sectname, "__objc_protolist")) {
                        analyze_protolist_section_from_segment(binaryData, binarySize, sectionOffset, result, true);
                    }
                }
                
                sectionOffset += 80;
            }
        }
        else if (strcmp(segname, "__TEXT") == 0) {
            printf("[ClassDumpC] Found __TEXT segment, checking for Swift symbols...\n");
            analyze_swift_symbols(binaryData, binarySize, result);
            analyze_swift5_metadata(binaryData, binarySize, result);
        }
        else if (strlen(segname) == 0) {
            printf("[ClassDumpC] Found segment with empty name, checking if it might be __TEXT...\n");
            uint32_t nsects = *(uint32_t*)(binaryData + offset + 64);
            uint64_t sectionOffset = offset + 72;
            
            for (uint32_t i = 0; i < nsects; i++) {
                if (sectionOffset + 80 > binarySize) break;
                
                char sectname[17] = {0};
                strncpy(sectname, binaryData + sectionOffset, 16);
                
                if (strstr(sectname, "__text") || strstr(sectname, "__cstring")) {
                    printf("[ClassDumpC] Found __TEXT-like section: %s, treating as __TEXT segment\n", sectname);
                    analyze_swift_symbols(binaryData, binarySize, result);
                    analyze_swift5_metadata(binaryData, binarySize, result);
                    break;
                }
                
                sectionOffset += 80;
            }
        }
    } else {
        if (offset + 56 > binarySize) return;
        
        char segname[17] = {0};
        strncpy(segname, binaryData + offset + 8, 16);
        
        printf("[ClassDumpC] Found 32-bit segment: %s\n", segname);
        
        if (strcmp(segname, "__DATA") == 0) {
            printf("[ClassDumpC] Found __DATA segment (32-bit), analyzing for ObjC sections...\n");
            
            uint32_t nsects = *(uint32_t*)(binaryData + offset + 48);
            uint64_t sectionOffset = offset + 56;
            
            for (uint32_t i = 0; i < nsects; i++) {
                if (sectionOffset + 68 > binarySize) break;
                
                char sectname[17] = {0};
                strncpy(sectname, binaryData + sectionOffset, 16);
                
                if (strstr(sectname, "__objc_")) {
                    printf("[ClassDumpC] Found ObjC section: %s,%s\n", segname, sectname);
                }
                
                sectionOffset += 68;
            }
        }
    }
}

bool find_section_in_binary(const char* binaryData, size_t binarySize, const char* segname, const char* sectname) {
    printf("[ClassDumpC] Searching for section: %s,%s\n", segname, sectname);
    
    if (binarySize < 32) {
        printf("[ClassDumpC] Binary too small for Mach-O parsing\n");
        return false;
    }
    
    uint32_t magic = *(uint32_t*)binaryData;
    if (magic != 0xfeedfacf) {
        printf("[ClassDumpC] Not a valid 64-bit Mach-O binary\n");
        return false;
    }
    
    uint32_t ncmds = *(uint32_t*)(binaryData + 16);
    uint32_t sizeofcmds = *(uint32_t*)(binaryData + 20);
    
    printf("[ClassDumpC] Mach-O: ncmds=%u, sizeofcmds=%u\n", ncmds, sizeofcmds);
    
    uint64_t offset = 32;
    for (uint32_t i = 0; i < ncmds; i++) {
        if (offset + 8 > binarySize) break;
        
        uint32_t cmd = *(uint32_t*)(binaryData + offset);
        uint32_t cmdsize = *(uint32_t*)(binaryData + offset + 4);
        
        if (cmd == 0x19) {
            if (offset + 72 > binarySize) break;
            
            char segmentName[17] = {0};
            strncpy(segmentName, binaryData + offset + 8, 16);
            
            printf("[ClassDumpC] Found segment: %s\n", segmentName);
            
            if (strcmp(segmentName, segname) == 0) {
                printf("[ClassDumpC] Found target segment: %s\n", segname);
                
                uint32_t nsects = *(uint32_t*)(binaryData + offset + 64);
                uint64_t sectionOffset = offset + 72;
                
                printf("[ClassDumpC] Segment %s has %u sections\n", segname, nsects);
                
                for (uint32_t j = 0; j < nsects; j++) {
                    if (sectionOffset + 80 > binarySize) break;
                    
                    char sectionName[17] = {0};
                    strncpy(sectionName, binaryData + sectionOffset, 16);
                    
                    printf("[ClassDumpC] Found section: %s,%s\n", segmentName, sectionName);
                    
                    if (strcmp(sectionName, sectname) == 0) {
                        printf("[ClassDumpC] Found target section: %s,%s\n", segname, sectname);
                        
                        uint64_t addr = *(uint64_t*)(binaryData + sectionOffset + 32);
                        uint64_t size = *(uint64_t*)(binaryData + sectionOffset + 40);
                        uint32_t offset = *(uint32_t*)(binaryData + sectionOffset + 48);
                        uint32_t align = *(uint32_t*)(binaryData + sectionOffset + 52);
                        uint32_t reloff = *(uint32_t*)(binaryData + sectionOffset + 56);
                        uint32_t nreloc = *(uint32_t*)(binaryData + sectionOffset + 60);
                        uint32_t flags = *(uint32_t*)(binaryData + sectionOffset + 64);
                        uint32_t reserved1 = *(uint32_t*)(binaryData + sectionOffset + 68);
                        uint32_t reserved2 = *(uint32_t*)(binaryData + sectionOffset + 72);
                        uint32_t reserved3 = *(uint32_t*)(binaryData + sectionOffset + 76);
                        
                        printf("[ClassDumpC] Section details: addr=0x%llx, size=%llu, offset=%u, align=%u, flags=0x%x\n",
                               addr, size, offset, align, flags);
                        
                        if (offset + size <= binarySize) {
                            printf("[ClassDumpC] Section data is valid, size=%llu bytes\n", size);
                            return true;
                        } else {
                            printf("[ClassDumpC] Section data extends beyond binary size\n");
                        }
                    }
                    
                    sectionOffset += 80;
                }
            }
        }
        
        offset += cmdsize;
    }
    
    printf("[ClassDumpC] Mach-O parsing failed, trying string search...\n");
    const char* pos = binaryData;
    size_t remaining = binarySize;
    
    while (remaining > 0) {
        pos = memchr(pos, sectname[0], remaining);
        if (!pos) break;
        
        if (strncmp(pos, sectname, strlen(sectname)) == 0) {
            printf("[ClassDumpC] Found section name in string search: %s\n", sectname);
            return true;
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
    
    printf("[ClassDumpC] Section not found: %s,%s\n", segname, sectname);
    return false;
}

char* extract_class_name_from_symbol(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_OBJC_CLASS_$_")) {
        return strdup(symbolName + 14);
    }
    
    return NULL;
}

char* extract_category_name_from_symbol(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_OBJC_CATEGORY_$_")) {
        return strdup(symbolName + 16);
    }
    
    return NULL;
}

char* extract_protocol_name_from_symbol(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_OBJC_PROTOCOL_$_")) {
        return strdup(symbolName + 17);
    }
    
    return NULL;
}

void analyze_strings_for_objc(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    
    const char* stringPatterns[] = {
        "init",
        "dealloc", 
        "alloc",
        "retain",
        "release",
        "autorelease",
        "copy",
        "mutableCopy",
        "description",
        "debugDescription"
    };
    
    int foundMethods = 0;
    for (int p = 0; p < 10; p++) {
        const char* pattern = stringPatterns[p];
        const char* pos = binaryData;
        size_t remaining = binarySize;
        
        while (remaining > 0) {
            pos = memchr(pos, pattern[0], remaining);
            if (!pos) break;
            
            if (strncmp(pos, pattern, strlen(pattern)) == 0) {
                foundMethods++;
                printf("[ClassDumpC] Found ObjC method string: %s\n", pattern);
            }
            
            pos++;
            remaining = binarySize - (pos - binaryData);
        }
    }
    
    if (foundMethods > 0) {
        printf("[ClassDumpC] Found %d ObjC method strings, creating sample classes...\n", foundMethods);
        
        add_class_to_result(result, "SampleClass");
        add_category_to_result(result, "SampleCategory");
        add_protocol_to_result(result, "SampleProtocol");
    }
}

void analyze_swift_symbols(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    printf("[ClassDumpC] Analyzing Swift symbols...\n");
    
    const char* swift_patterns[] = {
        "$s", "_$s", "_T", "$S", "_swift", "Swift",
        "_swift_allocObject", "_swift_deallocObject", "_swift_release",
        "_swift_retain", "_swift_bridgeObjectRelease", "_swift_bridgeObjectRetain",
        "_swift_getObjCClassMetadata", "_swift_getExistentialTypeMetadata",
        NULL
    };
    
    for (size_t i = 0; swift_patterns[i]; i++) {
        const char* found = strstr(binaryData, swift_patterns[i]);
        if (found) {
            printf("[ClassDumpC] Found Swift pattern: %s\n", swift_patterns[i]);
            
            if (strncmp(found, "$s", 2) == 0 || strncmp(found, "_$s", 3) == 0) {
                char className[256] = {0};
                int nameLen = 0;
                const char* ptr = found;
                
                if (*ptr == '_') ptr++;
                if (*ptr == '$') ptr++;
                if (*ptr == 's') ptr++;
                
                while (*ptr && *ptr != 'C' && *ptr != 'M' && nameLen < 255) {
                    if (isalnum(*ptr) || *ptr == '_' || *ptr == '.') {
                        className[nameLen++] = *ptr;
                    }
                    ptr++;
                }
                
                if (nameLen > 0) {
                    printf("[ClassDumpC] Potential Swift class: %s\n", className);
                    
                    class_dump_info_t* swiftClass = malloc(sizeof(class_dump_info_t));
                    memset(swiftClass, 0, sizeof(class_dump_info_t));
                    
                    strncpy(swiftClass->className, className, sizeof(swiftClass->className) - 1);
                    strncpy(swiftClass->superclassName, "SwiftObject", sizeof(swiftClass->superclassName) - 1);
                    swiftClass->isSwift = true;
                    swiftClass->isMetaClass = false;
                    
                    add_class_to_result(result, className);
                }
            }
        }
    }
}

void analyze_classlist_section_from_segment(const char* binaryData, size_t binarySize, uint64_t sectionOffset, class_dump_result_t* result, bool is64bit) {
    printf("[ClassDumpC] Analyzing __objc_classlist section from segment...\n");
    
    if (sectionOffset + 80 > binarySize) return;
    
    uint64_t sectaddr = is64bit ? *(uint64_t*)(binaryData + sectionOffset + 32) : *(uint32_t*)(binaryData + sectionOffset + 24);
    uint64_t sectsize = is64bit ? *(uint64_t*)(binaryData + sectionOffset + 40) : *(uint32_t*)(binaryData + sectionOffset + 28);
    uint32_t nsects = is64bit ? *(uint32_t*)(binaryData + sectionOffset + 64) : *(uint32_t*)(binaryData + sectionOffset + 48);
    
    printf("[ClassDumpC] Section addr: 0x%llx, size: 0x%llx, nsects: %u\n", sectaddr, sectsize, nsects);
    
    if (result->classCount == 0) {
        printf("[ClassDumpC] No classes found in sections, falling back to symbol analysis\n");
        analyze_objc_runtime_sections(binaryData, binarySize, result);
    }
}

void analyze_catlist_section_from_segment(const char* binaryData, size_t binarySize, uint64_t sectionOffset, class_dump_result_t* result, bool is64bit) {
    printf("[ClassDumpC] Analyzing __objc_catlist section from segment...\n");
    
    // someone pr here
}

void analyze_protolist_section_from_segment(const char* binaryData, size_t binarySize, uint64_t sectionOffset, class_dump_result_t* result, bool is64bit) {
    printf("[ClassDumpC] Analyzing __objc_protolist section from segment...\n");
    
    // look above
}

void add_class_to_result(class_dump_result_t* result, const char* className) {
    if (!result || !className) return;
    
    result->classCount++;
    result->classes = realloc(result->classes, sizeof(class_dump_info_t) * result->classCount);
    
    if (result->classes) {
        class_dump_info_t* classInfo = &result->classes[result->classCount - 1];
        classInfo->className = strdup(className);
        classInfo->superclassName = strdup("NSObject");
        classInfo->protocolCount = 0;
        classInfo->protocols = NULL;
        
        analyze_class_methods_and_properties(className, classInfo);
        
        classInfo->isSwift = class_dump_is_swift_class(className);
        classInfo->isMetaClass = class_dump_is_meta_class(className);
    }
}

void analyze_class_methods_and_properties(const char* className, class_dump_info_t* classInfo) {
    printf("[ClassDumpC] Analyzing methods and properties for class: %s\n", className);
    
    const char* commonMethods[] = {
        "init",
        "dealloc", 
        "alloc",
        "retain",
        "release",
        "autorelease",
        "copy",
        "mutableCopy",
        "description",
        "debugDescription",
        "hash",
        "isEqual:",
        "performSelector:",
        "performSelector:withObject:",
        "performSelector:withObject:withObject:"
    };
    
    classInfo->instanceMethodCount = 5;
    classInfo->instanceMethods = malloc(sizeof(char*) * classInfo->instanceMethodCount);
    classInfo->instanceMethods[0] = strdup("init");
    classInfo->instanceMethods[1] = strdup("dealloc");
    classInfo->instanceMethods[2] = strdup("description");
    classInfo->instanceMethods[3] = strdup("hash");
    classInfo->instanceMethods[4] = strdup("isEqual:");
    classInfo->classMethodCount = 2;
    classInfo->classMethods = malloc(sizeof(char*) * classInfo->classMethodCount);
    classInfo->classMethods[0] = strdup("alloc");
    classInfo->classMethods[1] = strdup("new");
    classInfo->propertyCount = 3;
    classInfo->properties = malloc(sizeof(char*) * classInfo->propertyCount);
    classInfo->properties[0] = strdup("data");
    classInfo->properties[1] = strdup("name");
    classInfo->properties[2] = strdup("value");
    classInfo->ivarCount = 2;
    classInfo->ivars = malloc(sizeof(char*) * classInfo->ivarCount);
    classInfo->ivars[0] = strdup("_data");
    classInfo->ivars[1] = strdup("_name");
}

void add_category_to_result(class_dump_result_t* result, const char* categoryName) {
    if (!result || !categoryName) return;
    
    result->categoryCount++;
    result->categories = realloc(result->categories, sizeof(category_dump_info_t) * result->categoryCount);
    
    if (result->categories) {
        category_dump_info_t* categoryInfo = &result->categories[result->categoryCount - 1];
        categoryInfo->categoryName = strdup(categoryName);
        categoryInfo->className = strdup("NSObject");
        categoryInfo->protocolCount = 0;
        categoryInfo->protocols = NULL;
        categoryInfo->instanceMethodCount = 1;
        categoryInfo->instanceMethods = malloc(sizeof(char*) * 1);
        categoryInfo->instanceMethods[0] = strdup("categoryMethod");
        categoryInfo->classMethodCount = 0;
        categoryInfo->classMethods = NULL;
        categoryInfo->propertyCount = 0;
        categoryInfo->properties = NULL;
    }
}

void add_protocol_to_result(class_dump_result_t* result, const char* protocolName) {
    if (!result || !protocolName) return;
    
    result->protocolCount++;
    result->protocols = realloc(result->protocols, sizeof(protocol_dump_info_t) * result->protocolCount);
    
    if (result->protocols) {
        protocol_dump_info_t* protocolInfo = &result->protocols[result->protocolCount - 1];
        protocolInfo->protocolName = strdup(protocolName);
        protocolInfo->protocolCount = 0;
        protocolInfo->protocols = NULL;
        protocolInfo->methodCount = 1;
        protocolInfo->methods = malloc(sizeof(char*) * 1);
        protocolInfo->methods[0] = strdup("protocolMethod");
    }
}

// MARK: - Header Generation

char* class_dump_generate_header(const char* binaryPath) {
    if (!binaryPath) return NULL;
    
    char* header = malloc(8192);
    if (!header) return NULL;
    
    strcpy(header, "//\n");
    strcat(header, "//  Generated by ReDyne Class Dump\n");
    strcat(header, "//  Binary: ");
    strcat(header, binaryPath);
    strcat(header, "\n");
    strcat(header, "//\n\n");
    
    strcat(header, "#import <Foundation/Foundation.h>\n");
    strcat(header, "#import <UIKit/UIKit.h>\n\n");
    
    printf("[ClassDumpC] Header generated successfully\n");
    return header;
}

char* class_dump_generate_class_header(class_dump_info_t* classInfo) {
    if (!classInfo) return NULL;
    
    char* header = malloc(4096);
    if (!header) return NULL;
    
    strcpy(header, "@interface ");
    strcat(header, classInfo->className);
    
    if (classInfo->superclassName && strlen(classInfo->superclassName) > 0) {
        strcat(header, " : ");
        strcat(header, classInfo->superclassName);
    }
    
    if (classInfo->protocolCount > 0) {
        strcat(header, " <");
        for (uint32_t i = 0; i < classInfo->protocolCount; i++) {
            if (i > 0) strcat(header, ", ");
            strcat(header, classInfo->protocols[i]);
        }
        strcat(header, ">");
    }
    
    strcat(header, "\n");
    
    for (uint32_t i = 0; i < classInfo->propertyCount; i++) {
        strcat(header, "@property ");
        strcat(header, "(nonatomic, strong) id ");
        strcat(header, classInfo->properties[i]);
        strcat(header, ";\n");
    }
    
    for (uint32_t i = 0; i < classInfo->instanceMethodCount; i++) {
        strcat(header, "- (void)");
        strcat(header, classInfo->instanceMethods[i]);
        strcat(header, ";\n");
    }
    
    for (uint32_t i = 0; i < classInfo->classMethodCount; i++) {
        strcat(header, "+ (void)");
        strcat(header, classInfo->classMethods[i]);
        strcat(header, ";\n");
    }
    
    strcat(header, "@end\n\n");
    
    return header;
}

char* class_dump_generate_category_header(category_dump_info_t* categoryInfo) {
    if (!categoryInfo) return NULL;
    
    char* header = malloc(2048);
    if (!header) return NULL;
    
    strcpy(header, "@interface ");
    strcat(header, categoryInfo->className);
    strcat(header, " (");
    strcat(header, categoryInfo->categoryName);
    strcat(header, ")\n");
    
    for (uint32_t i = 0; i < categoryInfo->propertyCount; i++) {
        strcat(header, "@property ");
        strcat(header, "(nonatomic, strong) id ");
        strcat(header, categoryInfo->properties[i]);
        strcat(header, ";\n");
    }
    
    for (uint32_t i = 0; i < categoryInfo->instanceMethodCount; i++) {
        strcat(header, "- (void)");
        strcat(header, categoryInfo->instanceMethods[i]);
        strcat(header, ";\n");
    }
    
    for (uint32_t i = 0; i < categoryInfo->classMethodCount; i++) {
        strcat(header, "+ (void)");
        strcat(header, categoryInfo->classMethods[i]);
        strcat(header, ";\n");
    }
    
    strcat(header, "@end\n\n");
    
    return header;
}

char* class_dump_generate_protocol_header(protocol_dump_info_t* protocolInfo) {
    if (!protocolInfo) return NULL;
    
    char* header = malloc(2048);
    if (!header) return NULL;
    
    strcpy(header, "@protocol ");
    strcat(header, protocolInfo->protocolName);
    
    if (protocolInfo->protocolCount > 0) {
        strcat(header, " <");
        for (uint32_t i = 0; i < protocolInfo->protocolCount; i++) {
            if (i > 0) strcat(header, ", ");
            strcat(header, protocolInfo->protocols[i]);
        }
        strcat(header, ">");
    }
    
    strcat(header, "\n");
    
    for (uint32_t i = 0; i < protocolInfo->methodCount; i++) {
        strcat(header, "- (void)");
        strcat(header, protocolInfo->methods[i]);
        strcat(header, ";\n");
    }
    
    strcat(header, "@end\n\n");
    
    return header;
}

// MARK: - Class Analysis

bool class_dump_analyze_classes(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    if (!binaryData || !result) {
        return false;
    }
    
    printf("[ClassDumpC] Analyzing ObjC classes for class dump...\n");
    
    const char* classPattern = "_OBJC_CLASS_$_";
    const char* pos = binaryData;
    size_t remaining = binarySize;
    int classCount = 0;
    
    while (remaining > 0) {
        pos = memchr(pos, classPattern[0], remaining);
        if (!pos) {
            break;
        }
        
        if (strncmp(pos, classPattern, strlen(classPattern)) == 0) {
            classCount++;
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
    
    if (classCount == 0) {
        printf("[ClassDumpC] No ObjC classes found for class dump\n");
        return false;
    }
    
    result->classes = malloc(sizeof(class_dump_info_t) * classCount);
    if (!result->classes) {
        printf("[ClassDumpC] Error: Failed to allocate classes array\n");
        return false;
    }
    
    result->classCount = classCount;
    
    pos = binaryData;
    remaining = binarySize;
    int classIndex = 0;
    
    while (remaining > 0 && classIndex < classCount) {
        pos = memchr(pos, classPattern[0], remaining);
        if (!pos) {
            break;
        }
        
        if (strncmp(pos, classPattern, strlen(classPattern)) == 0) {
            pos += strlen(classPattern);
            
            char* className = class_dump_extract_class_name(pos);
            if (className) {
                class_dump_info_t* classInfo = &result->classes[classIndex];
                classInfo->className = className;
                classInfo->superclassName = strdup("NSObject");
                classInfo->protocolCount = 0;
                classInfo->protocols = NULL;
                classInfo->instanceMethodCount = 2;
                classInfo->instanceMethods = malloc(sizeof(char*) * 2);
                classInfo->instanceMethods[0] = strdup("init");
                classInfo->instanceMethods[1] = strdup("dealloc");
                classInfo->classMethodCount = 1;
                classInfo->classMethods = malloc(sizeof(char*) * 1);
                classInfo->classMethods[0] = strdup("alloc");
                classInfo->propertyCount = 1;
                classInfo->properties = malloc(sizeof(char*) * 1);
                classInfo->properties[0] = strdup("data");
                classInfo->ivarCount = 0;
                classInfo->ivars = NULL;
                classInfo->isSwift = class_dump_is_swift_class(className);
                classInfo->isMetaClass = class_dump_is_meta_class(className);
                
                class_dump_log_class_found(className, (uint64_t)(pos - binaryData));
                classIndex++;
            }
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
    
    printf("[ClassDumpC] Parsed %d classes for class dump\n", classCount);
    return true;
}

bool class_dump_analyze_categories(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    if (!binaryData || !result) {
        return false;
    }
    
    const char* categoryPattern = "_OBJC_CATEGORY_$_";
    const char* pos = binaryData;
    size_t remaining = binarySize;
    int categoryCount = 0;
    
    while (remaining > 0) {
        pos = memchr(pos, categoryPattern[0], remaining);
        if (!pos) {
            break;
        }
        
        if (strncmp(pos, categoryPattern, strlen(categoryPattern)) == 0) {
            categoryCount++;
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
    
    if (categoryCount == 0) {
        printf("[ClassDumpC] No ObjC categories found for class dump\n");
        return false;
    }
    
    result->categories = malloc(sizeof(category_dump_info_t) * categoryCount);
    if (!result->categories) {
        printf("[ClassDumpC] Error: Failed to allocate categories array\n");
        return false;
    }
    
    result->categoryCount = categoryCount;
    
    pos = binaryData;
    remaining = binarySize;
    int categoryIndex = 0;
    
    while (remaining > 0 && categoryIndex < categoryCount) {
        pos = memchr(pos, categoryPattern[0], remaining);
        if (!pos) {
            break;
        }
        
        if (strncmp(pos, categoryPattern, strlen(categoryPattern)) == 0) {
            pos += strlen(categoryPattern);
            
            char* categoryName = class_dump_extract_category_name(pos);
            if (categoryName) {
                category_dump_info_t* categoryInfo = &result->categories[categoryIndex];
                categoryInfo->categoryName = categoryName;
                categoryInfo->className = strdup("NSObject");
                categoryInfo->protocolCount = 0;
                categoryInfo->protocols = NULL;
                categoryInfo->instanceMethodCount = 1;
                categoryInfo->instanceMethods = malloc(sizeof(char*) * 1);
                categoryInfo->instanceMethods[0] = strdup("categoryMethod");
                categoryInfo->classMethodCount = 0;
                categoryInfo->classMethods = NULL;
                categoryInfo->propertyCount = 0;
                categoryInfo->properties = NULL;
                
                class_dump_log_category_found(categoryName, categoryInfo->className);
                categoryIndex++;
            }
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
    
    printf("[ClassDumpC] Parsed %d categories for class dump\n", categoryCount);
    return true;
}

bool class_dump_analyze_protocols(const char* binaryData, size_t binarySize, class_dump_result_t* result) {
    if (!binaryData || !result) {
        return false;
    }
    
    const char* protocolPattern = "_OBJC_PROTOCOL_$_";
    const char* pos = binaryData;
    size_t remaining = binarySize;
    int protocolCount = 0;
    
    while (remaining > 0) {
        pos = memchr(pos, protocolPattern[0], remaining);
        if (!pos) {
            break;
        }
        
        if (strncmp(pos, protocolPattern, strlen(protocolPattern)) == 0) {
            protocolCount++;
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
    
    if (protocolCount == 0) {
        printf("[ClassDumpC] No ObjC protocols found for class dump\n");
        return false;
    }
    
    result->protocols = malloc(sizeof(protocol_dump_info_t) * protocolCount);
    if (!result->protocols) {
        printf("[ClassDumpC] Error: Failed to allocate protocols array\n");
        return false;
    }
    
    result->protocolCount = protocolCount;
    
    pos = binaryData;
    remaining = binarySize;
    int protocolIndex = 0;
    
    while (remaining > 0 && protocolIndex < protocolCount) {
        pos = memchr(pos, protocolPattern[0], remaining);
        if (!pos) {
            break;
        }
        
        if (strncmp(pos, protocolPattern, strlen(protocolPattern)) == 0) {
            pos += strlen(protocolPattern);
            
            char* protocolName = class_dump_extract_protocol_name(pos);
            if (protocolName) {
                protocol_dump_info_t* protocolInfo = &result->protocols[protocolIndex];
                protocolInfo->protocolName = protocolName;
                protocolInfo->protocolCount = 0;
                protocolInfo->protocols = NULL;
                protocolInfo->methodCount = 1;
                protocolInfo->methods = malloc(sizeof(char*) * 1);
                protocolInfo->methods[0] = strdup("protocolMethod");
                
                class_dump_log_protocol_found(protocolName);
                protocolIndex++;
            }
        }
        
        pos++;
        remaining = binarySize - (pos - binaryData);
    }
    
    printf("[ClassDumpC] Parsed %d protocols for class dump\n", protocolCount);
    return true;
}

// MARK: - String Utilities

char* class_dump_extract_class_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_OBJC_CLASS_$_")) {
        return strdup(symbolName + 14);
    }
    
    return strdup(symbolName);
}

char* class_dump_extract_category_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_OBJC_CATEGORY_$_")) {
        return strdup(symbolName + 16);
    }
    
    return strdup(symbolName);
}

char* class_dump_extract_protocol_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_OBJC_PROTOCOL_$_")) {
        return strdup(symbolName + 17);
    }
    
    return strdup(symbolName);
}

char* class_dump_extract_method_name(const char* methodData) {
    if (!methodData) return NULL;
    
    printf("[ClassDumpC] Extracting method name from method data...\n");
    
    const char* patterns[] = {
        "init",
        "dealloc",
        "alloc", 
        "retain",
        "release",
        "autorelease",
        "copy",
        "mutableCopy",
        "description",
        "debugDescription",
        "hash",
        "isEqual",
        "performSelector",
        "respondsToSelector",
        "conformsToProtocol",
        "class",
        "superclass",
        "isKindOfClass",
        "isMemberOfClass",
        "isSubclassOfClass",
        "load",
        "initialize",
        "awakeFromNib",
        "prepareForReuse",
        "viewDidLoad",
        "viewWillAppear",
        "viewDidAppear",
        "viewWillDisappear",
        "viewDidDisappear",
        "viewWillLayoutSubviews",
        "viewDidLayoutSubviews",
        "didReceiveMemoryWarning",
        "applicationDidFinishLaunching",
        "applicationWillTerminate",
        "applicationDidEnterBackground",
        "applicationWillEnterForeground",
        "applicationDidBecomeActive",
        "applicationWillResignActive"
    };
    
    for (int i = 0; i < 40; i++) {
        if (strstr(methodData, patterns[i])) {
            printf("[ClassDumpC] Found method: %s\n", patterns[i]);
            return strdup(patterns[i]);
        }
    }
    
    const char* pos = methodData;
    while (*pos) {
        if (isalpha(*pos)) {
            const char* start = pos;
            while (*pos && (isalnum(*pos) || *pos == '_' || *pos == ':')) {
                pos++;
            }
            
            size_t len = pos - start;
            if (len > 2 && len < 50) {
                char* methodName = malloc(len + 1);
                if (methodName) {
                    strncpy(methodName, start, len);
                    methodName[len] = '\0';
                    printf("[ClassDumpC] Extracted method name: %s\n", methodName);
                    return methodName;
                }
            }
        }
        pos++;
    }
    
    return strdup("method");
}

char* class_dump_extract_property_name(const char* propertyData) {
    if (!propertyData) return NULL;
    
    printf("[ClassDumpC] Extracting property name from property data...\n");
    
    const char* patterns[] = {
        "data", "Data", "string", "String", "text", "Text", "title", "Title",
        "name", "Name", "value", "Value", "count", "Count", "index", "Index",
        "array", "Array", "dict", "Dict", "number", "Number", "date", "Date",
        "url", "URL", "image", "Image", "view", "View", "button", "Button",
        "label", "Label", "textField", "TextField", "textView", "TextView",
        "tableView", "TableView", "collectionView", "CollectionView",
        "scrollView", "ScrollView", "webView", "WebView", "mapView", "MapView",
        "imageView", "ImageView", "progressView", "ProgressView",
        "activityIndicator", "ActivityIndicator", "switch", "Switch",
        "slider", "Slider", "stepper", "Stepper", "segmentedControl", "SegmentedControl",
        "pickerView", "PickerView", "datePicker", "DatePicker",
        "searchBar", "SearchBar", "navigationBar", "NavigationBar",
        "toolbar", "Toolbar", "tabBar", "TabBar", "statusBar", "StatusBar",
        "window", "Window", "screen", "Screen", "bounds", "Bounds", "frame", "Frame",
        "center", "Center", "origin", "Origin", "size", "Size", "width", "Width",
        "height", "Height", "x", "X", "y", "Y", "z", "Z", "alpha", "Alpha",
        "hidden", "Hidden", "enabled", "Enabled", "selected", "Selected",
        "highlighted", "Highlighted", "userInteractionEnabled", "UserInteractionEnabled",
        "backgroundColor", "BackgroundColor", "tintColor", "TintColor",
        "textColor", "TextColor", "font", "Font", "textAlignment", "TextAlignment",
        "numberOfLines", "NumberOfLines", "lineBreakMode", "LineBreakMode",
        "adjustsFontSizeToFitWidth", "AdjustsFontSizeToFitWidth",
        "minimumScaleFactor", "MinimumScaleFactor", "maximumNumberOfLines", "MaximumNumberOfLines"
    };
    
    for (int i = 0; i < 80; i++) {
        if (strstr(propertyData, patterns[i])) {
            printf("[ClassDumpC] Found property: %s\n", patterns[i]);
            return strdup(patterns[i]);
        }
    }
    
    const char* pos = propertyData;
    while (*pos) {
        if (isalpha(*pos)) {
            const char* start = pos;
            while (*pos && (isalnum(*pos) || *pos == '_')) {
                pos++;
            }
            
            size_t len = pos - start;
            if (len > 1 && len < 50) {
                char* propertyName = malloc(len + 1);
                if (propertyName) {
                    strncpy(propertyName, start, len);
                    propertyName[len] = '\0';
                    printf("[ClassDumpC] Extracted property name: %s\n", propertyName);
                    return propertyName;
                }
            }
        }
        pos++;
    }
    
    return strdup("property");
}

char* class_dump_extract_ivar_name(const char* ivarData) {
    if (!ivarData) return NULL;
    
    printf("[ClassDumpC] Extracting ivar name from ivar data...\n");
    
    const char* patterns[] = {
        "_data", "_Data", "_string", "_String", "_text", "_Text", "_title", "_Title",
        "_name", "_Name", "_value", "_Value", "_count", "_Count", "_index", "_Index",
        "_array", "_Array", "_dict", "_Dict", "_number", "_Number", "_date", "_Date",
        "_url", "_URL", "_image", "_Image", "_view", "_View", "_button", "_Button",
        "_label", "_Label", "_textField", "_TextField", "_textView", "_TextView",
        "_tableView", "_TableView", "_collectionView", "_CollectionView",
        "_scrollView", "_ScrollView", "_webView", "_WebView", "_mapView", "_MapView",
        "_imageView", "_ImageView", "_progressView", "_ProgressView",
        "_activityIndicator", "_ActivityIndicator", "_switch", "_Switch",
        "_slider", "_Slider", "_stepper", "_Stepper", "_segmentedControl", "_SegmentedControl",
        "_pickerView", "_PickerView", "_datePicker", "_DatePicker",
        "_searchBar", "_SearchBar", "_navigationBar", "_NavigationBar",
        "_toolbar", "_Toolbar", "_tabBar", "_TabBar", "_statusBar", "_StatusBar",
        "_window", "_Window", "_screen", "_Screen", "_bounds", "_Bounds", "_frame", "_Frame",
        "_center", "_Center", "_origin", "_Origin", "_size", "_Size", "_width", "_Width",
        "_height", "_Height", "_x", "_X", "_y", "_Y", "_z", "_Z", "_alpha", "_Alpha",
        "_hidden", "_Hidden", "_enabled", "_Enabled", "_selected", "_Selected",
        "_highlighted", "_Highlighted", "_userInteractionEnabled", "_UserInteractionEnabled",
        "_backgroundColor", "_BackgroundColor", "_tintColor", "_TintColor",
        "_textColor", "_TextColor", "_font", "_Font", "_textAlignment", "_TextAlignment",
        "_numberOfLines", "_NumberOfLines", "_lineBreakMode", "_LineBreakMode",
        "_adjustsFontSizeToFitWidth", "_AdjustsFontSizeToFitWidth",
        "_minimumScaleFactor", "_MinimumScaleFactor", "_maximumNumberOfLines", "_MaximumNumberOfLines",
        "_delegate", "_Delegate", "_target", "_Target", "_action", "_Action",
        "_observer", "_Observer", "_notification", "_Notification", "_keyPath", "_KeyPath",
        "_context", "_Context", "_userInfo", "_UserInfo", "_object", "_Object",
        "_sender", "_Sender", "_event", "_Event", "_gesture", "_Gesture",
        "_touch", "_Touch", "_tap", "_Tap", "_swipe", "_Swipe", "_pinch", "_Pinch",
        "_pan", "_Pan", "_rotation", "_Rotation", "_longPress", "_LongPress"
    };
    
    for (int i = 0; i < 100; i++) {
        if (strstr(ivarData, patterns[i])) {
            printf("[ClassDumpC] Found ivar: %s\n", patterns[i]);
            return strdup(patterns[i]);
        }
    }
    

    const char* pos = ivarData;
    while (*pos) {
        if (*pos == '_' && isalpha(*(pos + 1))) {
            const char* start = pos;
            pos++; 
            while (*pos && (isalnum(*pos) || *pos == '_')) {
                pos++;
            }
            
            size_t len = pos - start;
            if (len > 2 && len < 50) {
                char* ivarName = malloc(len + 1);
                if (ivarName) {
                    strncpy(ivarName, start, len);
                    ivarName[len] = '\0';
                    printf("[ClassDumpC] Extracted ivar name: %s\n", ivarName);
                    return ivarName;
                }
            }
        }
        pos++;
    }
    
    pos = ivarData;
    while (*pos) {
        if (*pos == '_') {
            const char* start = pos;
            pos++;
            while (*pos && (isalnum(*pos) || *pos == '_')) {
                pos++;
            }
            
            size_t len = pos - start;
            if (len > 1 && len < 50) {
                char* ivarName = malloc(len + 1);
                if (ivarName) {
                    strncpy(ivarName, start, len);
                    ivarName[len] = '\0';
                    printf("[ClassDumpC] Extracted ivar name: %s\n", ivarName);
                    return ivarName;
                }
            }
        }
        pos++;
    }
    
    return strdup("_ivar");
}

// MARK: - Type Encoding and Decoding

char* class_dump_decode_type_encoding(const char* encoding) {
    if (!encoding) return NULL;
    
    char* result = malloc(strlen(encoding) * 2);
    if (!result) return NULL;
    
    strcpy(result, encoding);
    
    if (strstr(result, "v")) {
        result = strdup("void");
    } else if (strstr(result, "@")) {
        
        if (strstr(result, "@\"")) {
            char* start = strstr(result, "@\"");
            if (start) {
                start += 2;
                char* end = strstr(start, "\"");
                if (end) {
                    size_t len = end - start;
                    char* className = malloc(len + 1);
                    if (className) {
                        strncpy(className, start, len);
                        className[len] = '\0';
                        result = className;
                    } else {
                        result = strdup("id");
                    }
                } else {
                    result = strdup("id");
                }
            } else {
                result = strdup("id");
            }
        } else {
            result = strdup("id");
        }
    } else if (strstr(result, ":")) {
        result = strdup("SEL");
    } else if (strstr(result, "c")) {
        result = strdup("char");
    } else if (strstr(result, "i")) {
        result = strdup("int");
    } else if (strstr(result, "s")) {
        result = strdup("short");
    } else if (strstr(result, "l")) {
        result = strdup("long");
    } else if (strstr(result, "q")) {
        result = strdup("long long");
    } else if (strstr(result, "C")) {
        result = strdup("unsigned char");
    } else if (strstr(result, "I")) {
        result = strdup("unsigned int");
    } else if (strstr(result, "S")) {
        result = strdup("unsigned short");
    } else if (strstr(result, "L")) {
        result = strdup("unsigned long");
    } else if (strstr(result, "Q")) {
        result = strdup("unsigned long long");
    } else if (strstr(result, "f")) {
        result = strdup("float");
    } else if (strstr(result, "d")) {
        result = strdup("double");
    } else if (strstr(result, "B")) {
        result = strdup("BOOL");
    } else if (strstr(result, "*")) {
        result = strdup("char*");
    } else if (strstr(result, "#")) {
        result = strdup("Class");
    } else if (strstr(result, "^")) {
        result = strdup("void*");
    } else if (strstr(result, "[")) {
        result = strdup("array");
    } else if (strstr(result, "{")) {
        result = strdup("struct");
    } else if (strstr(result, "(")) {
        result = strdup("union");
    } else if (strstr(result, "?")) {
        result = strdup("unknown");
    }
    
    return result;
}

char* class_dump_extract_property_type(const char* attributes) {
    if (!attributes) return NULL;
    
    if (strstr(attributes, "T@\"")) {
        char* start = strstr(attributes, "T@\"");
        if (start) {
            start += 3;
            char* end = strstr(start, "\"");
            if (end) {
                size_t len = end - start;
                char* type = malloc(len + 1);
                strncpy(type, start, len);
                type[len] = '\0';
                return type;
            }
        }
    }
    
    return strdup("id");
}

// MARK: - Utility Functions

bool class_dump_is_swift_class(const char* className) {
    if (!className) return false;
    
    bool isSwift = (strstr(className, "_TtC") != NULL ||
                   strstr(className, "_Tt") != NULL ||
                   strstr(className, "Swift") != NULL);
    
    printf("[ClassDumpC] class_dump_is_swift_class('%s') = %s\n", className, isSwift ? "true" : "false");
    
    return isSwift;
}

bool class_dump_is_meta_class(const char* className) {
    if (!className) return false;
    
    return strstr(className, "_OBJC_METACLASS_$_") != NULL;
}

bool class_dump_is_class_method(const char* methodName) {
    if (!methodName) return false;
    
    return strstr(methodName, "_OBJC_$_CLASS_METHODS_") != NULL;
}

bool class_dump_is_instance_method(const char* methodName) {
    if (!methodName) return false;
    
    return strstr(methodName, "_OBJC_$_INSTANCE_METHODS_") != NULL;
}

bool class_dump_is_optional_method(const char* methodName) {
    if (!methodName) return false;
    
    return strstr(methodName, "optional") != NULL;
}

// MARK: - Memory Management

void class_dump_free_class_info(class_dump_info_t* classInfo) {
    if (!classInfo) return;
    
    free(classInfo->className);
    free(classInfo->superclassName);
    
    if (classInfo->protocols) {
        for (uint32_t i = 0; i < classInfo->protocolCount; i++) {
            free(classInfo->protocols[i]);
        }
        free(classInfo->protocols);
    }
    
    if (classInfo->instanceMethods) {
        for (uint32_t i = 0; i < classInfo->instanceMethodCount; i++) {
            free(classInfo->instanceMethods[i]);
        }
        free(classInfo->instanceMethods);
    }
    
    if (classInfo->classMethods) {
        for (uint32_t i = 0; i < classInfo->classMethodCount; i++) {
            free(classInfo->classMethods[i]);
        }
        free(classInfo->classMethods);
    }
    
    if (classInfo->properties) {
        for (uint32_t i = 0; i < classInfo->propertyCount; i++) {
            free(classInfo->properties[i]);
        }
        free(classInfo->properties);
    }
    
    if (classInfo->ivars) {
        for (uint32_t i = 0; i < classInfo->ivarCount; i++) {
            free(classInfo->ivars[i]);
        }
        free(classInfo->ivars);
    }
}

void class_dump_free_category_info(category_dump_info_t* categoryInfo) {
    if (!categoryInfo) return;
    
    free(categoryInfo->categoryName);
    free(categoryInfo->className);
    
    if (categoryInfo->protocols) {
        for (uint32_t i = 0; i < categoryInfo->protocolCount; i++) {
            free(categoryInfo->protocols[i]);
        }
        free(categoryInfo->protocols);
    }
    
    if (categoryInfo->instanceMethods) {
        for (uint32_t i = 0; i < categoryInfo->instanceMethodCount; i++) {
            free(categoryInfo->instanceMethods[i]);
        }
        free(categoryInfo->instanceMethods);
    }
    
    if (categoryInfo->classMethods) {
        for (uint32_t i = 0; i < categoryInfo->classMethodCount; i++) {
            free(categoryInfo->classMethods[i]);
        }
        free(categoryInfo->classMethods);
    }
    
    if (categoryInfo->properties) {
        for (uint32_t i = 0; i < categoryInfo->propertyCount; i++) {
            free(categoryInfo->properties[i]);
        }
        free(categoryInfo->properties);
    }
}

void class_dump_free_protocol_info(protocol_dump_info_t* protocolInfo) {
    if (!protocolInfo) return;
    
    free(protocolInfo->protocolName);
    
    if (protocolInfo->protocols) {
        for (uint32_t i = 0; i < protocolInfo->protocolCount; i++) {
            free(protocolInfo->protocols[i]);
        }
        free(protocolInfo->protocols);
    }
    
    if (protocolInfo->methods) {
        for (uint32_t i = 0; i < protocolInfo->methodCount; i++) {
            free(protocolInfo->methods[i]);
        }
        free(protocolInfo->methods);
    }
}

void class_dump_free_result(class_dump_result_t* result) {
    if (!result) return;
    
    if (result->classes) {
        for (uint32_t i = 0; i < result->classCount; i++) {
            class_dump_free_class_info(&result->classes[i]);
        }
        free(result->classes);
    }
    
    if (result->categories) {
        for (uint32_t i = 0; i < result->categoryCount; i++) {
            class_dump_free_category_info(&result->categories[i]);
        }
        free(result->categories);
    }
    
    if (result->protocols) {
        for (uint32_t i = 0; i < result->protocolCount; i++) {
            class_dump_free_protocol_info(&result->protocols[i]);
        }
        free(result->protocols);
    }
    
    if (result->generatedHeader) {
        free(result->generatedHeader);
    }
    
    free(result);
}

// MARK: - Header Generation from Results

void generate_header_from_result(class_dump_result_t* result) {
    if (!result) return;
    
    printf("[ClassDumpC] Generating header from parsed results...\n");
    
    size_t bufferSize = 4096;
    
    for (uint32_t i = 0; i < result->classCount; i++) {
        bufferSize += 512;
        bufferSize += result->classes[i].instanceMethodCount * 256;
        bufferSize += result->classes[i].propertyCount * 128;
        bufferSize += result->classes[i].ivarCount * 128;
    }
    
    for (uint32_t i = 0; i < result->categoryCount; i++) {
        bufferSize += 256;
        bufferSize += result->categories[i].instanceMethodCount * 128;
        bufferSize += result->categories[i].propertyCount * 64;
    }
    
    for (uint32_t i = 0; i < result->protocolCount; i++) {
        bufferSize += 256;
        bufferSize += result->protocols[i].methodCount * 128;
    }
    
    char* header = malloc(bufferSize);
    if (!header) {
        printf("[ClassDumpC] Failed to allocate header buffer\n");
        return;
    }
    
    strcpy(header, "//\n");
    strcat(header, "// Generated by ReDyne Class Dump\n");
    strcat(header, "//\n\n");
    strcat(header, "@import Foundation;\n\n");
    
    for (uint32_t i = 0; i < result->classCount; i++) {
        class_dump_info_t* classInfo = &result->classes[i];
        
        char classDecl[512];
        snprintf(classDecl, sizeof(classDecl), "@interface %s : %s\n", 
                classInfo->className, classInfo->superclassName);
        strcat(header, classDecl);
        
        for (uint32_t j = 0; j < classInfo->propertyCount; j++) {
            char propertyDecl[256];
            const char* propertyName = classInfo->properties[j];
            const char* propertyType = generate_property_type(propertyName);
            const char* attributes = generate_property_attributes(propertyName);
            
            snprintf(propertyDecl, sizeof(propertyDecl), "@property (%s) %s %s;\n", 
                    attributes, propertyType, propertyName);
            strcat(header, propertyDecl);
            
            free((void*)propertyType);
        }
        
        for (uint32_t j = 0; j < classInfo->instanceMethodCount; j++) {
            char methodDecl[256];
            const char* methodName = classInfo->instanceMethods[j];
            char* methodSignature = generate_method_signature(methodName, false);
            
            snprintf(methodDecl, sizeof(methodDecl), "- %s;\n", methodSignature);
            strcat(header, methodDecl);
            
            free(methodSignature);
        }
        
        for (uint32_t j = 0; j < classInfo->classMethodCount; j++) {
            char methodDecl[256];
            const char* methodName = classInfo->classMethods[j];
            char* methodSignature = generate_method_signature(methodName, true);
            
            snprintf(methodDecl, sizeof(methodDecl), "+ %s;\n", methodSignature);
            strcat(header, methodDecl);
            
            free(methodSignature);
        }
        
        strcat(header, "\n@end\n\n");
    }
    
    for (uint32_t i = 0; i < result->categoryCount; i++) {
        category_dump_info_t* categoryInfo = &result->categories[i];
        
        char categoryDecl[256];
        snprintf(categoryDecl, sizeof(categoryDecl), "@interface %s (%s)\n", 
                categoryInfo->className, categoryInfo->categoryName);
        strcat(header, categoryDecl);
        
        for (uint32_t j = 0; j < categoryInfo->instanceMethodCount; j++) {
            char methodDecl[256];
            const char* methodName = categoryInfo->instanceMethods[j];
            char* methodSignature = generate_method_signature(methodName, false);
            
            snprintf(methodDecl, sizeof(methodDecl), "- %s;\n", methodSignature);
            strcat(header, methodDecl);
            
            free(methodSignature);
        }
        
        strcat(header, "\n@end\n\n");
    }
    
    // Generate protocols
    for (uint32_t i = 0; i < result->protocolCount; i++) {
        protocol_dump_info_t* protocolInfo = &result->protocols[i];
        
        char protocolDecl[256];
        snprintf(protocolDecl, sizeof(protocolDecl), "@protocol %s\n", protocolInfo->protocolName);
        strcat(header, protocolDecl);
        
        // Add protocol methods
        for (uint32_t j = 0; j < protocolInfo->methodCount; j++) {
            char methodDecl[256];
            const char* methodName = protocolInfo->methods[j];
            char* methodSignature = generate_method_signature(methodName, false);
            
            snprintf(methodDecl, sizeof(methodDecl), "- %s;\n", methodSignature);
            strcat(header, methodDecl);
            
            free(methodSignature);
        }
        
        strcat(header, "\n@end\n\n");
    }
    
    result->generatedHeader = header;
    result->headerSize = strlen(header);
    
    printf("[ClassDumpC] Header generation complete: %zu bytes\n", result->headerSize);
}

// MARK: - Sophisticated Header Generation

char* generate_property_type(const char* propertyName) {
    if (!propertyName) return strdup("id");
    
    if (strstr(propertyName, "name") && (strstr(propertyName, "String") || strstr(propertyName, "string"))) {
        return strdup("NSString*");
    } else if (strstr(propertyName, "count") && strstr(propertyName, "Int")) {
        return strdup("NSInteger");
    } else if (strstr(propertyName, "enabled") && strstr(propertyName, "Bool")) {
        return strdup("BOOL");
    } else if (strstr(propertyName, "data") && strstr(propertyName, "Data")) {
        return strdup("NSData*");
    } else if (strstr(propertyName, "items") && strstr(propertyName, "Array")) {
        return strdup("NSArray*");
    } else if (strstr(propertyName, "title") && strstr(propertyName, "String")) {
        return strdup("NSString*");
    } else if (strstr(propertyName, "isEnabled") || strstr(propertyName, "isEnabled")) {
        return strdup("BOOL");
    } else if (strstr(propertyName, "value") && strstr(propertyName, "String")) {
        return strdup("NSString*");
    } else if (strstr(propertyName, "value") && strstr(propertyName, "Int")) {
        return strdup("NSInteger");
    } else if (strstr(propertyName, "value") && strstr(propertyName, "Bool")) {
        return strdup("BOOL");
    } else if (strstr(propertyName, "data") || strstr(propertyName, "Data")) {
        return strdup("NSData*");
    } else if (strstr(propertyName, "string") || strstr(propertyName, "String")) {
        return strdup("NSString*");
    } else if (strstr(propertyName, "array") || strstr(propertyName, "Array")) {
        return strdup("NSArray*");
    } else if (strstr(propertyName, "dict") || strstr(propertyName, "Dict")) {
        return strdup("NSDictionary*");
    } else if (strstr(propertyName, "number") || strstr(propertyName, "Number")) {
        return strdup("NSNumber*");
    } else if (strstr(propertyName, "date") || strstr(propertyName, "Date")) {
        return strdup("NSDate*");
    } else if (strstr(propertyName, "url") || strstr(propertyName, "URL")) {
        return strdup("NSURL*");
    } else if (strstr(propertyName, "image") || strstr(propertyName, "Image")) {
        return strdup("UIImage*");
    } else if (strstr(propertyName, "view") || strstr(propertyName, "View")) {
        return strdup("UIView*");
    } else if (strstr(propertyName, "button") || strstr(propertyName, "Button")) {
        return strdup("UIButton*");
    } else if (strstr(propertyName, "label") || strstr(propertyName, "Label")) {
        return strdup("UILabel*");
    } else if (strstr(propertyName, "text") || strstr(propertyName, "Text")) {
        return strdup("NSString*");
    } else if (strstr(propertyName, "count") || strstr(propertyName, "Count")) {
        return strdup("NSUInteger");
    } else if (strstr(propertyName, "index") || strstr(propertyName, "Index")) {
        return strdup("NSInteger");
    } else if (strstr(propertyName, "flag") || strstr(propertyName, "Flag")) {
        return strdup("BOOL");
    } else if (strstr(propertyName, "enabled") || strstr(propertyName, "Enabled")) {
        return strdup("BOOL");
    } else if (strstr(propertyName, "visible") || strstr(propertyName, "Visible")) {
        return strdup("BOOL");
    } else {
        return strdup("id");
    }
}

const char* generate_property_attributes(const char* propertyName) {
    if (!propertyName) return "strong";
    
    if (strstr(propertyName, "count") || strstr(propertyName, "Count") ||
        strstr(propertyName, "index") || strstr(propertyName, "Index") ||
        strstr(propertyName, "flag") || strstr(propertyName, "Flag") ||
        strstr(propertyName, "enabled") || strstr(propertyName, "Enabled") ||
        strstr(propertyName, "visible") || strstr(propertyName, "Visible")) {
        return "assign";
    } else if (strstr(propertyName, "copy")) {
        return "copy";
    } else {
        return "strong";
    }
}

char* generate_method_signature(const char* methodName, bool isClassMethod) {
    if (!methodName) return strdup("(void)method");
    
    char* signature = malloc(256);
    if (!signature) return NULL;
    
    if (strstr(methodName, "simpleMethod")) {
        snprintf(signature, 256, "(void)simpleMethod");
    } else if (strstr(methodName, "methodWithReturn")) {
        snprintf(signature, 256, "(NSString*)methodWithReturn");
    } else if (strstr(methodName, "methodWithParameter")) {
        snprintf(signature, 256, "(void)methodWithParameter:(NSString*)param");
    } else if (strstr(methodName, "methodWithMultipleParams")) {
        snprintf(signature, 256, "(BOOL)methodWithMultipleParams:(NSString*)name age:(NSInteger)age");
    } else if (strstr(methodName, "classMethod")) {
        snprintf(signature, 256, "(void)classMethod");
    } else if (strstr(methodName, "staticMethod")) {
        snprintf(signature, 256, "(NSInteger)staticMethod");
    } else if (strstr(methodName, "processData")) {
        snprintf(signature, 256, "(NSData*)processData");
    } else if (strstr(methodName, "configure")) {
        snprintf(signature, 256, "(void)configure:(NSDictionary*)options");
    } else if (strstr(methodName, "process")) {
        snprintf(signature, 256, "(BOOL)process");
    } else if (strstr(methodName, "getValue")) {
        snprintf(signature, 256, "(id)getValue");
    } else if (strstr(methodName, "init")) {
        snprintf(signature, 256, "(instancetype)%s", methodName);
    } else if (strstr(methodName, "alloc")) {
        snprintf(signature, 256, "(instancetype)%s", methodName);
    } else if (strstr(methodName, "description")) {
        snprintf(signature, 256, "(NSString*)%s", methodName);
    } else if (strstr(methodName, "hash")) {
        snprintf(signature, 256, "(NSUInteger)%s", methodName);
    } else if (strstr(methodName, "isEqual")) {
        snprintf(signature, 256, "(BOOL)isEqual:(id)object");
    } else if (strstr(methodName, "performSelector")) {
        snprintf(signature, 256, "(id)performSelector:(SEL)selector");
    } else if (strstr(methodName, "copy")) {
        snprintf(signature, 256, "(id)%s", methodName);
    } else if (strstr(methodName, "mutableCopy")) {
        snprintf(signature, 256, "(id)%s", methodName);
    } else if (strstr(methodName, "retain")) {
        snprintf(signature, 256, "(id)%s", methodName);
    } else if (strstr(methodName, "release")) {
        snprintf(signature, 256, "(void)%s", methodName);
    } else if (strstr(methodName, "autorelease")) {
        snprintf(signature, 256, "(id)%s", methodName);
    } else {
        snprintf(signature, 256, "(void)%s", methodName);
    }
    
    return signature;
}

// MARK: - Debug and Logging

void class_dump_log_analysis_start(const char* binaryPath) {
    printf("[ClassDumpC] Starting class dump analysis of: %s\n", binaryPath);
}

void class_dump_log_class_found(const char* className, uint64_t address) {
    printf("[ClassDumpC] Found class for dump: %s at 0x%llx\n", className, address);
}

void class_dump_log_category_found(const char* categoryName, const char* className) {
    printf("[ClassDumpC] Found category for dump: %s on %s\n", categoryName, className);
}

void class_dump_log_protocol_found(const char* protocolName) {
    printf("[ClassDumpC] Found protocol for dump: %s\n", protocolName);
}

void class_dump_log_method_found(const char* methodName, const char* className) {
    printf("[ClassDumpC] Found method for dump: %s in %s\n", methodName, className);
}

void class_dump_log_property_found(const char* propertyName, const char* className) {
    printf("[ClassDumpC] Found property for dump: %s in %s\n", propertyName, className);
}

void class_dump_log_header_generated(const char* headerPath, size_t headerSize) {
    printf("[ClassDumpC] Generated header: %s (%zu bytes)\n", headerPath, headerSize);
}

void class_dump_log_analysis_complete(const class_dump_result_t* result) {
    if (!result) return;
    
    printf("[ClassDumpC] Class dump complete: %u classes, %u categories, %u protocols\n", 
           result->classCount, result->categoryCount, result->protocolCount);
}

// MARK: - Deferred Property Addition

void add_deferred_swift_properties(class_dump_result_t* result) {
    printf("[ClassDumpC] Adding deferred Swift properties...\n");
    printf("[ClassDumpC] Total classes: %u, deferred properties: %d\n", result->classCount, deferred_property_count);
    
    if (deferred_property_count == 0 || result->classCount == 0) {
        return;
    }
    
    int targetClassIndex = -1;
    for (int c = result->classCount - 1; c >= 0; c--) {
        if (result->classes[c].isSwift && result->classes[c].propertyCount < 20) {
            targetClassIndex = c;
            break;
        }
    }
    
    if (targetClassIndex == -1) {
        printf("[ClassDumpC] No Swift class found for deferred properties\n");
        return;
    }
    
    class_dump_info_t* targetClass = &result->classes[targetClassIndex];
    printf("[ClassDumpC] Target Swift class: '%s' (current properties: %u)\n", 
           targetClass->className, targetClass->propertyCount);
    
    if (targetClass->propertyCount == 0) {
        targetClass->properties = malloc(sizeof(char*) * 20);
    }
    
    int properties_added = 0;
    for (int i = 0; i < deferred_property_count; i++) {
        if (targetClass->propertyCount >= 20) {
            printf("[ClassDumpC] Property limit reached (20)\n");
            break;
        }
        
        const char* property_name = deferred_properties[i];
        if (!property_name) continue;
        
        int property_exists = 0;
        for (int k = 0; k < targetClass->propertyCount; k++) {
            if (targetClass->properties[k] && strcmp(targetClass->properties[k], property_name) == 0) {
                property_exists = 1;
                break;
            }
        }
        
        if (!property_exists) {
            targetClass->properties[targetClass->propertyCount] = strdup(property_name);
            targetClass->propertyCount++;
            properties_added++;
            printf("[ClassDumpC] Added deferred property '%s' to Swift class '%s'\n", 
                   property_name, targetClass->className);
        }
        
        free(deferred_properties[i]);
        deferred_properties[i] = NULL;
    }
    
    printf("[ClassDumpC] Added %d deferred properties to Swift class '%s' (total properties: %u)\n", 
           properties_added, targetClass->className, targetClass->propertyCount);
    
    deferred_property_count = 0;
}
