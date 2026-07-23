#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const WCLiquidGlassCrashLogsDidChangeNotification;

@interface WCLiquidGlassCrashLogger : NSObject

+ (instancetype)sharedLogger;
+ (NSURL *)diagnosticsDirectoryURL;
+ (NSURL *)crashLogsDirectoryURL;
- (void)start;
- (void)recordEvent:(NSString *)event;
- (NSArray<NSURL *> *)crashLogURLs;
- (void)deleteLogAtURL:(NSURL *)URL error:(NSError **)error;
- (void)deleteAllLogs;

@end

NS_ASSUME_NONNULL_END
