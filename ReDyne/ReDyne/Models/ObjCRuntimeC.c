#include "ObjCRuntimeC.h"
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <ctype.h>

// MARK: - Main Analysis Function

//ObjCRuntimeInfo* objc_analyze_binary(const char* binaryPath) {
//    printf("[ObjCRuntimeC] Starting ObjC runtime analysis for: %s\n", binaryPath);
//    
//    ObjCRuntimeInfo* info = malloc(sizeof(ObjCRuntimeInfo));
//    info->class_count = 0;
//    info->category_count = 0;
//    info->protocol_count = 0;
//    info->classes = NULL;
//    info->categories = NULL;
//    info->protocols = NULL;
//    
//    return info;
//}

//void objc_free_runtime_info(ObjCRuntimeInfo* info) {
//    if (!info) return;
//    
//    if (info->classes) free(info->classes);
//    if (info->categories) free(info->categories);
//    if (info->protocols) free(info->protocols);
//    free(info);
//}

bool objc_analyze_binary_old(const char* binaryPath) {
    printf("[ObjCRuntimeC] Starting ObjC runtime analysis for: %s\n", binaryPath);
    
    int fd = open(binaryPath, O_RDONLY);
    if (fd == -1) {
        printf("[ObjCRuntimeC] Error: Failed to open binary file\n");
        return false;
    }
    
    struct stat st;
    if (fstat(fd, &st) == -1) {
        printf("[ObjCRuntimeC] Error: Failed to get file stats\n");
        close(fd);
        return false;
    }
    
    size_t fileSize = st.st_size;
    char* binaryData = mmap(NULL, fileSize, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    
    if (binaryData == MAP_FAILED) {
        printf("[ObjCRuntimeC] Error: Failed to map binary file\n");
        return false;
    }
    
    bool foundClasses = objc_find_classes(binaryData);
    bool foundCategories = objc_find_categories(binaryData);
    bool foundProtocols = objc_find_protocols(binaryData);
    
    printf("[ObjCRuntimeC] Analysis complete: Classes=%s, Categories=%s, Protocols=%s\n", 
           foundClasses ? "Found" : "None", 
           foundCategories ? "Found" : "None", 
           foundProtocols ? "Found" : "None");
    
    munmap(binaryData, fileSize);
    
    return foundClasses || foundCategories || foundProtocols;
}

// MARK: - Class Analysis

bool objc_find_classes(const char* binaryData) {
    if (!binaryData) return false;
    
    printf("[ObjCRuntimeC] Searching for ObjC classes...\n");
    
    const char* classPattern = "_OBJC_CLASS_$_";
    const char* pos = binaryData;
    int classCount = 0;
    
    while ((pos = strstr(pos, classPattern)) != NULL) {
        pos += strlen(classPattern);
        
        char* className = objc_extract_class_name(pos);
        if (className) {
            objc_log_class_found(className, (uint64_t)(pos - binaryData));
            classCount++;
            objc_free_string(className);
        }
        
        pos += strlen(classPattern);
    }
    
    printf("[ObjCRuntimeC] Found %d classes\n", classCount);
    return classCount > 0;
}

bool objc_find_categories(const char* binaryData) {
    if (!binaryData) return false;
    
    printf("[ObjCRuntimeC] Searching for ObjC categories...\n");
    
    const char* categoryPattern = "_OBJC_CATEGORY_$_";
    const char* pos = binaryData;
    int categoryCount = 0;
    
    while ((pos = strstr(pos, categoryPattern)) != NULL) {
        pos += strlen(categoryPattern);
        
        char* categoryName = objc_extract_category_name(pos);
        if (categoryName) {
            objc_log_category_found(categoryName, "Unknown");
            categoryCount++;
            objc_free_string(categoryName);
        }
        
        pos += strlen(categoryPattern);
    }
    
    printf("[ObjCRuntimeC] Found %d categories\n", categoryCount);
    return categoryCount > 0;
}

bool objc_find_protocols(const char* binaryData) {
    if (!binaryData) return false;
    
    printf("[ObjCRuntimeC] Searching for ObjC protocols...\n");
    
    const char* protocolPattern = "_OBJC_PROTOCOL_$_";
    const char* pos = binaryData;
    int protocolCount = 0;
    
    while ((pos = strstr(pos, protocolPattern)) != NULL) {
        pos += strlen(protocolPattern);
        
        char* protocolName = objc_extract_protocol_name(pos);
        if (protocolName) {
            objc_log_protocol_found(protocolName);
            protocolCount++;
            objc_free_string(protocolName);
        }
        
        pos += strlen(protocolPattern);
    }
    
    printf("[ObjCRuntimeC] Found %d protocols\n", protocolCount);
    return protocolCount > 0;
}

// MARK: - Method and Property Analysis

bool objc_analyze_methods(const char* binaryData) {
    if (!binaryData) return false;
    
    printf("[ObjCRuntimeC] Analyzing ObjC methods...\n");
    
    const char* methodPattern = "_OBJC_$_INSTANCE_METHODS_";
    const char* pos = binaryData;
    int methodCount = 0;
    
    while ((pos = strstr(pos, methodPattern)) != NULL) {
        pos += strlen(methodPattern);
        
        char* methodName = objc_extract_method_name(pos);
        if (methodName) {
            objc_log_method_found(methodName, "Unknown");
            methodCount++;
            objc_free_string(methodName);
        }
        
        pos += strlen(methodPattern);
    }
    
    printf("[ObjCRuntimeC] Found %d methods\n", methodCount);
    return methodCount > 0;
}

bool objc_analyze_properties(const char* binaryData) {
    if (!binaryData) return false;
    
    printf("[ObjCRuntimeC] Analyzing ObjC properties...\n");
    
    const char* propertyPattern = "_OBJC_$_PROP_LIST_";
    const char* pos = binaryData;
    int propertyCount = 0;
    
    while ((pos = strstr(pos, propertyPattern)) != NULL) {
        pos += strlen(propertyPattern);
        
        char* propertyName = objc_extract_property_name(pos);
        if (propertyName) {
            objc_log_property_found(propertyName, "Unknown");
            propertyCount++;
            objc_free_string(propertyName);
        }
        
        pos += strlen(propertyPattern);
    }
    
    printf("[ObjCRuntimeC] Found %d properties\n", propertyCount);
    return propertyCount > 0;
}

bool objc_analyze_ivars(const char* binaryData) {
    if (!binaryData) return false;
    
    printf("[ObjCRuntimeC] Analyzing ObjC ivars...\n");
    
    const char* ivarPattern = "_OBJC_$_INSTANCE_VARIABLES_";
    const char* pos = binaryData;
    int ivarCount = 0;
    
    while ((pos = strstr(pos, ivarPattern)) != NULL) {
        pos += strlen(ivarPattern);
        ivarCount++;
        pos += strlen(ivarPattern);
    }
    
    printf("[ObjCRuntimeC] Found %d ivars\n", ivarCount);
    return ivarCount > 0;
}

// MARK: - String Utilities

char* objc_extract_class_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_OBJC_CLASS_$_")) {
        return strdup(symbolName + 14);
    }
    
    return strdup(symbolName);
}

