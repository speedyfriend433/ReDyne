#ifndef ObjCRuntimeC_h
#define ObjCRuntimeC_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "ObjCParser.h"

// MARK: - C ObjC Runtime Helper Functions


ObjCRuntimeInfo* objc_analyze_binary(const char* binaryPath);
void objc_free_runtime_info(ObjCRuntimeInfo* info);

bool objc_find_classes(const char* binaryPath);
bool objc_find_categories(const char* binaryPath);
bool objc_find_protocols(const char* binaryPath);
bool objc_analyze_methods(const char* binaryPath);
bool objc_analyze_properties(const char* binaryPath);
bool objc_analyze_ivars(const char* binaryPath);

char* objc_extract_class_name(const char* symbolName);
char* objc_extract_category_name(const char* symbolName);
char* objc_extract_protocol_name(const char* symbolName);
char* objc_extract_method_name(const char* methodData);
char* objc_extract_property_name(const char* propertyData);
char* objc_decode_type_encoding(const char* encoding);
char* objc_extract_property_type(const char* attributes);
char* objc_extract_ivar_type(const char* ivarData);

uint64_t objc_find_class_list(const char* binaryData, size_t binarySize);
uint64_t objc_find_category_list(const char* binaryData, size_t binarySize);
uint64_t objc_find_protocol_list(const char* binaryData, size_t binarySize);
uint64_t objc_find_method_list(const char* classData, size_t classSize);
uint64_t objc_find_property_list(const char* classData, size_t classSize);
uint64_t objc_find_ivar_list(const char* classData, size_t classSize);

bool objc_is_swift_class(const char* className);
bool objc_is_meta_class(const char* className);
bool objc_is_class_method(const char* methodName);
bool objc_is_instance_method(const char* methodName);

void objc_free_string(char* str);
void objc_log_analysis_start(const char* binaryPath);
void objc_log_class_found(const char* className, uint64_t address);
void objc_log_category_found(const char* categoryName, const char* className);
void objc_log_protocol_found(const char* protocolName);
void objc_log_method_found(const char* methodName, const char* className);
void objc_log_property_found(const char* propertyName, const char* className);
void objc_log_analysis_complete(int classCount, int categoryCount, int protocolCount);

#endif
