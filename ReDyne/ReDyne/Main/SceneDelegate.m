#import "SceneDelegate.h"

NSNotificationName const ReDyneOpenFileFromShareNotification = @"ReDyneOpenFileFromShareNotification";

@interface SceneDelegate ()
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
        
        Class filePickerClass = NSClassFromString(@"ReDyne.FilePickerViewController");
        if (filePickerClass) {
            id rootViewController = [[filePickerClass alloc] init];
            [rootViewController performSelector:@selector(setSceneDelegate:) withObject:self];
            UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:rootViewController];
            UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
            [appearance configureWithDefaultBackground];
            navigationController.navigationBar.standardAppearance = appearance;
            navigationController.navigationBar.scrollEdgeAppearance = appearance;
            navigationController.navigationBar.prefersLargeTitles = YES;
            
            self.window.rootViewController = navigationController;
            [self.window makeKeyAndVisible];
        } else {
            NSLog(@"ERROR: Could not find FilePickerViewController class!");
            UIViewController *errorVC = [[UIViewController alloc] init];
            errorVC.view.backgroundColor = [UIColor systemRedColor];
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, 300, 200)];
            label.text = @"Error: FilePickerViewController not found!\n\nCheck if Swift files are compiled.";
            label.numberOfLines = 0;
            label.textColor = [UIColor whiteColor];
            label.textAlignment = NSTextAlignmentCenter;
            [errorVC.view addSubview:label];
            
            self.window.rootViewController = errorVC;
            [self.window makeKeyAndVisible];
        }
        
        // Handle files passed during cold launch (from share sheet or "Open In")
        if (connectionOptions.URLContexts.count > 0) {
            [self handleURLContexts:connectionOptions.URLContexts];
        }
    }
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    // Handle files opened while app is already running
    [self handleURLContexts:URLContexts];
}

- (void)handleURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    UIOpenURLContext *context = URLContexts.allObjects.firstObject;
    if (!context) return;
    
    NSURL *url = context.URL;
    NSLog(@"ReDyne received URL with scheme: %@", url.scheme);
    
    if ([url.scheme isEqualToString:@"redyne"]) {
        // Handle redyne://open?file=<filename> from share extension
        NSURLComponents *components = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:NO];
        NSString *filename = nil;
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqualToString:@"file"]) {
                filename = item.value;
                break;
            }
        }
        
        // Reject anything that is not a plain file name (blocks "../" traversal from untrusted URLs)
        if (filename && (filename.length == 0 ||
                         ![filename isEqualToString:filename.lastPathComponent] ||
                         [filename isEqualToString:@"."] || [filename isEqualToString:@".."] ||
                         [filename containsString:@"\0"])) {
            NSLog(@"Rejected redyne:// URL with invalid file name");
            filename = nil;
        }

        if (filename) {
            // Look for the file in the App Group shared container
            NSURL *containerURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:@"group.com.jian.ReDyne"];
            NSURL *sharedFileURL = nil;
            
            if (containerURL) {
                sharedFileURL = [[containerURL URLByAppendingPathComponent:@"SharedFiles" isDirectory:YES] URLByAppendingPathComponent:filename];
            }
            
            if (!sharedFileURL || ![[NSFileManager defaultManager] fileExistsAtPath:sharedFileURL.path]) {
                // Fallback: check temp directory
                sharedFileURL = [[[NSFileManager defaultManager].temporaryDirectory URLByAppendingPathComponent:@"ReDyneShared" isDirectory:YES] URLByAppendingPathComponent:filename];
            }
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:sharedFileURL.path]) {
                // Copy to app's working temp directory
                NSURL *workingDir = [[NSFileManager defaultManager].temporaryDirectory URLByAppendingPathComponent:@"ReDyneTempFiles" isDirectory:YES];
                [[NSFileManager defaultManager] createDirectoryAtURL:workingDir withIntermediateDirectories:YES attributes:nil error:nil];
                
                NSURL *destURL = [workingDir URLByAppendingPathComponent:filename];
                [[NSFileManager defaultManager] removeItemAtURL:destURL error:nil];
                
                NSError *copyError = nil;
                [[NSFileManager defaultManager] copyItemAtURL:sharedFileURL toURL:destURL error:&copyError];
                
                if (!copyError) {
                    // Post notification with small delay to ensure UI is ready
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:ReDyneOpenFileFromShareNotification
                                                                            object:nil
                                                                          userInfo:@{@"fileURL": destURL}];
                    });
                } else {
                    NSLog(@"Failed to copy shared file: %@", copyError);
                }
            } else {
                NSLog(@"Shared file not found: %@", sharedFileURL.path);
            }
        }
    } else if (url.isFileURL) {
        // Handle direct file opening ("Open In" / document types)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ReDyneOpenFileFromShareNotification
                                                                object:nil
                                                              userInfo:@{@"fileURL": url}];
        });
    }
}

- (void)sceneDidDisconnect:(UIScene *)scene {
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
}

- (void)sceneWillResignActive:(UIScene *)scene {
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
}

@end

