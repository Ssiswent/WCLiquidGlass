#import "WCLiquidGlassCrashLogger.h"

#import "CrashReporter.h"

#import <UIKit/UIKit.h>
#import <errno.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <fcntl.h>
#import <signal.h>
#import <string.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <time.h>
#import <unistd.h>

#ifndef WCLIQUIDGLASS_VERSION
#define WCLIQUIDGLASS_VERSION "Unknown"
#endif

NSNotificationName const WCLiquidGlassCrashLogsDidChangeNotification = @"WCLiquidGlass.CrashLogsChanged";

static const NSUInteger WCLiquidGlassMaximumCrashLogCount = 20;

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint8_t sessionID[16];
    uint32_t processID;
    uint32_t signalNumber;
    int32_t signalCode;
    uint32_t reserved;
    uint64_t timestampSeconds;
    uint64_t timestampNanoseconds;
    uint64_t faultAddress;
    uint64_t programCounter;
    uint64_t stackPointer;
    uint64_t framePointer;
    uint64_t linkRegister;
    uint8_t reservedTail[32];
} WCLiquidGlassCrashMarker;

typedef char WCLiquidGlassCrashMarkerSizeCheck[
    sizeof(WCLiquidGlassCrashMarker) == 128 ? 1 : -1];

static const uint32_t WCLiquidGlassCrashMarkerMagic = 0x57434c47;
static const uint32_t WCLiquidGlassCrashMarkerVersion = 1;
static const int WCLiquidGlassCrashSignals[] = {
    SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP
};

static int WCLiquidGlassCrashMarkerFD = -1;
static volatile sig_atomic_t WCLiquidGlassCrashMarkerActive = 0;
static volatile sig_atomic_t WCLiquidGlassCrashMarkerHandling = 0;
static uint8_t WCLiquidGlassCrashSessionID[16];
static struct sigaction WCLiquidGlassPreviousSignalActions[sizeof(WCLiquidGlassCrashSignals) /
                                                           sizeof(WCLiquidGlassCrashSignals[0])];
static NSString *WCLiquidGlassRecentEventsPath;
static NSUncaughtExceptionHandler *WCLiquidGlassPreviousExceptionHandler;
static volatile sig_atomic_t WCLiquidGlassExceptionHandling = 0;
static __weak WCLiquidGlassCrashLogger *WCLiquidGlassExceptionLogger;
static BOOL WCLiquidGlassExceptionHandlerInstalled = NO;

static void WCLiquidGlassHandleException(NSException *exception);

static int WCLiquidGlassSignalIndex(int signalNumber) {
    for (NSUInteger index = 0;
         index < sizeof(WCLiquidGlassCrashSignals) / sizeof(WCLiquidGlassCrashSignals[0]);
         index += 1) {
        if (WCLiquidGlassCrashSignals[index] == signalNumber) {
            return (int)index;
        }
    }
    return -1;
}

static void WCLiquidGlassExtractRegisters(void *context,
                                          uint64_t *programCounter,
                                          uint64_t *stackPointer,
                                          uint64_t *framePointer,
                                          uint64_t *linkRegister) {
    if (!context) {
        return;
    }
#if defined(__arm64__)
    ucontext_t *userContext = (ucontext_t *)context;
    if (!userContext->uc_mcontext) {
        return;
    }
    *programCounter = userContext->uc_mcontext->__ss.__pc;
    *stackPointer = userContext->uc_mcontext->__ss.__sp;
    *framePointer = userContext->uc_mcontext->__ss.__fp;
    *linkRegister = userContext->uc_mcontext->__ss.__lr;
#elif defined(__x86_64__)
    ucontext_t *userContext = (ucontext_t *)context;
    if (!userContext->uc_mcontext) {
        return;
    }
    *programCounter = userContext->uc_mcontext->__ss.__rip;
    *stackPointer = userContext->uc_mcontext->__ss.__rsp;
    *framePointer = userContext->uc_mcontext->__ss.__rbp;
#else
    (void)programCounter;
    (void)stackPointer;
    (void)framePointer;
    (void)linkRegister;
#endif
}

