/* Checks the reader for XEP-0393: what is markup, and what is ordinary text.
 *
 * Almost all the rules of the standard exist to keep the second apart from the first. An
 * underscore in the middle of an address, an asterisk at the start of a sentence with no
 * counterpart, a hyphen in a list: none of these may turn half the line italic. Exactly those
 * cases stand here, next to the cases that really are markup.
 *
 * Counting is done in the same units NSString counts in, that is UTF-16. An emoji in front of a
 * directive shifts it by two, not by one; that has hurt this tree once already over XEP-0428
 * and therefore stands in it as a case of its own.
 */
#import <Foundation/Foundation.h>
#import "AIMessageStyling.h"

static int checks = 0, failures = 0;

static NSString *KindName(AIMessageStyleKind k)
{
	switch (k) {
		case AIMessageStyleEmphasis:		return @"emphasis";
		case AIMessageStyleStrong:			return @"strong";
		case AIMessageStyleStrikethrough:	return @"strikethrough";
		case AIMessageStylePreformatted:	return @"preformatted";
		case AIMessageStyleQuotation:		return @"quotation";
	}
	return @"?";
}

/* A list of "kind:text" is expected, where text is the extract the span covers, directives
   included. The order does not matter. */
static void Expect(NSString *body, NSArray<NSString *> *wanted)
{
	checks++;

	NSMutableArray *got = [NSMutableArray array];
	for (AIMessageStyleSpan *span in AIMessageStylingSpans(body)) {
		[got addObject:[NSString stringWithFormat:@"%@:%@",
						KindName(span.kind), [body substringWithRange:span.range]]];
	}

	NSCountedSet *a = [NSCountedSet setWithArray:got];
	NSCountedSet *b = [NSCountedSet setWithArray:wanted];

	if (![a isEqual:b]) {
		failures++;
		printf("FAILED  %s\n        expected %s\n        got      %s\n",
			   [body UTF8String],
			   [[wanted componentsJoinedByString:@" | "] UTF8String],
			   [[got componentsJoinedByString:@" | "] UTF8String]);
	}
}

int main(void)
{
	@autoreleasepool {
		//The simple cases
		Expect(@"*bold*", @[@"strong:*bold*"]);
		Expect(@"_italic_", @[@"emphasis:_italic_"]);
		Expect(@"~gone~", @[@"strikethrough:~gone~"]);
		Expect(@"`code`", @[@"preformatted:`code`"]);
		Expect(@"a *bolder* word", @[@"strong:*bolder*"]);
		Expect(@"*two* and *three*", @[@"strong:*two*", @"strong:*three*"]);

		//Nesting: different kinds yes, the same kind no
		Expect(@"*_both_*", @[@"strong:*_both_*", @"emphasis:_both_"]);

		//Inside fixed width nothing is read
		Expect(@"`no *bold* in here`", @[@"preformatted:`no *bold* in here`"]);

		//The rules that protect ordinary text
		Expect(@"https://example.com/a_b_c", @[]);			//the opener does not follow a space
		Expect(@"*no closer", @[]);
		Expect(@"* not opened*", @[]);						//a space behind the opener
		Expect(@"*not closed *", @[]);						//a space before the closer
		Expect(@"**", @[]);									//nothing in between
		Expect(@"5 * 3 * 2", @[]);							//arithmetic is not markup
		Expect(@"snake_case_name", @[]);

		//Quotation
		Expect(@"> said", @[@"quotation:> said"]);
		Expect(@"> *loudly* said", @[@"quotation:> *loudly* said", @"strong:*loudly*"]);
		Expect(@"not > in the middle", @[]);

		//A block, closed and open
		Expect(@"```\nline\n```", @[@"preformatted:```\nline\n```"]);
		Expect(@"```\nwith no end", @[@"preformatted:```\nwith no end"]);
		Expect(@"before\n```\ninside *not bold*\n```\nafter",
			   @[@"preformatted:```\ninside *not bold*\n```"]);

		//Several lines: a span ends at its own line
		Expect(@"*across\ntwo*", @[]);

		//UTF-16: an emoji counts as two
		Expect(@"\U0001F600 *bold*", @[@"strong:*bold*"]);
		{
			checks++;
			NSString *body = @"\U0001F600 *bold*";
			NSArray *spans = AIMessageStylingSpans(body);
			NSRange r = [spans.firstObject range];
			if (r.location != 3) {			//two units of emoji plus one space
				failures++;
				printf("FAILED  emoji offset: expected 3, got %lu\n", (unsigned long)r.location);
			}
		}

		//The empty and the harmless
		Expect(@"", @[]);
		Expect(@"perfectly ordinary text", @[]);

		printf("%d checks, %d failures\n", checks, failures);
	}
	return failures ? 1 : 0;
}
