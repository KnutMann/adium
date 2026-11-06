// List the on-screen windows of one process: id, layer, bounds, title. Run: winlist <pid>
#import <Cocoa/Cocoa.h>
int main(int argc, char **argv) { @autoreleasepool {
  pid_t pid = argc > 1 ? atoi(argv[1]) : 0;
  NSArray *wins = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly|kCGWindowListExcludeDesktopElements, kCGNullWindowID));
  for (NSDictionary *w in wins) {
    if (pid && [w[(id)kCGWindowOwnerPID] intValue] != pid) continue;
    NSDictionary *b = w[(id)kCGWindowBounds];
    printf("%d\tlayer=%d\t%dx%d@%d,%d\t%s\t%s\n", [w[(id)kCGWindowNumber] intValue], [w[(id)kCGWindowLayer] intValue],
      [b[@"Width"] intValue], [b[@"Height"] intValue], [b[@"X"] intValue], [b[@"Y"] intValue],
      [w[(id)kCGWindowOwnerName] UTF8String], [w[(id)kCGWindowName] UTF8String] ?: "");
  }
} return 0; }