static void WCLiquidGlassWriteCrashMarker(const WCLiquidGlassCrashMarker *marker) {
    int fileDescriptor = WCLiquidGlassCrashMarkerFD;
    if (fileDescriptor < 0) {
        return;
    }
    const uint8_t *bytes = (const uint8_t *)marker;
    size_t offset = 0;
    while (offset < sizeof(*marker)) {
        ssize_t written = pwrite(fileDescriptor,
                                 bytes + offset,
                                 sizeof(*marker) - offset,
                                 (off_t)offset);
        if (written > 0) {
            offset += (size_t)written;
        } else if (written < 0 && errno == EINTR) {
            continue;
        } else {
            break;
        }
    }
}

static void WCLiquidGlassChainSignal(int signalNumber, siginfo_t *info, void *context) {
    int index = WCLiquidGlassSignalIndex(signalNumber);
    if (index < 0) {
        return;
    }
    struct sigaction previous = WCLiquidGlassPreviousSignalActions[index];
    if (previous.sa_handler == SIG_IGN) {
        return;
    }
    if (previous.sa_handler == SIG_DFL) {
        sigaction(signalNumber, &previous, NULL);
        kill(getpid(), signalNumber);
        return;
    }
    if ((previous.sa_flags & SA_SIGINFO) != 0) {
        if (previous.sa_sigaction) {
            previous.sa_sigaction(signalNumber, info, context);
        }
    } else if (previous.sa_handler) {
        previous.sa_handler(signalNumber);
    }
}

static void WCLiquidGlassCrashSignalHandler(int signalNumber, siginfo_t *info, void *context) {
    if (!WCLiquidGlassCrashMarkerActive ||
        WCLiquidGlassCrashMarkerFD < 0 ||
        !__sync_bool_compare_and_swap(&WCLiquidGlassCrashMarkerHandling, 0, 1)) {
        WCLiquidGlassChainSignal(signalNumber, info, context);
        return;
    }

    WCLiquidGlassCrashMarker marker = {0};
    marker.magic = WCLiquidGlassCrashMarkerMagic;
    marker.version = WCLiquidGlassCrashMarkerVersion;
    for (NSUInteger index = 0; index < sizeof(marker.sessionID); index += 1) {
        marker.sessionID[index] = WCLiquidGlassCrashSessionID[index];
    }
    marker.processID = (uint32_t)getpid();
    marker.signalNumber = (uint32_t)signalNumber;
    marker.signalCode = info ? info->si_code : 0;
    marker.faultAddress = info ? (uint64_t)(uintptr_t)info->si_addr : 0;
    struct timespec timestamp = {0};
    if (clock_gettime(CLOCK_REALTIME, &timestamp) == 0) {
        marker.timestampSeconds = (uint64_t)timestamp.tv_sec;
        marker.timestampNanoseconds = (uint64_t)timestamp.tv_nsec;
    }
    uint64_t programCounter = 0;
    uint64_t stackPointer = 0;
    uint64_t framePointer = 0;
    uint64_t linkRegister = 0;
    WCLiquidGlassExtractRegisters(context,
                                  &programCounter,
                                  &stackPointer,
                                  &framePointer,
                                  &linkRegister);
    marker.programCounter = programCounter;
    marker.stackPointer = stackPointer;
    marker.framePointer = framePointer;
    marker.linkRegister = linkRegister;
    WCLiquidGlassWriteCrashMarker(&marker);
    WCLiquidGlassChainSignal(signalNumber, info, context);
    WCLiquidGlassCrashMarkerHandling = 0;
}