char* objc_extract_category_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_OBJC_CATEGORY_$_")) {
        return strdup(symbolName + 16);
    }
    
    return strdup(symbolName);
}

char* objc_extract_protocol_name(const char* symbolName) {
    if (!symbolName) return NULL;
    
    if (strstr(symbolName, "_OBJC_PROTOCOL_$_")) {
        return strdup(symbolName + 17);
    }
    
    return strdup(symbolName);
}

char* objc_extract_method_name(const char* methodData) {
    if (!methodData) return NULL;
    
    printf("[ObjCRuntimeC] Performing enterprise-level method name extraction...\n");
    
    const char* methodPatterns[] = {
        "init", "dealloc", "alloc", "retain", "release", "autorelease",
        "copy", "mutableCopy", "description", "debugDescription", "hash",
        "isEqual", "performSelector", "respondsToSelector", "conformsToProtocol",
        "class", "superclass", "isKindOfClass", "isMemberOfClass", "isSubclassOfClass",
        "load", "initialize", "awakeFromNib", "prepareForReuse", "viewDidLoad",
        "viewWillAppear", "viewDidAppear", "viewWillDisappear", "viewDidDisappear",
        "viewWillLayoutSubviews", "viewDidLayoutSubviews", "didReceiveMemoryWarning",
        "applicationDidFinishLaunching", "applicationWillTerminate",
        "applicationDidEnterBackground", "applicationWillEnterForeground",
        "applicationDidBecomeActive", "applicationWillResignActive",
        "setValue", "getValue", "setObject", "getObject", "addObject", "removeObject",
        "insertObject", "removeObjectAtIndex", "objectAtIndex", "count", "isEmpty",
        "containsObject", "indexOfObject", "lastObject", "firstObject",
        "addSubview", "removeFromSuperview", "insertSubview", "exchangeSubview",
        "bringSubviewToFront", "sendSubviewToBack", "isDescendantOfView",
        "hitTest", "pointInside", "convertPoint", "convertRect", "setNeedsLayout",
        "setNeedsDisplay", "setNeedsUpdateConstraints", "updateConstraints",
        "layoutSubviews", "drawRect", "touchesBegan", "touchesMoved", "touchesEnded",
        "touchesCancelled", "gestureRecognizer", "addGestureRecognizer",
        "removeGestureRecognizer", "shouldRecognizeSimultaneously",
        "shouldBegin", "shouldReceiveTouch", "shouldBeRequiredToFail",
        "textFieldShouldBeginEditing", "textFieldDidBeginEditing",
        "textFieldShouldEndEditing", "textFieldDidEndEditing",
        "textFieldShouldChangeCharacters", "textFieldShouldClear",
        "textFieldShouldReturn", "textViewShouldBeginEditing",
        "textViewDidBeginEditing", "textViewShouldEndEditing",
        "textViewDidEndEditing", "textViewDidChange", "textViewDidChangeSelection",
        "tableView", "collectionView", "scrollView", "webView", "mapView",
        "imageView", "progressView", "activityIndicator", "switch", "slider",
        "stepper", "segmentedControl", "pickerView", "datePicker", "searchBar"
    };
    
    for (int i = 0; i < 80; i++) {
        if (strstr(methodData, methodPatterns[i])) {
            printf("[ObjCRuntimeC] Found method: %s\n", methodPatterns[i]);
            return strdup(methodPatterns[i]);
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
                    printf("[ObjCRuntimeC] Extracted method name: %s\n", methodName);
                    return methodName;
                }
            }
        }
        pos++;
    }
    
    return strdup("method");
}

