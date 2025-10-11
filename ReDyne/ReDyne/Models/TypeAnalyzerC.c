#include "TypeAnalyzerC.h"
#include <string.h>
#include <stdlib.h>

// MARK: - Symbol Analysis Helpers

bool c_is_class_symbol(const char* name) {
    if (!name) return false;
    
    return strstr(name, "_OBJC_CLASS_$_") != NULL ||
           strstr(name, "Class") != NULL ||
           strstr(name, "class") != NULL ||
           strstr(name, "_class_") != NULL;
}

bool c_is_struct_symbol(const char* name) {
    if (!name) return false;
    
    return strstr(name, "struct") != NULL ||
           strstr(name, "Struct") != NULL ||
           strstr(name, "_struct_") != NULL;
}

bool c_is_enum_symbol(const char* name) {
    if (!name) return false;
    
    return strstr(name, "enum") != NULL ||
           strstr(name, "Enum") != NULL ||
           strstr(name, "_enum_") != NULL;
}

bool c_is_protocol_symbol(const char* name) {
    if (!name) return false;
    
    return strstr(name, "protocol") != NULL ||
           strstr(name, "Protocol") != NULL ||
           strstr(name, "_protocol_") != NULL;
}

bool c_is_function_symbol(const char* name) {
    if (!name) return false;
    
    return name[0] == '_' && 
           (strstr(name, "func") != NULL || 
            strstr(name, "method") != NULL ||
            strstr(name, "selector") != NULL);
}

bool c_is_property_symbol(const char* name, const char* typeName) {
    if (!name || !typeName) return false;
    
    return strstr(name, typeName) != NULL &&
           (strstr(name, "property") != NULL ||
            strstr(name, "field") != NULL ||
            strstr(name, "member") != NULL ||
            strstr(name, "ivar") != NULL ||
            strstr(name, "_") != NULL);
}

bool c_is_method_symbol(const char* name, const char* typeName) {
    if (!name || !typeName) return false;
    
    return strstr(name, typeName) != NULL &&
           (strstr(name, "method") != NULL ||
            strstr(name, "func") != NULL ||
            strstr(name, "selector") != NULL ||
            strstr(name, "imp") != NULL);
}

bool c_is_enum_case_symbol(const char* name, const char* enumName) {
    if (!name || !enumName) return false;
    
    return strstr(name, enumName) != NULL &&
           (strstr(name, "case") != NULL ||
            strstr(name, "value") != NULL ||
            strstr(name, "option") != NULL);
}

// MARK: - Name Extraction Helpers

char* c_extract_class_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_OBJC_CLASS_$_")) {
        return strdup(symbolName + 14);
    }
    
    return strdup(symbolName);
}

char* c_extract_struct_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_struct_")) {
        return strdup(symbolName + 8);
    }
    
    return strdup(symbolName);
}

char* c_extract_enum_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_enum_")) {
        return strdup(symbolName + 6);
    }
    
    return strdup(symbolName);
}

char* c_extract_protocol_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_protocol_")) {
        return strdup(symbolName + 10);
    }
    
    return strdup(symbolName);
}

char* c_extract_function_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (symbolName[0] == '_') {
        return strdup(symbolName + 1);
    }
    
    return strdup(symbolName);
}

char* c_extract_property_name(const char* name, const char* typeName) {
    if (!name || !typeName) return NULL;
    
    const char* typePos = strstr(name, typeName);
    if (typePos) {
        const char* nameStart = typePos + strlen(typeName);
        if (*nameStart == '_') {
            nameStart++;
        }
        return strdup(nameStart);
    }
    
    return strdup(name);
}

char* c_extract_method_name(const char* name, const char* typeName) {
    if (!name || !typeName) return NULL;
    
    const char* typePos = strstr(name, typeName);
    if (typePos) {
        const char* nameStart = typePos + strlen(typeName);
        if (*nameStart == '_') {
            nameStart++;
        }
        return strdup(nameStart);
    }
    
    return strdup(name);
}

char* c_extract_enum_case_name(const char* name, const char* enumName) {
    if (!name || !enumName) return NULL;
    
    const char* enumPos = strstr(name, enumName);
    if (enumPos) {
        const char* nameStart = enumPos + strlen(enumName);
        if (*nameStart == '_') {
            nameStart++;
        }
        return strdup(nameStart);
    }
    
    return strdup(name);
}

// MARK: - Type Inference Helpers