static BOOL WCLiquidGlassStartCrashMarker(NSString *path, NSData *sessionID) {
    if (path.length == 0 || sessionID.length != sizeof(WCLiquidGlassCrashSessionID)) {
        return NO;
    }
    const char *fileSystemPath = path.fileSystemRepresentation;
    if (!fileSystemPath) {
        return NO;
    }
    int fileDescriptor = open(fileSystemPath, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fileDescriptor < 0) {
        return NO;
    }

    NSUInteger signalCount = sizeof(WCLiquidGlassCrashSignals) / sizeof(WCLiquidGlassCrashSignals[0]);
    NSUInteger installedCount = 0;
    struct sigaction action = {0};
    sigemptyset(&action.sa_mask);
    action.sa_sigaction = WCLiquidGlassCrashSignalHandler;
    action.sa_flags = SA_SIGINFO;
    for (NSUInteger index = 0; index < signalCount; index += 1) {
        if (sigaction(WCLiquidGlassCrashSignals[index], &action,
                      &WCLiquidGlassPreviousSignalActions[index]) != 0) {
            for (NSUInteger restoreIndex = 0; restoreIndex < installedCount; restoreIndex += 1) {
                sigaction(WCLiquidGlassCrashSignals[restoreIndex],
                          &WCLiquidGlassPreviousSignalActions[restoreIndex],
                          NULL);
            }
            close(fileDescriptor);
            return NO;
        }
        installedCount += 1;
    }
    memcpy(WCLiquidGlassCrashSessionID, sessionID.bytes, sizeof(WCLiquidGlassCrashSessionID));
    WCLiquidGlassCrashMarkerFD = fileDescriptor;
    WCLiquidGlassCrashMarkerHandling = 0;
    WCLiquidGlassCrashMarkerActive = 1;
    return YES;
}

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
    NSString *eventsText = nil;
    @synchronized (events) {
        [events addObject:[NSString stringWithFormat:@"%@  %@", NSDate.date, event]];
        if (events.count > 30) {
            [events removeObjectsInRange:NSMakeRange(0, events.count - 30)];
        }
        eventsText = [events componentsJoinedByString:@"\n"];
    }
    NSString *eventsPath = WCLiquidGlassRecentEventsPath;
    if (eventsPath.length > 0 && eventsText.length > 0) {
        [eventsText writeToFile:eventsPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

static void WCLiquidGlassResetRecentEvents(void) {
    NSMutableArray<NSString *> *events = WCLiquidGlassRecentEvents();
    @synchronized (events) {
        [events removeAllObjects];
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

static NSString *WCLiquidGlassTimestampForDate(NSDate *date) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd-HH-mm-ss-SSS";
    });
    @synchronized (formatter) {
        return [formatter stringFromDate:date ?: NSDate.date];
    }
}

static NSString *WCLiquidGlassSignalName(int signalNumber) {
    switch (signalNumber) {
        case SIGABRT: return @"SIGABRT";
        case SIGBUS: return @"SIGBUS";
        case SIGFPE: return @"SIGFPE";
        case SIGILL: return @"SIGILL";
        case SIGSEGV: return @"SIGSEGV";
        case SIGTRAP: return @"SIGTRAP";
        default: return [NSString stringWithFormat:@"SIG%d", signalNumber];
    }
}

static NSString *WCLiquidGlassUUIDStringFromBytes(const uint8_t *bytes) {
    if (!bytes) {
        return @"Unknown";
    }
    NSUUID *UUID = [[NSUUID alloc] initWithUUIDBytes:bytes];
    return UUID.UUIDString ?: @"Unknown";
}

static NSString *WCLiquidGlassImagePathForAddress(NSArray<NSDictionary *> *images, uint64_t address) {
    if (address == 0) {
        return nil;
    }
    for (NSDictionary *image in images) {
        uint64_t base = [image[@"base"] unsignedLongLongValue];
        uint64_t size = [image[@"size"] unsignedLongLongValue];
        if (size > 0 && address >= base && address < base + size) {
            return image[@"path"];
        }
    }
    return nil;
}

static BOOL WCLiquidGlassLooksLikeInjectedImage(NSString *path) {
    return [path.pathExtension.lowercaseString isEqualToString:@"dylib"] &&
           ([path containsString:@"/Library/MobileSubstrate/"] ||
            [path containsString:@"/var/jb/"] ||
            [path containsString:@"/usr/lib/TweakInject/"] ||
            [path containsString:@"/WeChat.app/Frameworks/"]);
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

static NSString *WCLiquidGlassReportHeaderWithEvents(NSString *level, NSString *events) {
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
            events ?: WCLiquidGlassRecentEventsText(),
            WCLiquidGlassLoadedTweaks()];
}

static NSString *WCLiquidGlassReportHeader(NSString *level) {
    return WCLiquidGlassReportHeaderWithEvents(level, nil);
}

@interface WCLiquidGlassCrashLogger ()

@property(nonatomic) BOOL started;
@property(nonatomic, strong) PLCrashReporter *reporter;
@property(nonatomic, strong) NSData *sessionID;

- (void)wc_writeUncaughtException:(NSException *)exception;

@end

static void WCLiquidGlassHandleException(NSException *exception) {
    if (!__sync_bool_compare_and_swap(&WCLiquidGlassExceptionHandling, 0, 1)) {
        if (WCLiquidGlassPreviousExceptionHandler) {
            WCLiquidGlassPreviousExceptionHandler(exception);
        }
        return;
    }
    @autoreleasepool {
        [WCLiquidGlassExceptionLogger wc_writeUncaughtException:exception];
    }
    if (WCLiquidGlassPreviousExceptionHandler &&
        WCLiquidGlassPreviousExceptionHandler != WCLiquidGlassHandleException) {
        WCLiquidGlassPreviousExceptionHandler(exception);
    }
    WCLiquidGlassExceptionHandling = 0;
}

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
    [self wc_recoverSignalCrashMarker];
    WCLiquidGlassResetRecentEvents();
    if (directoriesReady) {
        self.sessionID = [self wc_newSessionID];
        if (WCLiquidGlassDebuggerAttached()) {
            WCLiquidGlassRecordEvent(@"Signal crash marker skipped because debugger is attached");
        } else if (!WCLiquidGlassStartCrashMarker([self wc_crashMarkerURL].path, self.sessionID)) {
            WCLiquidGlassRecordEvent(@"Signal crash marker installation failed");
        } else {
            WCLiquidGlassRecordEvent(@"Signal crash marker installed");
        }
        [self wc_writeSessionMetadata];
        [self wc_installExceptionHandler];
        [self wc_writeImageSnapshot];
        PLCrashReporter *reporter = [self wc_reporter];
        if (![self wc_stagePendingCrashReportForEnable:reporter]) {
            WCLiquidGlassRecordEvent(@"Legacy PLCrashReporter pending report staging failed");
        }
    } else {
        WCLiquidGlassRecordEvent(@"Crash logging directories are unavailable");
    }
    [self wc_processStagedCrashReports];
    [self wc_observeLifecycle];
    [self wc_trimOldLogs];
    WCLiquidGlassRecordEvent(@"WCLiquidGlass logs started with signal marker recovery");
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
    NSURL *runtime = [self.class.diagnosticsDirectoryURL URLByAppendingPathComponent:@"Internal/Runtime"
                                                                        isDirectory:YES];
    WCLiquidGlassRecentEventsPath = [[runtime URLByAppendingPathComponent:@"recent-events.log"
                                                             isDirectory:NO] path];
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
    directoryError = nil;
    BOOL runtimeSuccess = [fileManager createDirectoryAtURL:runtime
                                  withIntermediateDirectories:YES
                                                   attributes:attributes
                                                        error:&directoryError];
    if (!runtimeSuccess && directoryError) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Crash marker runtime directory creation failed: %@",
                                  directoryError.localizedDescription ?: @"Unknown error"]);
    }
    return success && internalSuccess && reporterSuccess && pendingSuccess && runtimeSuccess;
}