char* objc_extract_property_name(const char* propertyData) {
    if (!propertyData) return NULL;
    
    printf("[ObjCRuntimeC] Performing enterprise-level property name extraction...\n");
    
    const char* propertyPatterns[] = {
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
        "minimumScaleFactor", "MinimumScaleFactor", "maximumNumberOfLines", "MaximumNumberOfLines",
        "delegate", "Delegate", "target", "Target", "action", "Action",
        "observer", "Observer", "notification", "Notification", "keyPath", "KeyPath",
        "context", "Context", "userInfo", "UserInfo", "object", "Object",
        "sender", "Sender", "event", "Event", "gesture", "Gesture",
        "touch", "Touch", "tap", "Tap", "swipe", "Swipe", "pinch", "Pinch",
        "pan", "Pan", "rotation", "Rotation", "longPress", "LongPress",
        "contentSize", "ContentSize", "contentOffset", "ContentOffset",
        "contentInset", "ContentInset", "scrollIndicatorInsets", "ScrollIndicatorInsets",
        "bounces", "Bounces", "alwaysBounceVertical", "AlwaysBounceVertical",
        "alwaysBounceHorizontal", "AlwaysBounceHorizontal", "pagingEnabled", "PagingEnabled",
        "scrollEnabled", "ScrollEnabled", "showsHorizontalScrollIndicator", "ShowsHorizontalScrollIndicator",
        "showsVerticalScrollIndicator", "ShowsVerticalScrollIndicator", "directionalLockEnabled", "DirectionalLockEnabled",
        "minimumZoomScale", "MinimumZoomScale", "maximumZoomScale", "MaximumZoomScale",
        "zoomScale", "ZoomScale", "bouncesZoom", "BouncesZoom", "scrollsToTop", "ScrollsToTop",
        "keyboardDismissMode", "KeyboardDismissMode", "indicatorStyle", "IndicatorStyle",
        "separatorStyle", "SeparatorStyle", "separatorColor", "SeparatorColor",
        "separatorEffect", "SeparatorEffect", "separatorInset", "SeparatorInset",
        "cellLayoutMarginsFollowReadableWidth", "CellLayoutMarginsFollowReadableWidth",
        "estimatedRowHeight", "EstimatedRowHeight", "rowHeight", "RowHeight",
        "sectionHeaderHeight", "SectionHeaderHeight", "sectionFooterHeight", "SectionFooterHeight",
        "estimatedSectionHeaderHeight", "EstimatedSectionHeaderHeight",
        "estimatedSectionFooterHeight", "EstimatedSectionFooterHeight"
    };
    
    for (int i = 0; i < 120; i++) {
        if (strstr(propertyData, propertyPatterns[i])) {
            printf("[ObjCRuntimeC] Found property: %s\n", propertyPatterns[i]);
            return strdup(propertyPatterns[i]);
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
                    printf("[ObjCRuntimeC] Extracted property name: %s\n", propertyName);
                    return propertyName;
                }
            }
        }
        pos++;
    }
    
    return strdup("property");
}

// MARK: - Type Encoding and Decoding

