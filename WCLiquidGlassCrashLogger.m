#import "WCLiquidGlassCrashLogger.h"

#import "CrashReporter.h"

#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>

#ifndef WCLIQUIDGLASS_VERSION
#define WCLIQUIDGLASS_VERSION "Unknown"
#endif

NSNotificationName const WCLiquidGlassCrashLogsDidChangeNotification = @"WCLiquidGlass.CrashLogsChanged";

static const NSUInteger WCLiquidGlassMaximumCrashLogCount = 20;

static NSMutableArray<NSString *> *WCLiquidGlassRecentEvents(void) {
    static NSMutableArray<NSString *> *events;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        events = [NSMutableArray array];
    });
    return events;
}

static void WCLiquidGlassRecordEvent(NSString *event) {
    NSMutableArray<NSString *> *events = WCLiquidGlassRecentEvents();
    @synchronized (events) {
        [events addObject:[NSString stringWithFormat:@"%@  %@", NSDate.date, event]];
        if (events.count > 30) {
            [events removeObjectsInRange:NSMakeRange(0, events.count - 30)];
        }
    }
}

static NSString *WCLiquidGlassRecentEventsText(void) {
    NSMutableArray<NSString *> *events = WCLiquidGlassRecentEvents();
    @synchronized (events) {
        return events.count > 0 ? [events componentsJoinedByString:@"\n"] : @"None";
    }
}

static NSString *WCLiquidGlassTimestamp(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd-HH-mm-ss-SSS";
    });
    @synchronized (formatter) {
        return [formatter stringFromDate:NSDate.date];
    }
}

static BOOL WCLiquidGlassDebuggerAttached(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info = {0};
    size_t size = sizeof(info);
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) {
        return NO;
    }
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

static NSString *WCLiquidGlassDeviceModel(void) {
    struct utsname systemInfo;
    if (uname(&systemInfo) != 0) {
        return @"Unknown";
    }
    return [NSString stringWithUTF8String:systemInfo.machine] ?: @"Unknown";
}

static NSString *WCLiquidGlassLoadedTweaks(void) {
    NSMutableArray<NSString *> *images = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t index = 0; index < count; index += 1) {
        const char *imageName = _dyld_get_image_name(index);
        if (!imageName) {
            continue;
        }
        NSString *path = [NSString stringWithUTF8String:imageName];
        if ([path.pathExtension.lowercaseString isEqualToString:@"dylib"] &&
            ([path containsString:@"/Library/MobileSubstrate/"] ||
             [path containsString:@"/var/jb/"] ||
             [path containsString:@"/usr/lib/TweakInject/"] ||
             [path containsString:@"/WeChat.app/Frameworks/"])) {
            [images addObject:path.lastPathComponent];
        }
    }
    [images sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return images.count > 0 ? [images componentsJoinedByString:@"\n"] : @"None detected";
}

static NSString *WCLiquidGlassReportHeader(NSString *level) {
    NSBundle *bundle = NSBundle.mainBundle;
    NSDictionary *info = bundle.infoDictionary;
    return [NSString stringWithFormat:
            @"WCLiquidGlass Diagnostics\n"
             "Collection Level: %@\n"
             "Generated: %@\n"
             "WCLiquidGlass: %s\n"
             "WeChat: %@ (%@)\n"
             "iOS: %@\n"
             "Device: %@\n"
             "Process Uptime: %.3f seconds\n"
             "Application State: %ld\n\n"
             "Recent Lifecycle Events:\n%@\n\n"
             "Loaded Injected Dylibs:\n%@\n\n",
            level,
            NSDate.date,
            WCLIQUIDGLASS_VERSION,
            info[@"CFBundleShortVersionString"] ?: @"Unknown",
            info[@"CFBundleVersion"] ?: @"Unknown",
            UIDevice.currentDevice.systemVersion ?: @"Unknown",
            WCLiquidGlassDeviceModel(),
            NSProcessInfo.processInfo.systemUptime,
            (long)UIApplication.sharedApplication.applicationState,
            WCLiquidGlassRecentEventsText(),
            WCLiquidGlassLoadedTweaks()];
}

