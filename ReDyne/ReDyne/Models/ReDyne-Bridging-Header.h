#ifndef ReDyne_Bridging_Header_h
#define ReDyne_Bridging_Header_h

#import "TypeAnalyzerC.h"
#import "ObjCRuntimeC.h"
#import "ClassDumpC.h"

typedef struct {
    char* className;
    char* superclassName;
    char** protocols;
    uint32_t protocolCount;
    char** instanceMethods;
    uint32_t instanceMethodCount;
    char** classMethods;
    uint32_t classMethodCount;
    char** properties;
    uint32_t propertyCount;
    char** ivars;
    uint32_t ivarCount;
    bool isSwift;
    bool isMetaClass;
} class_dump_info_t;

typedef struct {
    char* categoryName;
    char* className;
    char** protocols;
    uint32_t protocolCount;
    char** instanceMethods;
    uint32_t instanceMethodCount;
    char** classMethods;
    uint32_t classMethodCount;
    char** properties;
    uint32_t propertyCount;
} category_dump_info_t;

typedef struct {
    char* protocolName;
    char** protocols;
    uint32_t protocolCount;
    char** methods;
    uint32_t methodCount;
} protocol_dump_info_t;

typedef struct {
    class_dump_info_t* classes;
    uint32_t classCount;
    category_dump_info_t* categories;
    uint32_t categoryCount;
    protocol_dump_info_t* protocols;
    uint32_t protocolCount;
    char* generatedHeader;
    size_t headerSize;
} class_dump_result_t;

@_silgen_name("class_dump_binary")
extern class_dump_result_t* class_dump_binary(const char* binaryPath);

@_silgen_name("class_dump_free_result")
extern void class_dump_free_result(class_dump_result_t* result);

@_silgen_name("objc_analyze_binary")
extern bool objc_analyze_binary(const char* binaryPath);

@_silgen_name("objc_find_classes")
extern bool objc_find_classes(const char* binaryData);

@_silgen_name("objc_find_categories")
extern bool objc_find_categories(const char* binaryData);

@_silgen_name("objc_find_protocols")
extern bool objc_find_protocols(const char* binaryData);

#endif