- (NSURL *)wc_runtimeDirectoryURL {
    return [self.class.diagnosticsDirectoryURL URLByAppendingPathComponent:@"Internal/Runtime"
                                                                 isDirectory:YES];
}

- (NSURL *)wc_crashMarkerURL {
    return [[self wc_runtimeDirectoryURL] URLByAppendingPathComponent:@"crash.marker"
                                                             isDirectory:NO];
}

- (NSURL *)wc_sessionURL {
    return [[self wc_runtimeDirectoryURL] URLByAppendingPathComponent:@"session.plist"
                                                             isDirectory:NO];
}

- (NSURL *)wc_imageSnapshotURL {
    return [[self wc_runtimeDirectoryURL] URLByAppendingPathComponent:@"image_snapshot.plist"
                                                             isDirectory:NO];
}

- (NSData *)wc_newSessionID {
    uuid_t bytes = {0};
    [NSUUID.UUID getUUIDBytes:bytes];
    return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

- (void)wc_writeSessionMetadata {
    if (self.sessionID.length != sizeof(WCLiquidGlassCrashSessionID)) {
        return;
    }
    NSDictionary *metadata = @{
        @"sessionID": WCLiquidGlassUUIDStringFromBytes(self.sessionID.bytes),
        @"processID": @(getpid()),
        @"startDate": NSDate.date,
        @"imageSnapshot": [self wc_imageSnapshotURL].path ?: @""
    };
    if (![metadata writeToURL:[self wc_sessionURL] atomically:YES]) {
        WCLiquidGlassRecordEvent(@"Session metadata write failed");
    }
}

- (void)wc_writeImageSnapshot {
    NSMutableArray<NSDictionary *> *images = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t index = 0; index < count; index += 1) {
        const struct mach_header *header = _dyld_get_image_header(index);
        const char *name = _dyld_get_image_name(index);
        if (!header || !name) {
            continue;
        }

        uint64_t minimumVMAddress = UINT64_MAX;
        uint64_t maximumVMAddress = 0;
        uuid_t imageUUID = {0};
        BOOL hasUUID = NO;
        if (header->magic == MH_MAGIC_64) {
            const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;
            const uint8_t *commandBytes = (const uint8_t *)(header64 + 1);
            for (uint32_t commandIndex = 0; commandIndex < header64->ncmds; commandIndex += 1) {
                const struct load_command *command = (const struct load_command *)commandBytes;
                if (command->cmd == LC_SEGMENT_64) {
                    const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
                    minimumVMAddress = MIN(minimumVMAddress, segment->vmaddr);
                    maximumVMAddress = MAX(maximumVMAddress, segment->vmaddr + segment->vmsize);
                } else if (command->cmd == LC_UUID) {
                    const struct uuid_command *UUIDCommand = (const struct uuid_command *)command;
                    memcpy(imageUUID, UUIDCommand->uuid, sizeof(imageUUID));
                    hasUUID = YES;
                }
                commandBytes += command->cmdsize;
            }
        } else if (header->magic == MH_MAGIC) {
            const uint8_t *commandBytes = (const uint8_t *)(header + 1);
            for (uint32_t commandIndex = 0; commandIndex < header->ncmds; commandIndex += 1) {
                const struct load_command *command = (const struct load_command *)commandBytes;
                if (command->cmd == LC_SEGMENT) {
                    const struct segment_command *segment = (const struct segment_command *)command;
                    minimumVMAddress = MIN(minimumVMAddress, segment->vmaddr);
                    maximumVMAddress = MAX(maximumVMAddress, segment->vmaddr + segment->vmsize);
                } else if (command->cmd == LC_UUID) {
                    const struct uuid_command *UUIDCommand = (const struct uuid_command *)command;
                    memcpy(imageUUID, UUIDCommand->uuid, sizeof(imageUUID));
                    hasUUID = YES;
                }
                commandBytes += command->cmdsize;
            }
        }
        if (minimumVMAddress == UINT64_MAX || maximumVMAddress <= minimumVMAddress) {
            continue;
        }

        uint64_t runtimeBase = (uint64_t)(uintptr_t)header - minimumVMAddress;
        NSMutableDictionary *entry = [@{
            @"path": [NSString stringWithUTF8String:name] ?: @"",
            @"base": @(runtimeBase),
            @"size": @(maximumVMAddress - minimumVMAddress),
            @"slide": @(_dyld_get_image_vmaddr_slide(index))
        } mutableCopy];
        if (hasUUID) {
            entry[@"uuid"] = WCLiquidGlassUUIDStringFromBytes(imageUUID);
        }
        [images addObject:entry];
    }
    if (![images writeToURL:[self wc_imageSnapshotURL] atomically:YES]) {
        WCLiquidGlassRecordEvent(@"Prior-process image snapshot write failed");
    }
}

