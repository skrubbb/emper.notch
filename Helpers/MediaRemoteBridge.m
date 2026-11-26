// Emper system "now playing" bridge.
// macOS 15.4+ only lets Apple-entitled processes read MediaRemote. /usr/bin/perl is such a process, so
// Emper starts `perl` and has it load this library (same idea as the open-source mediaremote-adapter;
// written from scratch). The library streams one JSON line per change to stdout and reads commands
// from stdin: play, pause, toggle, next, previous, seek <seconds>.
// Private API: may break in a future macOS. Emper keeps Spotify / Apple Music on their own path.
#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetBoolFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef NSString *(*ClientStringFn)(id);
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*SendFn)(int, CFDictionaryRef);
typedef void (*SetTimeFn)(double);

static GetInfoFn getInfo;
static GetBoolFn getPlaying;
static GetClientFn getClient;
static ClientStringFn clientBundle, clientParent;
static SendFn sendCommand;
static SetTimeFn setTime;
static NSUInteger lastArtHash;
static dispatch_queue_t q;

static void emit(NSDictionary *d) {
    NSData *j = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
    if (!j) return;
    fwrite(j.bytes, 1, j.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void refresh(void) {
    getClient(q, ^(id client) {
        NSString *bundle = client && clientBundle ? clientBundle(client) : nil;
        NSString *parent = client && clientParent ? clientParent(client) : nil;
        getPlaying(q, ^(Boolean playing) {
            getInfo(q, ^(CFDictionaryRef ref) {
                NSDictionary *info = (__bridge NSDictionary *)ref;
                NSMutableDictionary *o = [NSMutableDictionary dictionary];
                o[@"bundle"] = bundle ?: @"";
                o[@"parent"] = parent ?: @"";
                o[@"playing"] = @(playing ? YES : NO);
                o[@"title"] = info[@"kMRMediaRemoteNowPlayingInfoTitle"] ?: @"";
                o[@"artist"] = info[@"kMRMediaRemoteNowPlayingInfoArtist"] ?: @"";
                o[@"album"] = info[@"kMRMediaRemoteNowPlayingInfoAlbum"] ?: @"";
                o[@"duration"] = info[@"kMRMediaRemoteNowPlayingInfoDuration"] ?: @0;
                o[@"elapsed"] = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] ?: @0;
                o[@"rate"] = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] ?: @0;
                NSDate *ts = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                o[@"timestamp"] = @(ts ? ts.timeIntervalSince1970 : 0);
                NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                NSUInteger h = art ? art.hash ^ art.length : 0;
                if (h != lastArtHash) {
                    lastArtHash = h;
                    o[@"artwork"] = art ? [art base64EncodedStringWithOptions:0] : @"";
                }
                emit(o);
            });
        });
    });
}

static void handle(NSString *line) {
    NSArray *p = [line componentsSeparatedByString:@" "];
    NSString *c = p.firstObject;
    if ([c isEqualToString:@"play"]) sendCommand(0, NULL);
    else if ([c isEqualToString:@"pause"]) sendCommand(1, NULL);
    else if ([c isEqualToString:@"toggle"]) sendCommand(2, NULL);
    else if ([c isEqualToString:@"next"]) sendCommand(4, NULL);
    else if ([c isEqualToString:@"previous"]) sendCommand(5, NULL);
    else if ([c isEqualToString:@"seek"] && p.count > 1 && setTime) setTime([p[1] doubleValue]);
    else if ([c isEqualToString:@"refresh"]) refresh();
}

void emper_mediaremote_stream(void) {
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!h) { emit(@{@"error": @"MediaRemote not found"}); return; }
    getInfo = (GetInfoFn)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
    getPlaying = (GetBoolFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getClient = (GetClientFn)dlsym(h, "MRMediaRemoteGetNowPlayingClient");
    clientBundle = (ClientStringFn)dlsym(h, "MRNowPlayingClientGetBundleIdentifier");
    clientParent = (ClientStringFn)dlsym(h, "MRNowPlayingClientGetParentAppBundleIdentifier");
    sendCommand = (SendFn)dlsym(h, "MRMediaRemoteSendCommand");
    setTime = (SetTimeFn)dlsym(h, "MRMediaRemoteSetElapsedTime");
    RegisterFn reg = (RegisterFn)dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!getInfo || !getPlaying || !getClient || !sendCommand || !reg) { emit(@{@"error": @"MediaRemote symbols missing"}); return; }
    q = dispatch_queue_create("emper.mediaremote", DISPATCH_QUEUE_SERIAL);
    reg(q);
    for (NSString *n in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                          @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                          @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(q, ^{ refresh(); });
        }];
    }
    // Commands from Emper on stdin; EOF (Emper quit) ends the helper.
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        char buf[512];
        while (fgets(buf, sizeof buf, stdin)) {
            NSString *line = [[NSString stringWithUTF8String:buf] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            dispatch_async(q, ^{ handle(line); });
        }
        exit(0);
    });
    dispatch_async(q, ^{ refresh(); });
    CFRunLoopRun();
}
