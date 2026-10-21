#import "OWObjC.h"
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

@implementation OWObjC

+ (BOOL)catching:(NS_NOESCAPE void (^)(void))block error:(NSError **)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSString *reason = exception.reason ?: exception.name;
            *error = [NSError errorWithDomain:@"de.keno.openwispr.objc"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: reason,
                                                @"ExceptionName": exception.name}];
        }
        return NO;
    }
}

@end

// Everything the signal handler touches is prepared up front: only async-signal-safe calls in there.
static char *gMarkerPath;
static char *gBundlePath;
static time_t gStartedAt;
static volatile sig_atomic_t gHandled;
static volatile sig_atomic_t gReasonWritten;
static const int kSignals[] = {SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE};
static const time_t kMinUptimeForRelaunch = 10;

static void OWWriteMarker(const char *text) {
    int fd = open(gMarkerPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;
    write(fd, text, strlen(text));
    close(fd);
}

static void OWHandleException(NSException *exception) {
    NSArray<NSString *> *frames = exception.callStackSymbols;
    NSRange range = NSMakeRange(0, MIN((NSUInteger)20, frames.count));
    NSString *text = [NSString stringWithFormat:@"%@: %@\n\n%@\n",
                      exception.name, exception.reason ?: @"", [[frames subarrayWithRange:range] componentsJoinedByString:@"\n"]];
    OWWriteMarker(text.UTF8String);
    gReasonWritten = 1;
}

static void OWHandleSignal(int sig) {
    if (!gHandled) {
        gHandled = 1;
        if (!gReasonWritten) {
            char text[64] = "Fatal signal ";
            const char *name = sys_signame[sig];
            strlcat(text, name, sizeof(text));
            strlcat(text, "\n", sizeof(text));
            OWWriteMarker(text);
        }
        if (time(NULL) - gStartedAt >= kMinUptimeForRelaunch) {
            // Detached shell outlives this process and reopens the app once it is gone.
            char *argv[] = {"/bin/sh", "-c", "sleep 1; /usr/bin/open -n \"$0\"", gBundlePath, NULL};
            pid_t pid;
            posix_spawn(&pid, "/bin/sh", NULL, NULL, argv, environ);
        }
    }
    // Let the default action run so macOS still writes its crash report.
    signal(sig, SIG_DFL);
    raise(sig);
}

void OWInstallCrashGuard(NSString *markerPath, NSString *bundlePath) {
    gMarkerPath = strdup(markerPath.fileSystemRepresentation);
    gBundlePath = strdup(bundlePath.fileSystemRepresentation);
    gStartedAt = time(NULL);
    NSSetUncaughtExceptionHandler(&OWHandleException);
    for (size_t i = 0; i < sizeof(kSignals) / sizeof(kSignals[0]); i++) {
        signal(kSignals[i], OWHandleSignal);
    }
}
