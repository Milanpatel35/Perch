// The Now Playing helper. Loaded by `/usr/bin/perl` (perch-mediaremote.pl),
// never by Perch itself.
//
// From macOS 15.4, MediaRemote answers only Apple-signed processes, so Perch
// asking for "what is playing" gets nothing. Apple's own perl may still ask,
// and this library is what it asks with. ADR 0010 records why, and what
// happens when Apple closes this too: Perch falls back to Music and Spotify.
//
// Two entry points, both installed into perl as subroutines:
//
//   perch_stream   prints one JSON line per change in what is playing, and
//                  exits when its stdin closes — that is, when Perch quits or
//                  dies, so no helper is ever left behind.
//   perch_command  sends one transport command, named in PERCH_COMMAND, and
//                  returns. PERCH_SEEK carries the position for "seek".
//
// No network, no files, no state: it reads MediaRemote and writes stdout.

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <unistd.h>

typedef void (*MRGetInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetIsPlaying)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetClient)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*MRClientString)(id);
typedef void (*MRRegister)(dispatch_queue_t);
typedef Boolean (*MRSendCommand)(int, CFDictionaryRef);
typedef void (*MRSetElapsed)(double);

static void *framework(void) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    });
    return handle;
}

static void *symbol(const char *name) {
    void *handle = framework();
    return handle ? dlsym(handle, name) : NULL;
}

static void emit(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) { return; }
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id number(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:[NSNumber class]] ? value : [NSNull null];
}

static NSString *text(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

/// Reads everything about what is playing and prints it as one line.
static void report(void) {
    MRGetInfo getInfo = (MRGetInfo)symbol("MRMediaRemoteGetNowPlayingInfo");
    MRGetIsPlaying getIsPlaying =
        (MRGetIsPlaying)symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    MRGetClient getClient = (MRGetClient)symbol("MRMediaRemoteGetNowPlayingClient");
    MRClientString bundleOf = (MRClientString)symbol("MRNowPlayingClientGetBundleIdentifier");
    MRClientString parentOf =
        (MRClientString)symbol("MRNowPlayingClientGetParentAppBundleIdentifier");
    if (!getInfo) {
        emit(@{@"error": @"MediaRemote is not available"});
        return;
    }

    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_time_t limit = dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC);

    __block NSDictionary *info = nil;
    getInfo(queue, ^(CFDictionaryRef dictionary) {
        info = dictionary ? [(__bridge NSDictionary *)dictionary copy] : nil;
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, limit);

    __block BOOL playing = NO;
    if (getIsPlaying) {
        getIsPlaying(queue, ^(Boolean value) {
            playing = value;
            dispatch_semaphore_signal(done);
        });
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    }

    // A browser tab reports the browser as its parent: that is the app a
    // person recognises, and the one to bring forward.
    __block NSString *bundle = @"";
    if (getClient && bundleOf) {
        getClient(queue, ^(id client) {
            if (client) {
                CFStringRef parent = parentOf ? parentOf(client) : NULL;
                CFStringRef own = bundleOf(client);
                CFStringRef chosen = parent ? parent : own;
                if (chosen) { bundle = [(__bridge NSString *)chosen copy]; }
            }
            dispatch_semaphore_signal(done);
        });
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    }

    NSString *title = text(info, @"kMRMediaRemoteNowPlayingInfoTitle");
    if (info.count == 0 || title.length == 0) {
        emit(@{@"empty": @YES});
        return;
    }

    NSMutableDictionary *line = [@{
        @"title": title,
        @"artist": text(info, @"kMRMediaRemoteNowPlayingInfoArtist"),
        @"album": text(info, @"kMRMediaRemoteNowPlayingInfoAlbum"),
        @"duration": number(info, @"kMRMediaRemoteNowPlayingInfoDuration"),
        @"elapsed": number(info, @"kMRMediaRemoteNowPlayingInfoElapsedTime"),
        @"rate": number(info, @"kMRMediaRemoteNowPlayingInfoPlaybackRate"),
        @"playing": @(playing),
        @"bundle": bundle,
    } mutableCopy];

    id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    if ([timestamp isKindOfClass:[NSDate class]]) {
        line[@"timestamp"] = @([(NSDate *)timestamp timeIntervalSince1970]);
    }

    id artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    if ([artwork isKindOfClass:[NSData class]] && [(NSData *)artwork length] > 0) {
        line[@"artwork"] = [(NSData *)artwork base64EncodedStringWithOptions:0];
    }

    emit(line);
}

void perch_stream(void) {
    // Perch holds the other end of stdin. When it goes, so does this.
    [NSThread detachNewThreadWithBlock:^{
        char buffer[64];
        while (read(STDIN_FILENO, buffer, sizeof buffer) > 0) {}
        exit(0);
    }];

    MRRegister registerFor =
        (MRRegister)symbol("MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!registerFor) {
        emit(@{@"error": @"MediaRemote is not available"});
        exit(1);
    }
    registerFor(dispatch_get_main_queue());

    // Changes arrive in bursts — title, then artwork, then rate — so they
    // are coalesced into one read a tenth of a second after the last.
    __block dispatch_block_t pending = nil;
    void (^changed)(NSNotification *) = ^(__unused NSNotification *note) {
        if (pending) { dispatch_block_cancel(pending); }
        pending = dispatch_block_create(0, ^{ report(); });
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(),
            pending);
    };

    NSArray *names = @[
        @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
    ];
    for (NSString *name in names) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:changed];
    }

    report();
    dispatch_main();
}

void perch_command(void) {
    const char *raw = getenv("PERCH_COMMAND");
    NSString *command = raw ? @(raw) : @"";

    if ([command isEqualToString:@"seek"]) {
        MRSetElapsed setElapsed = (MRSetElapsed)symbol("MRMediaRemoteSetElapsedTime");
        const char *seconds = getenv("PERCH_SEEK");
        if (setElapsed && seconds) { setElapsed(atof(seconds)); }
        return;
    }

    // MRMediaRemoteCommand values.
    int code = -1;
    if ([command isEqualToString:@"toggle"]) { code = 2; }
    else if ([command isEqualToString:@"next"]) { code = 4; }
    else if ([command isEqualToString:@"previous"]) { code = 5; }

    MRSendCommand send = (MRSendCommand)symbol("MRMediaRemoteSendCommand");
    if (send && code >= 0) { send(code, NULL); }
}
