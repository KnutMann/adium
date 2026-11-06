// click: synthetic mouse and keyboard input through the HID event tap, in screen points with
// the origin at the top left. Needs the Accessibility permission of the terminal.
//   click click <x> <y>              click <x> <y> [right]
//   click drag <x1> <y1> <x2> <y2>   press at the first point, move in steps, release at the second
//   click key <keycode> [cmd] [shift] [alt] [ctrl]
//   click type <text>                type a string (ASCII) via unicode key events
#import <Cocoa/Cocoa.h>
static void post(CGEventRef e) { CGEventPost(kCGHIDEventTap, e); CFRelease(e); usleep(40000); }
static void mouse(CGEventType t, CGPoint p, CGMouseButton b) { post(CGEventCreateMouseEvent(NULL, t, p, b)); }
int main(int argc, char **argv) { @autoreleasepool {
  if (argc < 2) return 2;
  NSString *cmd = @(argv[1]);
  if ([cmd isEqualToString:@"where"]) { CGEventRef e = CGEventCreate(NULL); CGPoint p = CGEventGetLocation(e); CFRelease(e); printf("%.0f,%.0f\n", p.x, p.y); return 0; }
  if ([cmd isEqualToString:@"move"] && argc >= 4) { mouse(kCGEventMouseMoved, CGPointMake(atof(argv[2]), atof(argv[3])), kCGMouseButtonLeft); printf("moved\n"); return 0; }
  if ([cmd isEqualToString:@"trusted"]) { printf("AXIsProcessTrusted=%d\n", AXIsProcessTrusted()); return 0; }
  if ([cmd isEqualToString:@"scroll"] && argc >= 5) {   // scroll <x> <y> <lines>: negative lines scroll the content up (towards its end)
    CGPoint p = CGPointMake(atof(argv[2]), atof(argv[3])); mouse(kCGEventMouseMoved, p, kCGMouseButtonLeft); usleep(100000);
    int lines = atoi(argv[4]); int step = lines < 0 ? -3 : 3;
    for (int done = 0; abs(done) < abs(lines); done += step) { CGEventRef e = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, step); CGEventSetLocation(e, p); post(e); }
    printf("scrolled %d lines at %.0f,%.0f\n", lines, p.x, p.y); return 0;
  }
  if ([cmd isEqualToString:@"click"] && argc >= 4) {
    CGPoint p = CGPointMake(atof(argv[2]), atof(argv[3]));
    BOOL right = argc > 4 && !strcmp(argv[4], "right");
    mouse(kCGEventMouseMoved, p, kCGMouseButtonLeft);
    mouse(right ? kCGEventRightMouseDown : kCGEventLeftMouseDown, p, right ? kCGMouseButtonRight : kCGMouseButtonLeft);
    mouse(right ? kCGEventRightMouseUp : kCGEventLeftMouseUp, p, right ? kCGMouseButtonRight : kCGMouseButtonLeft);
    printf("clicked %.0f,%.0f\n", p.x, p.y); return 0;
  }
  if ([cmd isEqualToString:@"drag"] && argc >= 6) {
    CGPoint a = CGPointMake(atof(argv[2]), atof(argv[3])), b = CGPointMake(atof(argv[4]), atof(argv[5]));
    mouse(kCGEventMouseMoved, a, kCGMouseButtonLeft); usleep(100000);
    mouse(kCGEventLeftMouseDown, a, kCGMouseButtonLeft); usleep(150000);
    for (int i = 1; i <= 20; i++) { CGPoint p = CGPointMake(a.x + (b.x - a.x) * i / 20.0, a.y + (b.y - a.y) * i / 20.0); mouse(kCGEventLeftMouseDragged, p, kCGMouseButtonLeft); }
    usleep(150000); mouse(kCGEventLeftMouseUp, b, kCGMouseButtonLeft);
    printf("dragged %.0f,%.0f -> %.0f,%.0f\n", a.x, a.y, b.x, b.y); return 0;
  }
  if ([cmd isEqualToString:@"key"] && argc >= 3) {
    CGEventFlags f = 0;
    for (int i = 3; i < argc; i++) { if (!strcmp(argv[i], "cmd")) f |= kCGEventFlagMaskCommand; if (!strcmp(argv[i], "shift")) f |= kCGEventFlagMaskShift; if (!strcmp(argv[i], "alt")) f |= kCGEventFlagMaskAlternate; if (!strcmp(argv[i], "ctrl")) f |= kCGEventFlagMaskControl; }
    CGEventRef d = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)atoi(argv[2]), true), u = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)atoi(argv[2]), false);
    CGEventSetFlags(d, f); CGEventSetFlags(u, f); post(d); post(u); printf("key %s\n", argv[2]); return 0;
  }
  if ([cmd isEqualToString:@"type"] && argc >= 3) {
    NSString *s = @(argv[2]);
    for (NSUInteger i = 0; i < s.length; i++) { unichar c = [s characterAtIndex:i];
      CGEventRef d = CGEventCreateKeyboardEvent(NULL, 0, true), u = CGEventCreateKeyboardEvent(NULL, 0, false);
      CGEventKeyboardSetUnicodeString(d, 1, &c); CGEventKeyboardSetUnicodeString(u, 1, &c); post(d); post(u); }
    printf("typed %lu chars\n", (unsigned long)s.length); return 0;
  }
  fprintf(stderr, "usage: see header\n"); return 2;
} }