@interface WCLiquidGlassCrashLogger ()

@property(nonatomic) BOOL started;
@property(nonatomic, strong) PLCrashReporter *reporter;

@end

@implementation WCLiquidGlassCrashLogger

+ (instancetype)sharedLogger {
    static WCLiquidGlassCrashLogger *logger;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        logger = [[self alloc] init];
    });
    return logger;
}

+ (NSURL *)diagnosticsDirectoryURL {
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                             inDomains:NSUserDomainMask].firstObject;
    return [[[documents URLByAppendingPathComponent:@"WCLiquidGlass" isDirectory:YES]
             URLByAppendingPathComponent:@"Diagnostics" isDirectory:YES] URLByStandardizingPath];
}

+ (NSURL *)crashLogsDirectoryURL {
    return [[self diagnosticsDirectoryURL] URLByAppendingPathComponent:@"Crashes" isDirectory:YES];
}

- (void)start {
    @synchronized (self) {
        if (self.started) {
            return;
        }
        self.started = YES;
    }

    BOOL directoriesReady = [self wc_prepareDirectories];
    PLCrashReporter *reporter = [self wc_reporter];
    BOOL pendingReady = directoriesReady && [self wc_stagePendingCrashReportForEnable:reporter];
    if (WCLiquidGlassDebuggerAttached()) {
        WCLiquidGlassRecordEvent(@"PLCrashReporter skipped because debugger is attached");
    } else if (!pendingReady) {
        WCLiquidGlassRecordEvent(@"PLCrashReporter enable deferred because pending report preparation failed");
    } else {
        [self wc_enableCrashReporter];
    }
    [self wc_processStagedCrashReports];
    [self wc_observeLifecycle];
    [self wc_trimOldLogs];
    WCLiquidGlassRecordEvent(@"WCLiquidGlass logs started");
}

- (void)recordEvent:(NSString *)event {
    if (event.length == 0) {
        return;
    }
    WCLiquidGlassRecordEvent(event);
}

- (nullable NSURL *)writePageHierarchyDiagnosticWithContent:(NSString *)content {
    if (![self wc_prepareDirectories]) {
        return nil;
    }
    NSString *body = [NSString stringWithFormat:@"%@%@\n",
                      WCLiquidGlassReportHeader(@"Page Hierarchy Diagnostic"),
                      content ?: @""];
    NSURL *URL = [self.class.crashLogsDirectoryURL
                  URLByAppendingPathComponent:[NSString stringWithFormat:@"PageHierarchy-%@.txt",
                                              WCLiquidGlassTimestamp()]];
    NSError *writeError = nil;
    if (![body writeToURL:URL atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Page hierarchy diagnostic write failed: %@",
                                  writeError.localizedDescription ?: @"Unknown error"]);
        return nil;
    }
    WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Page hierarchy diagnostic saved: %@", URL.lastPathComponent]);
    [self wc_trimOldLogs];
    [NSNotificationCenter.defaultCenter postNotificationName:WCLiquidGlassCrashLogsDidChangeNotification object:nil];
    return URL;
}

- (NSArray<NSURL *> *)crashLogURLs {
    NSArray<NSURL *> *URLs = [NSFileManager.defaultManager contentsOfDirectoryAtURL:self.class.crashLogsDirectoryURL
                                                        includingPropertiesForKeys:@[NSURLContentModificationDateKey, NSURLFileSizeKey]
                                                                           options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                             error:nil] ?: @[];
    NSPredicate *textFiles = [NSPredicate predicateWithBlock:^BOOL(NSURL *URL, __unused NSDictionary *bindings) {
        return [URL.pathExtension.lowercaseString isEqualToString:@"txt"] ||
               [URL.pathExtension.lowercaseString isEqualToString:@"crash"];
    }];
    return [[URLs filteredArrayUsingPredicate:textFiles]
            sortedArrayUsingComparator:^NSComparisonResult(NSURL *first, NSURL *second) {
        NSDate *firstDate = nil;
        NSDate *secondDate = nil;
        [first getResourceValue:&firstDate forKey:NSURLContentModificationDateKey error:nil];
        [second getResourceValue:&secondDate forKey:NSURLContentModificationDateKey error:nil];
        return [secondDate ?: NSDate.distantPast compare:firstDate ?: NSDate.distantPast];
    }];
}