char* c_infer_property_type(const char* name, uint64_t size) {
    if (!name) return NULL;
    
    char* type = malloc(32);
    if (!type) return NULL;
    
    if (strstr(name, "string") || strstr(name, "str")) {
        strcpy(type, "String");
    } else if (strstr(name, "int") || strstr(name, "number")) {
        strcpy(type, "Int");
    } else if (strstr(name, "bool") || strstr(name, "flag")) {
        strcpy(type, "Bool");
    } else if (strstr(name, "float") || strstr(name, "double")) {
        strcpy(type, "Double");
    } else if (size == 8) {
        strcpy(type, "Int64");
    } else if (size == 4) {
        strcpy(type, "Int32");
    } else if (size == 2) {
        strcpy(type, "Int16");
    } else if (size == 1) {
        strcpy(type, "Int8");
    } else {
        strcpy(type, "Any");
    }
    
    return type;
}

char* c_infer_return_type(const char* name, uint64_t size) {
    if (!name) return NULL;
    
    char* type = malloc(32);
    if (!type) return NULL;
    
    if (strstr(name, "init") || strstr(name, "alloc")) {
        strcpy(type, "Self");
    } else if (strstr(name, "bool") || strstr(name, "flag")) {
        strcpy(type, "Bool");
    } else if (strstr(name, "string") || strstr(name, "str")) {
        strcpy(type, "String");
    } else if (strstr(name, "int") || strstr(name, "number")) {
        strcpy(type, "Int");
    } else if (strstr(name, "void") || strstr(name, "empty")) {
        strcpy(type, "Void");
    } else {
        strcpy(type, "Any");
    }
    
    return type;
}

int c_infer_access_level(const char* name) {
    if (!name) return 0;
    
    if (strstr(name, "private") || strstr(name, "_private")) {
        return 2;
    } else if (strstr(name, "fileprivate") || strstr(name, "_fileprivate")) {
        return 3;
    } else if (strstr(name, "internal") || strstr(name, "_internal")) {
        return 1;
    } else if (strstr(name, "open") || strstr(name, "_open")) {
        return 4;
    } else {
        return 0;
    }
}

// MARK: - String Parsing Helpers

bool c_contains_class_definition(const char* string) {
    if (!string) return false;
    
    return strstr(string, "class ") != NULL && strstr(string, ":") != NULL;
}

bool c_contains_struct_definition(const char* string) {
    if (!string) return false;
    
    return strstr(string, "struct ") != NULL && strstr(string, "{") != NULL;
}

bool c_contains_enum_definition(const char* string) {
    if (!string) return false;
    
    return strstr(string, "enum ") != NULL && strstr(string, "case") != NULL;
}

char* c_extract_type_name_from_string(const char* string, const char* keyword) {
    if (!string || !keyword) return NULL;
    
    char* keywordPos = strstr(string, keyword);
    if (!keywordPos) return NULL;
    
    char* nameStart = keywordPos + strlen(keyword);
    while (*nameStart == ' ') nameStart++;
    
    char* nameEnd = nameStart;
    while (*nameEnd && *nameEnd != ' ' && *nameEnd != ':' && *nameEnd != '{') {
        nameEnd++;
    }
    
    int nameLen = (int)(nameEnd - nameStart);
    if (nameLen <= 0) return NULL;
    
    char* typeName = malloc(nameLen + 1);
    if (!typeName) return NULL;
    
    strncpy(typeName, nameStart, nameLen);
    typeName[nameLen] = '\0';
    
    return typeName;
}

// MARK: - Binary Analysis Helpers

uint64_t c_estimate_class_size(const char* className) {
    if (!className) return 64;
    
    if (strstr(className, "View") || strstr(className, "Controller")) {
        return 200;
    } else if (strstr(className, "Model")) {
        return 100;
    } else if (strstr(className, "Manager")) {
        return 150;
    } else {
        return 64;
    }
}

uint64_t c_estimate_struct_size(const char* structName) {
    if (!structName) return 24;
    
    if (strstr(structName, "Point") || strstr(structName, "Size")) {
        return 16;
    } else if (strstr(structName, "Rect")) {
        return 32;
    } else if (strstr(structName, "Range")) {
        return 16;
    } else {
        return 24;
    }
}

uint64_t c_estimate_enum_size(const char* enumName) {
    if (!enumName) return 4;
    
    if (strstr(enumName, "Int") || strstr(enumName, "Raw")) {
        return 8;
    } else {
        return 4;
    }
}

// MARK: - Memory Management

void c_free_string(char* str) {
    if (str) {
        free(str);
    }
}
