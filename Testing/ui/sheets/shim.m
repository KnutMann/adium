#import <Cocoa/Cocoa.h>

/* The one helper AITextColorPreviewView borrows from AIUtilities, so the
 * harness does not have to link the whole framework. */
@implementation NSParagraphStyle (AIParagraphStyleAdditionsShim)
+ (NSParagraphStyle *)styleWithAlignment:(NSTextAlignment)alignment
{
	NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
	style.alignment = alignment;
	return style;
}
@end

/* The one value transformer the nibs name. The real one turns a stored colour
 * string into an NSColor; here nothing is stored, so it hands back nothing. */
@interface AIColorStringTransformer : NSValueTransformer @end
@implementation AIColorStringTransformer
+ (Class)transformedValueClass { return [NSColor class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)transformedValue:(id)value { return nil; }
- (id)reverseTransformedValue:(id)value { return nil; }
+ (void)load
{
	[NSValueTransformer setValueTransformer:[[AIColorStringTransformer alloc] init]
									forName:@"AIColorStringTransformer"];
}
@end
