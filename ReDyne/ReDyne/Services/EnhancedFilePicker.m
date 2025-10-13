#import "EnhancedFilePicker.h"
#import "LCSharedUtils.h"
#import "UIKitPrivate.h"
#import "util.h"
#import "FoundationPrivate.h"

static BOOL enhancedFilePickerActive = NO;
static void NSFMGuestHooksInit(void);

@implementation EnhancedFilePicker

+ (void)enable {
    if (enhancedFilePickerActive) {
        return;
    }

    enhancedFilePickerActive = YES;
    NSFMGuestHooksInit();
}

+ (void)disable {
    if (!enhancedFilePickerActive) {
        return;
    }

    enhancedFilePickerActive = NO;
}

+ (BOOL)isActive {
    return enhancedFilePickerActive;
}

@end

BOOL fixFilePicker;
__attribute__((constructor))
static void NSFMGuestHooksInit() {
    if (!enhancedFilePickerActive) {
        return;
    }

    fixFilePicker = YES;

    // Hook document picker initialization
    swizzle(UIDocumentPickerViewController.class,
            @selector(initForOpeningContentTypes:asCopy:),
            @selector(hook_initForOpeningContentTypes:asCopy:));

    swizzle(UIDocumentPickerViewController.class,
            @selector(initWithDocumentTypes:inMode:),
            @selector(hook_initWithDocumentTypes:inMode:));

    swizzle(UIDocumentBrowserViewController.class,
            @selector(initForOpeningContentTypes:),
            @selector(hook_initForOpeningContentTypes));

    swizzleClassMethod(UTType.class,
                      @selector(typeWithIdentifier:),
                      @selector(hook_typeWithIdentifier:));

    if (fixFilePicker) {
        swizzle(NSURL.class,
                @selector(startAccessingSecurityScopedResource),
                @selector(hook_startAccessingSecurityScopedResource));

        swizzle(UIDocumentPickerViewController.class,
                @selector(setAllowsMultipleSelection:),
                @selector(hook_setAllowsMultipleSelection:));
    }
    // swizzle(DOCConfiguration.class, @selector(setHostIdentifier:), @selector(hook_setHostIdentifier:));
}