- (void)wc_recoverSignalCrashMarker {
    NSURL *markerURL = [self wc_crashMarkerURL];
    NSData *data = [NSData dataWithContentsOfURL:markerURL options:0 error:nil];
    if (data.length == 0) {
        return;
    }
    WCLiquidGlassCrashMarker marker = {0};
    if (data.length != sizeof(marker)) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Crash marker ignored because size was %lu",
                                  (unsigned long)data.length]);
        [NSFileManager.defaultManager removeItemAtURL:markerURL error:nil];
        return;
    }
    memcpy(&marker, data.bytes, sizeof(marker));
    if (marker.magic != WCLiquidGlassCrashMarkerMagic ||
        marker.version != WCLiquidGlassCrashMarkerVersion) {
        WCLiquidGlassRecordEvent(@"Crash marker ignored because its header was invalid");
        [NSFileManager.defaultManager removeItemAtURL:markerURL error:nil];
        return;
    }

    NSDate *crashDate = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)marker.timestampSeconds +
                                                               (NSTimeInterval)marker.timestampNanoseconds / 1000000000.0];
    NSArray<NSDictionary *> *images = [NSArray arrayWithContentsOfURL:[self wc_imageSnapshotURL]] ?: @[];
    NSDictionary *session = [NSDictionary dictionaryWithContentsOfURL:[self wc_sessionURL]] ?: @{};
    NSString *previousEvents = WCLiquidGlassRecentEventsPath.length > 0
        ? [NSString stringWithContentsOfFile:WCLiquidGlassRecentEventsPath
                                    encoding:NSUTF8StringEncoding
                                       error:nil]
        : nil;
    NSString *pcImage = WCLiquidGlassImagePathForAddress(images, marker.programCounter);
    NSString *lrImage = WCLiquidGlassImagePathForAddress(images, marker.linkRegister);
    NSString *faultImage = WCLiquidGlassImagePathForAddress(images, marker.faultAddress);
    NSMutableArray<NSString *> *candidatePlugins = [NSMutableArray array];
    for (NSDictionary *image in images) {
        NSString *path = image[@"path"];
        if (WCLiquidGlassLooksLikeInjectedImage(path) && ![candidatePlugins containsObject:path]) {
            [candidatePlugins addObject:path];
        }
    }
    [candidatePlugins sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    NSString *faultDescription = faultImage
        ? [NSString stringWithFormat:@" (%@)", faultImage]
        : @"";
    NSString *pcDescription = pcImage
        ? [NSString stringWithFormat:@" (%@)", pcImage]
        : @"";
    NSString *lrDescription = lrImage
        ? [NSString stringWithFormat:@" (%@)", lrImage]
        : @"";
    NSMutableString *content = [NSMutableString stringWithFormat:
                                 @"%@\n"
                                  "Capture Method: pre-opened fixed binary marker; fatal signal handler performed no Objective-C calls or stack unwinding.\n"
                                  "Crash Timestamp: %@\n"
                                  "Fatal Signal: %@ (%u)\n"
                                  "Signal Code: %d\n"
                                  "Crashed Process PID: %u\n"
                                  "Fault Address: 0x%llx%@\n"
                                  "PC: 0x%llx%@\n"
                                  "SP: 0x%llx\n"
                                  "FP: 0x%llx\n"
                                  "LR: 0x%llx%@\n"
                                  "Session ID: %@\n"
                                  "Prior Session Start: %@\n"
                                  "Prior-process image snapshot: %@\n"
                                  "Signal crash stack availability is intentionally limited because WCLiquidGlass avoids unsafe stack unwinding inside fatal signal handlers.\n\n",
                                 WCLiquidGlassReportHeaderWithEvents(@"Recovered Native Signal",
                                                                     previousEvents.length > 0 ? previousEvents : @"None"),
                                 WCLiquidGlassTimestampForDate(crashDate),
                                 WCLiquidGlassSignalName((int)marker.signalNumber),
                                 marker.signalNumber,
                                 marker.signalCode,
                                 marker.processID,
                                 marker.faultAddress,
                                 faultDescription,
                                 marker.programCounter,
                                 pcDescription,
                                 marker.stackPointer,
                                 marker.framePointer,
                                 marker.linkRegister,
                                 lrDescription,
                                 WCLiquidGlassUUIDStringFromBytes(marker.sessionID),
                                 session[@"startDate"] ?: @"Unknown",
                                 images.count > 0 ? @"available" : @"unavailable; PC/LR attribution withheld"];
    [content appendFormat:@"Candidate Injected Plugins at Crash:\n%@\n\n",
                           candidatePlugins.count > 0 ? [candidatePlugins componentsJoinedByString:@"\n"] : @"None available"];
    if (session[@"sessionID"] && ![session[@"sessionID"] isEqual:WCLiquidGlassUUIDStringFromBytes(marker.sessionID)]) {
        [content appendFormat:@"Session Metadata Mismatch: %@\n\n", session[@"sessionID"]];
    }

    NSString *baseName = [NSString stringWithFormat:@"Crash-%@-%@",
                          WCLiquidGlassTimestampForDate(crashDate),
                          WCLiquidGlassSignalName((int)marker.signalNumber)];
    NSURL *reportURL = [self.class.crashLogsDirectoryURL
                        URLByAppendingPathComponent:[baseName stringByAppendingString:@".crash"]];
    if ([NSFileManager.defaultManager fileExistsAtPath:reportURL.path]) {
        reportURL = [self.class.crashLogsDirectoryURL
                     URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.crash",
                                                 baseName,
                                                 NSUUID.UUID.UUIDString]];
    }
    NSError *writeError = nil;
    if (![content writeToURL:reportURL atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Recovered signal report write failed: %@",
                                  writeError.localizedDescription ?: @"Unknown error"]);
        return;
    }
    [NSFileManager.defaultManager removeItemAtURL:markerURL error:nil];
    if (WCLiquidGlassRecentEventsPath.length > 0) {
        [NSFileManager.defaultManager removeItemAtPath:WCLiquidGlassRecentEventsPath error:nil];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:WCLiquidGlassCrashLogsDidChangeNotification object:nil];
}