- (void)deleteLogAtURL:(NSURL *)URL error:(NSError **)error {
    NSString *logsPath = self.class.crashLogsDirectoryURL.URLByResolvingSymlinksInPath.path;
    NSString *targetPath = URL.URLByResolvingSymlinksInPath.path;
    if (![targetPath hasPrefix:[logsPath stringByAppendingString:@"/"]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"WCLiquidGlass.Diagnostics"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"无效的日志路径"}];
        }
        return;
    }
    if ([NSFileManager.defaultManager removeItemAtURL:URL error:error]) {
        [NSNotificationCenter.defaultCenter postNotificationName:WCLiquidGlassCrashLogsDidChangeNotification object:nil];
    }
}

- (void)deleteAllLogs {
    for (NSURL *URL in self.crashLogURLs) {
        [NSFileManager.defaultManager removeItemAtURL:URL error:nil];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:WCLiquidGlassCrashLogsDidChangeNotification object:nil];
}

- (BOOL)wc_prepareDirectories {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSDictionary *attributes = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
    NSError *directoryError = nil;
    BOOL success = [fileManager createDirectoryAtURL:self.class.crashLogsDirectoryURL
                           withIntermediateDirectories:YES
                                            attributes:attributes
                                                 error:&directoryError];
    if (!success && directoryError) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Crash logs directory creation failed: %@",
                                  directoryError.localizedDescription ?: @"Unknown error"]);
    }
    NSURL *internal = [self.class.diagnosticsDirectoryURL URLByAppendingPathComponent:@"Internal" isDirectory:YES];
    directoryError = nil;
    BOOL internalSuccess = [fileManager createDirectoryAtURL:internal
                                  withIntermediateDirectories:YES
                                                   attributes:attributes
                                                        error:&directoryError];
    if (!internalSuccess && directoryError) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Diagnostics internal directory creation failed: %@",
                                  directoryError.localizedDescription ?: @"Unknown error"]);
    }
    NSURL *reporterDirectory = [internal URLByAppendingPathComponent:@"PLCrashReporter" isDirectory:YES];
    directoryError = nil;
    BOOL reporterSuccess = [fileManager createDirectoryAtURL:reporterDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:attributes
                                                        error:&directoryError];
    if (!reporterSuccess && directoryError) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"PLCrashReporter directory creation failed: %@",
                                  directoryError.localizedDescription ?: @"Unknown error"]);
    }
    NSURL *pendingDirectory = [internal URLByAppendingPathComponent:@"Pending" isDirectory:YES];
    directoryError = nil;
    BOOL pendingSuccess = [fileManager createDirectoryAtURL:pendingDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:attributes
                                                        error:&directoryError];
    if (!pendingSuccess && directoryError) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Pending staging directory creation failed: %@",
                                  directoryError.localizedDescription ?: @"Unknown error"]);
    }
    return success && internalSuccess && reporterSuccess && pendingSuccess;
}

- (void)wc_observeLifecycle {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSArray<NSNotificationName> *names = @[UIApplicationDidBecomeActiveNotification,
                                            UIApplicationWillResignActiveNotification,
                                            UIApplicationDidEnterBackgroundNotification,
                                            UIApplicationWillEnterForegroundNotification,
                                            UIApplicationDidReceiveMemoryWarningNotification,
                                            UIApplicationWillTerminateNotification];
    for (NSNotificationName name in names) {
        [center addObserverForName:name
                           object:nil
                            queue:NSOperationQueue.mainQueue
                       usingBlock:^(NSNotification *notification) {
            WCLiquidGlassRecordEvent(notification.name);
        }];
    }
}

