#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs a block and turns an Objective-C exception into a Swift error.
/// AVFoundation reports some failures (e.g. `installTap` on a stale format) only by raising NSException,
/// which Swift cannot catch and which would otherwise abort the app.
@interface OWObjC : NSObject
+ (BOOL)catching:(NS_NOESCAPE void (^)(void))block error:(NSError *_Nullable *_Nullable)error
    NS_SWIFT_NAME(catching(_:));
@end

/// Records the reason of a crash to `markerPath` (uncaught NSException or fatal signal) and relaunches
/// the app bundle at `bundlePath`, unless the process crashed within its first seconds (crash loop).
void OWInstallCrashGuard(NSString *markerPath, NSString *bundlePath);

NS_ASSUME_NONNULL_END