- (void)wc_installExceptionHandler {
    if (WCLiquidGlassExceptionHandlerInstalled) {
        return;
    }
    WCLiquidGlassExceptionLogger = self;
    WCLiquidGlassPreviousExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(WCLiquidGlassHandleException);
    WCLiquidGlassExceptionHandlerInstalled = YES;
}

- (void)wc_writeUncaughtException:(NSException *)exception {
    NSString *stack = [exception.callStackSymbols componentsJoinedByString:@"\n"];
    NSString *content = [NSString stringWithFormat:
                          @"%@\n"
                           "Capture Method: synchronous uncaught-exception handler before forwarding to the previous handler.\n"
                           "Exception Name: %@\n"
                           "Exception Reason: %@\n"
                           "Exception User Info: %@\n"
                           "Call Stack:\n%@\n",
                          WCLiquidGlassReportHeader(@"Uncaught Objective-C Exception"),
                          exception.name ?: @"Unknown",
                          exception.reason ?: @"Unknown",
                          exception.userInfo ?: @{},
                          stack.length > 0 ? stack : @"Unavailable"];
    NSURL *URL = [self.class.crashLogsDirectoryURL
                  URLByAppendingPathComponent:[NSString stringWithFormat:@"Crash-%@-ObjectiveC-%@.crash",
                                              WCLiquidGlassTimestamp(),
                                              NSUUID.UUID.UUIDString]];
    NSError *error = nil;
    if (![content writeToURL:URL atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        WCLiquidGlassRecordEvent([NSString stringWithFormat:@"Objective-C exception report write failed: %@",
                                  error.localizedDescription ?: @"Unknown error"]);
        return;
    }
    [NSNotificationCenter.defaultCenter postNotificationName:WCLiquidGlassCrashLogsDidChangeNotification object:nil];
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
                                    shouldRegisterUncaughtExceptionHandler:NO
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