- (PLCrashReporter *)wc_reporter {
    if (self.reporter) {
        return self.reporter;
    }
    NSString *basePath = [[self.class.diagnosticsDirectoryURL URLByAppendingPathComponent:@"Internal/PLCrashReporter"] path];
    PLCrashReporterConfig *config = [[PLCrashReporterConfig alloc]
                                    initWithSignalHandlerType:PLCrashReporterSignalHandlerTypeMach
                                    symbolicationStrategy:PLCrashReporterSymbolicationStrategyNone
                                    shouldRegisterUncaughtExceptionHandler:YES
                                    basePath:basePath
                                    maxReportBytes:5 * 1024 * 1024];
    self.reporter = [[PLCrashReporter alloc] initWithConfiguration:config];
    return self.reporter;
}

- (NSURL *)wc_pendingStagingDirectoryURL {
    return [self.class.diagnosticsDirectoryURL URLByAppendingPathComponent:@"Internal/Pending" isDirectory:YES];
}

- (BOOL)wc_processCrashReportAtURL:(NSURL *)sourceURL {
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:sourceURL options:0 error:&readError];
    if (!data) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Pending crash report load failed (%@): %@",
                                  sourceURL.lastPathComponent,
                                  readError.localizedDescription ?: @"Unknown error"]);
        return NO;
    }
    NSError *parseError = nil;
    PLCrashReport *report = [[PLCrashReport alloc] initWithData:data error:&parseError];
    if (!report) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Pending crash report parse failed (%@): %@",
                                  sourceURL.lastPathComponent,
                                  parseError.localizedDescription ?: @"Unknown error"]);
        return NO;
    }
    NSString *formatted = [PLCrashReportTextFormatter stringValueForCrashReport:report
                                                                  withTextFormat:PLCrashReportTextFormatiOS];
    if (formatted.length == 0) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Pending crash report formatting failed (%@)",
                                  sourceURL.lastPathComponent]);
        return NO;
    }
    BOOL objectiveCException = report.exceptionInfo != nil;
    NSString *reportType = objectiveCException ? @"ObjectiveC" : @"Native";
    NSString *capturedHeader = [[NSString alloc] initWithData:report.customData encoding:NSUTF8StringEncoding];
    NSString *content = [(capturedHeader ?: WCLiquidGlassReportHeader(objectiveCException
                                                                        ? @"Objective-C Exception"
                                                                        : @"Native Mach Exception"))
                         stringByAppendingString:formatted];
    NSString *baseName = [NSString stringWithFormat:@"Crash-%@-%@", WCLiquidGlassTimestamp(), reportType];
    NSURL *URL = [self.class.crashLogsDirectoryURL
                  URLByAppendingPathComponent:[baseName stringByAppendingString:@".crash"]];
    if ([NSFileManager.defaultManager fileExistsAtPath:URL.path]) {
        URL = [self.class.crashLogsDirectoryURL
               URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.crash",
                                           baseName,
                                           NSUUID.UUID.UUIDString]];
    }
    NSError *writeError = nil;
    if (![content writeToURL:URL atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Pending crash report write failed (%@): %@",
                                  sourceURL.lastPathComponent,
                                  writeError.localizedDescription ?: @"Unknown error"]);
        return NO;
    }
    NSError *removeError = nil;
    if (![NSFileManager.defaultManager removeItemAtURL:sourceURL error:&removeError]) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Pending crash report staging cleanup failed (%@): %@",
                                  sourceURL.lastPathComponent,
                                  removeError.localizedDescription ?: @"Unknown error"]);
        return NO;
    }
    [NSNotificationCenter.defaultCenter postNotificationName:WCLiquidGlassCrashLogsDidChangeNotification object:nil];
    return YES;
}

