#ifndef ClassDumpC_h
#define ClassDumpC_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

// MARK: - Class Dump Data Structures

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

// MARK: - C Function Declarations

class_dump_result_t* class_dump_binary(const char* binaryPath);

char* class_dump_generate_header(const char* binaryPath);
char* class_dump_generate_class_header(class_dump_info_t* classInfo);
char* class_dump_generate_category_header(category_dump_info_t* categoryInfo);
char* class_dump_generate_protocol_header(protocol_dump_info_t* protocolInfo);

bool class_dump_analyze_classes(const char* binaryData, size_t binarySize, class_dump_result_t* result);
bool class_dump_analyze_categories(const char* binaryData, size_t binarySize, class_dump_result_t* result);
bool class_dump_analyze_protocols(const char* binaryData, size_t binarySize, class_dump_result_t* result);

char* class_dump_extract_method_signature(const char* methodData, const char* methodName, bool isClassMethod);
char* class_dump_extract_property_declaration(const char* propertyData, const char* propertyName);
char* class_dump_extract_ivar_declaration(const char* ivarData, const char* ivarName);
char* class_dump_decode_type_encoding(const char* encoding);
char* class_dump_extract_property_type(const char* attributes);
char* class_dump_decode_method_return_type(const char* methodData);
char** class_dump_extract_method_parameters(const char* methodData, uint32_t* parameterCount);
char* class_dump_extract_class_name(const char* symbolName);
char* class_dump_extract_category_name(const char* symbolName);
char* class_dump_extract_protocol_name(const char* symbolName);
char* class_dump_extract_method_name(const char* methodData);
char* class_dump_extract_property_name(const char* propertyData);
char* class_dump_extract_ivar_name(const char* ivarData);
char* class_dump_format_class_interface(class_dump_info_t* classInfo);
char* class_dump_format_class_implementation(class_dump_info_t* classInfo);
char* class_dump_format_category_interface(category_dump_info_t* categoryInfo);
char* class_dump_format_category_implementation(category_dump_info_t* categoryInfo);
char* class_dump_format_protocol_declaration(protocol_dump_info_t* protocolInfo);
char* class_dump_generate_method_signature(const char* methodName, const char* types, bool isClassMethod);
char* class_dump_generate_property_signature(const char* propertyName, const char* attributes);
char* class_dump_generate_ivar_signature(const char* ivarName, const char* type);
char* class_dump_convert_type_encoding_to_objc(const char* encoding);
char* class_dump_convert_property_attributes_to_objc(const char* attributes);
char* class_dump_convert_ivar_type_to_objc(const char* ivarType);

void class_dump_free_class_info(class_dump_info_t* classInfo);
void class_dump_free_category_info(category_dump_info_t* categoryInfo);
void class_dump_free_protocol_info(protocol_dump_info_t* protocolInfo);
void class_dump_free_result(class_dump_result_t* result);

bool class_dump_is_swift_class(const char* className);
bool class_dump_is_meta_class(const char* className);
bool class_dump_is_class_method(const char* methodName);
bool class_dump_is_instance_method(const char* methodName);
bool class_dump_is_optional_method(const char* methodName);

void analyze_symbol_table_for_objc(const char* binaryData, size_t binarySize, class_dump_result_t* result);
void analyze_objc_runtime_sections(const char* binaryData, size_t binarySize, class_dump_result_t* result);
void analyze_strings_for_objc(const char* binaryData, size_t binarySize, class_dump_result_t* result);
void add_class_to_result(class_dump_result_t* result, const char* className);
void add_category_to_result(class_dump_result_t* result, const char* categoryName);
void add_protocol_to_result(class_dump_result_t* result, const char* protocolName);
void analyze_class_methods_and_properties(const char* className, class_dump_info_t* classInfo);
void analyze_classlist_section(const char* binaryData, size_t binarySize, class_dump_result_t* result);
void analyze_catlist_section(const char* binaryData, size_t binarySize, class_dump_result_t* result);
void analyze_protolist_section(const char* binaryData, size_t binarySize, class_dump_result_t* result);
void analyze_method_list_section(const char* binaryData, size_t binarySize, class_dump_result_t* result);
void analyze_prop_list_section(const char* binaryData, size_t binarySize, class_dump_result_t* result);
void analyze_ivar_list_section(const char* binaryData, size_t binarySize, class_dump_result_t* result);
void parse_symtab_command(const char* binaryData, size_t binarySize, uint64_t offset, class_dump_result_t* result);
void parse_dysymtab_command(const char* binaryData, size_t binarySize, uint64_t offset, class_dump_result_t* result);
void parse_segment_command(const char* binaryData, size_t binarySize, uint64_t offset, class_dump_result_t* result, bool is64bit);
void analyze_swift_symbols(const char* binaryData, size_t binarySize, class_dump_result_t* result);
void analyze_swift5_metadata(const char* binaryData, size_t binarySize, class_dump_result_t* result);
void analyze_swift_reflection_strings(const char* data, size_t size, class_dump_result_t* result);
void analyze_swift_type_references(const char* data, size_t size, class_dump_result_t* result);
int is_valid_property_name(const char* name);
void extract_properties_from_mangled_name(const char* mangledName, class_dump_result_t* result);
void analyze_classlist_section_from_segment(const char* binaryData, size_t binarySize, uint64_t sectionOffset, class_dump_result_t* result, bool is64bit);
void analyze_catlist_section_from_segment(const char* binaryData, size_t binarySize, uint64_t sectionOffset, class_dump_result_t* result, bool is64bit);
void analyze_protolist_section_from_segment(const char* binaryData, size_t binarySize, uint64_t sectionOffset, class_dump_result_t* result, bool is64bit);
bool find_section_in_binary(const char* binaryData, size_t binarySize, const char* segname, const char* sectname);
char* extract_class_name_from_symbol(const char* symbolName);
char* extract_category_name_from_symbol(const char* symbolName);
char* extract_protocol_name_from_symbol(const char* symbolName);
char* generate_property_type(const char* propertyName);
const char* generate_property_attributes(const char* propertyName);
char* generate_method_signature(const char* methodName, bool isClassMethod);

// Generate header from parsed results
void generate_header_from_result(class_dump_result_t* result);
void class_dump_log_analysis_start(const char* binaryPath);
void class_dump_log_class_found(const char* className, uint64_t address);
void class_dump_log_category_found(const char* categoryName, const char* className);
void class_dump_log_protocol_found(const char* protocolName);
void class_dump_log_method_found(const char* methodName, const char* className);
void class_dump_log_property_found(const char* propertyName, const char* className);
void class_dump_log_header_generated(const char* headerPath, size_t headerSize);
void class_dump_log_analysis_complete(const class_dump_result_t* result);

// Deferred property addition for Swift classes
void add_deferred_swift_properties(class_dump_result_t* result);

#endif
