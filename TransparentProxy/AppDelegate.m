#import "AppDelegate.h"
#import <NetworkExtension/NetworkExtension.h>

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [NETransparentProxyManager loadAllFromPreferencesWithCompletionHandler:
      ^(NSArray<NETransparentProxyManager *> * _Nullable managers, NSError * _Nullable error) {
        if (error) {
            NSLog(@"loadAllFromPreferencesWithCompletionHandler: %@", error.localizedDescription);
            return;
        }

        for (NETransparentProxyManager *manager in managers) {
            [manager removeFromPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
                if (error) {
                    NSLog(@"removeFromPreferencesWithCompletionHandler: %@", error.localizedDescription);
                }
            }];
        }

        NETunnelProviderProtocol *protocolConfiguration = [[NETunnelProviderProtocol alloc] init];
        protocolConfiguration.providerBundleIdentifier = @"com.adguard.example.TransparentProxy.TheExtension";
        protocolConfiguration.providerConfiguration = @{};
        protocolConfiguration.serverAddress = @"Transparent Proxy Bug Reproducer";

        NETransparentProxyManager *manager = [[NETransparentProxyManager alloc] init];
        manager.localizedDescription = @"Transparent Proxy Bug Reproducer";
        manager.protocolConfiguration = protocolConfiguration;
        manager.enabled = YES;

        [manager saveToPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"saveToPreferencesWithCompletionHandler: %@", error.localizedDescription);
                return;
            }
        
            [manager loadFromPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
                if (error) {
                    NSLog(@"loadFromPreferencesWithCompletionHandler: %@", error.localizedDescription);
                    return;
                }
                
                if (![manager.connection startVPNTunnelWithOptions:@{} andReturnError:&error]) {
                    NSLog(@"startVPNTunnelWithOptions: %@", error.localizedDescription);
                    return;
                }
                
                NSLog(@"Transparent proxy started");
            }];
        }];
    }];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [NETransparentProxyManager loadAllFromPreferencesWithCompletionHandler:
      ^(NSArray<NETransparentProxyManager *> * _Nullable managers, NSError * _Nullable error) {
        if (error) {
            NSLog(@"loadAllFromPreferencesWithCompletionHandler: %@", error.localizedDescription);
            return;
        }

        for (NETransparentProxyManager *manager in managers) {
            [manager removeFromPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
                if (error) {
                    NSLog(@"removeFromPreferencesWithCompletionHandler: %@", error.localizedDescription);
                }
            }];
        }
    }];
}

@end
