#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "utils.h"

NS_ASSUME_NONNULL_BEGIN

@interface EnhancedFilePicker : NSObject


+ (void)enable;
+ (void)disable;
+ (BOOL)isActive;

@end

NS_ASSUME_NONNULL_END
