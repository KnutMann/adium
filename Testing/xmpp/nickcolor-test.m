/* Does our name colour work out the same as everybody else's?
 *
 * The whole point of XEP-0392 is that the same person gets the same colour in every program.
 * That holds exactly when the angle on the colour wheel is right, and the XEP has test values
 * for it. What is checked is the REAL method out of AIUtilities, not a rebuild of it.
 *
 * The brightness is deliberately left out of the check: it may follow the background and is
 * precisely not part of what the clients have agreed on.
 */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <AIUtilities/AIColorAdditions.h>

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

/*!
 * @brief The hue, worked out straight from the hex values
 *
 * Deliberately without NSColor: its HTML reader hands back a CALIBRATED colour, and every
 * conversion out of that shifts the hue by two to four degrees. That trap caught the first
 * version of the method itself, and the test must not walk into the same one.
 */
static CGFloat angleOf(NSString *hex)
{
	unsigned int value = 0;
	[[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&value];

	CGFloat red = ((value >> 16) & 0xFF) / 255.0;
	CGFloat green = ((value >> 8) & 0xFF) / 255.0;
	CGFloat blue = (value & 0xFF) / 255.0;

	CGFloat high = MAX(red, MAX(green, blue)), low = MIN(red, MIN(green, blue));
	CGFloat span = high - low;
	if (span <= 0)
		return 0;

	CGFloat angle;
	if (high == red)		angle = 60.0 * fmod((green - blue) / span, 6.0);
	else if (high == green)	angle = 60.0 * ((blue - red) / span + 2.0);
	else					angle = 60.0 * ((red - green) / span + 4.0);

	return (angle < 0 ? angle + 360.0 : angle);
}

int main(void) { @autoreleasepool {
	//The test values from section 13.1 of the XEP
	NSArray *samples = @[@[@"Romeo", @327.255249],
						 @[@"juliet@capulet.lit", @209.410400],
						 @[@"\U0001F63A", @331.199341],
						 @[@"council", @359.994507],
						 @[@"Board", @171.430664]];

	for (NSArray *sample in samples) {
		NSString *text = sample[0];
		CGFloat wanted = [sample[1] doubleValue];
		CGFloat got = angleOf([NSColor consistentColorForIdentifier:text onDarkBackground:NO]);

		/* A degree and a half of leeway: eight bits per colour channel give no more than that,
		 * the colour wheel has roughly 1.4 degrees per step at full saturation. An arithmetic
		 * error would be orders of magnitude above that, a colour space error two to four
		 * degrees. */
		CGFloat apart = fabs(got - wanted);
		if (apart > 180.0) apart = 360.0 - apart;		//once around the wheel

		check([NSString stringWithFormat:@"The angle for %@ is right", text], apart < 1.5,
			  [NSString stringWithFormat:@"worked out %.3f, expected %.3f", got, wanted]);
	}

	//The same name, asked twice, has to give the same thing
	check(@"The same input gives the same colour",
		  [[NSColor consistentColorForIdentifier:@"Romeo" onDarkBackground:NO]
		   isEqualToString:[NSColor consistentColorForIdentifier:@"Romeo" onDarkBackground:NO]], nil);

	//The background may change the brightness, but not the hue
	check(@"The background does not change the hue",
		  fabs(angleOf([NSColor consistentColorForIdentifier:@"Romeo" onDarkBackground:YES]) -
			   angleOf([NSColor consistentColorForIdentifier:@"Romeo" onDarkBackground:NO])) < 1.5, nil);

	//An empty name must not crash
	check(@"An empty name still gives something",
		  [[NSColor consistentColorForIdentifier:@"" onDarkBackground:NO] length] > 0, nil);

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
} }
