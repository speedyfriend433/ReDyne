#import "SceneDelegate.h"

@interface SceneDelegate ()
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
        
        Class filePickerClass = NSClassFromString(@"ReDyne.FilePickerViewController");
        if (filePickerClass) {
            UIViewController *rootViewController = [[filePickerClass alloc] init];
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