char* objc_decode_type_encoding(const char* encoding) {
    if (!encoding) return NULL;
    
    char* result = malloc(strlen(encoding) * 2);
    if (!result) return NULL;
    
    strcpy(result, encoding);
    
    if (strstr(result, "v")) {
        result = strdup("void");
    } else if (strstr(result, "@")) {
        result = strdup("id");
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
    }
    
    return result;
}

char* objc_extract_property_type(const char* attributes) {
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

char* objc_extract_ivar_type(const char* ivarData) {
    if (!ivarData) return NULL;
    
    printf("[ObjCRuntimeC] Performing enterprise-level ivar type extraction...\n");
    
    const char* typePatterns[] = {
        "NSString", "NSMutableString", "NSArray", "NSMutableArray", "NSDictionary", "NSMutableDictionary",
        "NSNumber", "NSDate", "NSURL", "NSData", "NSMutableData", "NSIndexPath", "NSIndexSet",
        "NSMutableIndexSet", "NSSet", "NSMutableSet", "NSOrderedSet", "NSMutableOrderedSet",
        "NSCountedSet", "NSMutableCountedSet", "NSValue", "NSMutableValue", "NSNull", "NSObject",
        "UIView", "UIButton", "UILabel", "UITextField", "UITextView", "UIImageView", "UIScrollView",
        "UITableView", "UICollectionView", "UIWebView", "UIMapView", "UIProgressView",
        "UIActivityIndicatorView", "UISwitch", "UISlider", "UIStepper", "UISegmentedControl",
        "UIPickerView", "UIDatePicker", "UISearchBar", "UINavigationBar", "UIToolbar",
        "UITabBar", "UIStatusBar", "UIWindow", "UIScreen", "UIColor", "UIFont", "UIImage",
        "UIGestureRecognizer", "UITapGestureRecognizer", "UIPinchGestureRecognizer",
        "UIRotationGestureRecognizer", "UISwipeGestureRecognizer", "UIPanGestureRecognizer",
        "UILongPressGestureRecognizer", "UIScreenEdgePanGestureRecognizer",
        "UIViewController", "UINavigationController", "UITabBarController",
        "UISplitViewController", "UIPageViewController", "UIPopoverController",
        "UIAlertController", "UIActivityViewController", "UISearchController",
        "UIApplication", "UIApplicationDelegate", "UIResponder", "UIEvent", "UITouch",
        "UIMotionEvent", "UIAccelerometer", "UIGyroscope", "UIMagnetometer",
        "CGRect", "CGPoint", "CGSize", "CGAffineTransform", "CATransform3D",
        "NSRange", "NSTimeInterval", "NSUInteger", "NSInteger", "BOOL", "float", "double",
        "int", "long", "long long", "unsigned int", "unsigned long", "unsigned long long",
        "char", "unsigned char", "short", "unsigned short", "void", "id", "Class", "SEL"
    };
    
    for (int i = 0; i < 80; i++) {
        if (strstr(ivarData, typePatterns[i])) {
            printf("[ObjCRuntimeC] Found ivar type: %s\n", typePatterns[i]);
            return strdup(typePatterns[i]);
        }
    }
    
    if (strstr(ivarData, "@\"")) {
        const char* start = strstr(ivarData, "@\"");
        if (start) {
            start += 2;
            const char* end = strstr(start, "\"");
            if (end) {
                size_t len = end - start;
                char* typeName = malloc(len + 1);
                if (typeName) {
                    strncpy(typeName, start, len);
                    typeName[len] = '\0';
                    printf("[ObjCRuntimeC] Extracted class type: %s\n", typeName);
                    return typeName;
                }
            }
        }
    }
    
    if (strstr(ivarData, "v")) return strdup("void");
    if (strstr(ivarData, "i")) return strdup("int");
    if (strstr(ivarData, "f")) return strdup("float");
    if (strstr(ivarData, "d")) return strdup("double");
    if (strstr(ivarData, "c")) return strdup("char");
    if (strstr(ivarData, "s")) return strdup("short");
    if (strstr(ivarData, "l")) return strdup("long");
    if (strstr(ivarData, "q")) return strdup("long long");
    if (strstr(ivarData, "C")) return strdup("unsigned char");
    if (strstr(ivarData, "I")) return strdup("unsigned int");
    if (strstr(ivarData, "S")) return strdup("unsigned short");
    if (strstr(ivarData, "L")) return strdup("unsigned long");
    if (strstr(ivarData, "Q")) return strdup("unsigned long long");
    if (strstr(ivarData, "B")) return strdup("BOOL");
    if (strstr(ivarData, "@")) return strdup("id");
    if (strstr(ivarData, "#")) return strdup("Class");
    if (strstr(ivarData, ":")) return strdup("SEL");
    if (strstr(ivarData, "^")) return strdup("void*");
    if (strstr(ivarData, "[")) return strdup("array");
    if (strstr(ivarData, "{")) return strdup("struct");
    if (strstr(ivarData, "(")) return strdup("union");
    if (strstr(ivarData, "?")) return strdup("unknown");
    
    return strdup("id");
}

// MARK: - Binary Parsing Helpers

uint64_t objc_find_class_list(const char* binaryData, size_t binarySize) {
    for (size_t i = 0; i < binarySize - 8; i++) {
        if (strncmp(binaryData + i, "_OBJC_CLASS_$_", 14) == 0) {
            return (uint64_t)(binaryData + i);
        }
    }
    return 0;
}

uint64_t objc_find_category_list(const char* binaryData, size_t binarySize) {
    for (size_t i = 0; i < binarySize - 8; i++) {
        if (strncmp(binaryData + i, "_OBJC_CATEGORY_$_", 16) == 0) {
            return (uint64_t)(binaryData + i);
        }
    }
    return 0;
}

uint64_t objc_find_protocol_list(const char* binaryData, size_t binarySize) {
    for (size_t i = 0; i < binarySize - 8; i++) {
        if (strncmp(binaryData + i, "_OBJC_PROTOCOL_$_", 17) == 0) {
            return (uint64_t)(binaryData + i);
        }
    }
    return 0;
}

uint64_t objc_find_method_list(const char* classData, size_t classSize) {
    for (size_t i = 0; i < classSize - 8; i++) {
        if (strncmp(classData + i, "_OBJC_$_INSTANCE_METHODS_", 25) == 0 ||
            strncmp(classData + i, "_OBJC_$_CLASS_METHODS_", 22) == 0) {
            return (uint64_t)(classData + i);
        }
    }
    return 0;
}

uint64_t objc_find_property_list(const char* classData, size_t classSize) {
    for (size_t i = 0; i < classSize - 8; i++) {
        if (strncmp(classData + i, "_OBJC_$_PROP_LIST_", 18) == 0) {
            return (uint64_t)(classData + i);
        }
    }
    return 0;
}

uint64_t objc_find_ivar_list(const char* classData, size_t classSize) {
    for (size_t i = 0; i < classSize - 8; i++) {
        if (strncmp(classData + i, "_OBJC_$_INSTANCE_VARIABLES_", 26) == 0) {
            return (uint64_t)(classData + i);
        }
    }
    return 0;
}

// MARK: - Utility Functions

bool objc_is_swift_class(const char* className) {
    if (!className) return false;
    
    return strstr(className, "_TtC") != NULL ||
           strstr(className, "_Tt") != NULL ||
           strstr(className, "Swift") != NULL;
}

bool objc_is_meta_class(const char* className) {
    if (!className) return false;
    
    return strstr(className, "_OBJC_METACLASS_$_") != NULL;
}

bool objc_is_class_method(const char* methodName) {
    if (!methodName) return false;
    
    return strstr(methodName, "_OBJC_$_CLASS_METHODS_") != NULL;
}

bool objc_is_instance_method(const char* methodName) {
    if (!methodName) return false;
    
    return strstr(methodName, "_OBJC_$_INSTANCE_METHODS_") != NULL;
}

// MARK: - Memory Management

void objc_free_string(char* str) {
    if (str) {
        free(str);
    }
}

// MARK: - Debug and Logging

void objc_log_analysis_start(const char* binaryPath) {
    printf("[ObjCRuntimeC] Starting analysis of: %s\n", binaryPath);
}

void objc_log_class_found(const char* className, uint64_t address) {
    printf("[ObjCRuntimeC] Found class: %s at 0x%llx\n", className, address);
}

void objc_log_category_found(const char* categoryName, const char* className) {
    printf("[ObjCRuntimeC] Found category: %s on %s\n", categoryName, className);
}

void objc_log_protocol_found(const char* protocolName) {
    printf("[ObjCRuntimeC] Found protocol: %s\n", protocolName);
}

void objc_log_method_found(const char* methodName, const char* className) {
    printf("[ObjCRuntimeC] Found method: %s in %s\n", methodName, className);
}

void objc_log_property_found(const char* propertyName, const char* className) {
    printf("[ObjCRuntimeC] Found property: %s in %s\n", propertyName, className);
}

void objc_log_analysis_complete(int classCount, int categoryCount, int protocolCount) {
    printf("[ObjCRuntimeC] Analysis complete: %d classes, %d categories, %d protocols\n", 
           classCount, categoryCount, protocolCount);
}
