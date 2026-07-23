#import "WCLiquidGlassCrashLogger.h"

#import "WCLiquidGlassPreferences.h"

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
static NSUncaughtExceptionHandler *WCLiquidGlassPreviousExceptionHandler = NULL;
static __weak WCLiquidGlassCrashLogger *WCLiquidGlassActiveCrashLogger = nil;

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

static void WCLiquidGlassHandleUncaughtException(NSException *exception) {
    @autoreleasepool {
        WCLiquidGlassCrashLogger *logger = WCLiquidGlassActiveCrashLogger;
        if (logger) {
            NSString *body = [NSString stringWithFormat:
                              @"%@Exception Name: %@\nReason: %@\nUser Info: %@\n\nBacktrace:\n%@\n",
                              WCLiquidGlassReportHeader(@"Basic / Objective-C Exception"),
                              exception.name ?: @"Unknown",
                              exception.reason ?: @"Unknown",
                              exception.userInfo ?: @{},
                              [exception.callStackSymbols componentsJoinedByString:@"\n"] ?: @"Unavailable"];
            NSURL *URL = [[WCLiquidGlassCrashLogger crashLogsDirectoryURL]
                          URLByAppendingPathComponent:[NSString stringWithFormat:@"Crash-%@-ObjectiveC.txt", WCLiquidGlassTimestamp()]];
            [body writeToURL:URL atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }
    if (WCLiquidGlassPreviousExceptionHandler &&
        WCLiquidGlassPreviousExceptionHandler != WCLiquidGlassHandleUncaughtException) {
        WCLiquidGlassPreviousExceptionHandler(exception);
    }
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

    [WCLiquidGlassPreferences registerDefaults];
    [self wc_prepareDirectories];
    WCLiquidGlassRecordEvent(@"WCLiquidGlass diagnostics started");
    [self wc_observeLifecycle];
    [self wc_processPendingFullReport];
    [self wc_trimOldLogs];

    WCLiquidGlassActiveCrashLogger = self;
    WCLiquidGlassPreviousExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(WCLiquidGlassHandleUncaughtException);

    if (WCLiquidGlassPreferences.fullCrashReportsEnabled && !WCLiquidGlassDebuggerAttached()) {
        [self wc_enableFullCrashReporter];
    }
}

- (void)recordEvent:(NSString *)event {
    if (event.length == 0) {
        return;
    }
    WCLiquidGlassRecordEvent(event);
}

- (NSArray<NSURL *> *)crashLogURLs {
    NSArray<NSURL *> *URLs = [NSFileManager.defaultManager contentsOfDirectoryAtURL:self.class.crashLogsDirectoryURL
                                                        includingPropertiesForKeys:@[NSURLContentModificationDateKey, NSURLFileSizeKey]
                                                                           options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                             error:nil] ?: @[];
    NSPredicate *textFiles = [NSPredicate predicateWithBlock:^BOOL(NSURL *URL, NSDictionary *bindings) {
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

- (void)wc_prepareDirectories {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    [fileManager createDirectoryAtURL:self.class.crashLogsDirectoryURL
          withIntermediateDirectories:YES
                           attributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
                                error:nil];
    NSURL *internal = [self.class.diagnosticsDirectoryURL URLByAppendingPathComponent:@"Internal" isDirectory:YES];
    [fileManager createDirectoryAtURL:internal
          withIntermediateDirectories:YES
                           attributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
                                error:nil];
    [fileManager createDirectoryAtURL:[internal URLByAppendingPathComponent:@"PLCrashReporter" isDirectory:YES]
          withIntermediateDirectories:YES
                           attributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
                                error:nil];
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
            if (self.reporter && WCLiquidGlassPreferences.fullCrashReportsEnabled) {
                self.reporter.customData = [WCLiquidGlassReportHeader(@"Full / Mach Exception Metadata") dataUsingEncoding:NSUTF8StringEncoding];
            }
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
                                    shouldRegisterUncaughtExceptionHandler:NO
                                    basePath:basePath
                                    maxReportBytes:5 * 1024 * 1024];
    self.reporter = [[PLCrashReporter alloc] initWithConfiguration:config];
    return self.reporter;
}

- (void)wc_processPendingFullReport {
    PLCrashReporter *reporter = [self wc_reporter];
    if (![reporter hasPendingCrashReport]) {
        return;
    }

    NSError *loadError = nil;
    NSData *data = [reporter loadPendingCrashReportDataAndReturnError:&loadError];
    if (!data) {
        return;
    }
    NSError *parseError = nil;
    PLCrashReport *report = [[PLCrashReport alloc] initWithData:data error:&parseError];
    if (!report) {
        return;
    }
    NSString *formatted = [PLCrashReportTextFormatter stringValueForCrashReport:report
                                                                  withTextFormat:PLCrashReportTextFormatiOS];
    NSString *capturedHeader = [[NSString alloc] initWithData:report.customData encoding:NSUTF8StringEncoding];
    NSString *content = [(capturedHeader ?: WCLiquidGlassReportHeader(@"Full / Mach Exception"))
                         stringByAppendingString:formatted ?: @""];
    NSURL *URL = [self.class.crashLogsDirectoryURL
                  URLByAppendingPathComponent:[NSString stringWithFormat:@"Crash-%@-Full.crash", WCLiquidGlassTimestamp()]];
    NSError *writeError = nil;
    if ([content writeToURL:URL atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        [reporter purgePendingCrashReportAndReturnError:nil];
        [NSNotificationCenter.defaultCenter postNotificationName:WCLiquidGlassCrashLogsDidChangeNotification object:nil];
    }
}

- (void)wc_enableFullCrashReporter {
    PLCrashReporter *reporter = [self wc_reporter];
    reporter.customData = [WCLiquidGlassReportHeader(@"Full / Mach Exception Metadata") dataUsingEncoding:NSUTF8StringEncoding];
    [reporter enableCrashReporterAndReturnError:nil];
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