- (BOOL)wc_stagePendingCrashReportForEnable:(PLCrashReporter *)reporter {
    NSString *path = reporter.crashReportPath;
    BOOL hasPending = [reporter hasPendingCrashReport];
    if (path.length == 0 || ![NSFileManager.defaultManager fileExistsAtPath:path]) {
        if (hasPending) {
            WCLiquidGlassRecordEvent(@"PLCrashReporter reported pending crash data but its live path is unavailable");
            return NO;
        }
        return YES;
    }
    NSURL *sourceURL = [NSURL fileURLWithPath:path];
    NSString *stagingName = [NSString stringWithFormat:@"Crash-%@-%@.plcrash",
                             WCLiquidGlassTimestamp(),
                             NSUUID.UUID.UUIDString];
    NSURL *stagingURL = [[self wc_pendingStagingDirectoryURL] URLByAppendingPathComponent:stagingName];
    NSError *moveError = nil;
    if ([NSFileManager.defaultManager moveItemAtURL:sourceURL toURL:stagingURL error:&moveError]) {
        return YES;
    }
    WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Pending crash report staging move failed: %@",
                              moveError.localizedDescription ?: @"Unknown error"]);
    if (![self wc_processCrashReportAtURL:sourceURL]) {
        WCLiquidGlassRecordEvent(@"Live pending crash report fallback failed; PLCrashReporter remains disabled");
        return NO;
    }
    return YES;
}

- (void)wc_processStagedCrashReports {
    NSError *directoryError = nil;
    NSArray<NSURL *> *URLs = [NSFileManager.defaultManager contentsOfDirectoryAtURL:[self wc_pendingStagingDirectoryURL]
                                                               includingPropertiesForKeys:nil
                                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                    error:&directoryError];
    if (!URLs) {
        if (directoryError) {
            WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Pending staging scan failed: %@",
                                      directoryError.localizedDescription ?: @"Unknown error"]);
        }
        return;
    }
    for (NSURL *URL in URLs) {
        if ([URL.pathExtension.lowercaseString isEqualToString:@"plcrash"]) {
            if ([self wc_processCrashReportAtURL:URL]) {
                continue;
            }
            NSString *failedPath = [[URL URLByDeletingPathExtension].path stringByAppendingString:@".failed"];
            if ([NSFileManager.defaultManager fileExistsAtPath:failedPath]) {
                failedPath = [[URL URLByDeletingPathExtension].path
                               stringByAppendingFormat:@"-%@.failed", NSUUID.UUID.UUIDString];
            }
            NSError *isolationError = nil;
            NSURL *failedURL = [NSURL fileURLWithPath:failedPath];
            if (![NSFileManager.defaultManager moveItemAtURL:URL toURL:failedURL error:&isolationError]) {
                WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Failed pending crash report isolation failed (%@): %@",
                                          URL.lastPathComponent,
                                          isolationError.localizedDescription ?: @"Unknown error"]);
            }
        }
    }
}

- (void)wc_enableCrashReporter {
    PLCrashReporter *reporter = [self wc_reporter];
    if (!reporter) {
        WCLiquidGlassRecordEvent(@"PLCrashReporter initialization failed");
        return;
    }
    NSString *header = WCLiquidGlassReportHeader(@"Automatic Crash Collection Metadata");
    reporter.customData = [header dataUsingEncoding:NSUTF8StringEncoding];
    NSError *enableError = nil;
    if (![reporter enableCrashReporterAndReturnError:&enableError]) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"PLCrashReporter enable failed: %@",
                                  enableError.localizedDescription ?: @"Unknown error"]);
    }
}

- (void)wc_trimOldLogs {
    NSArray<NSURL *> *URLs = self.crashLogURLs;
    if (URLs.count <= WCLiquidGlassMaximumCrashLogCount) {
        return;
    }
    for (NSUInteger index = WCLiquidGlassMaximumCrashLogCount; index < URLs.count; index += 1) {
        [NSFileManager.defaultManager removeItemAtURL:URLs[index] error:nil];
    }
}

@end
