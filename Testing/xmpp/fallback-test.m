/* Does XEP-0428 cut out the right place?
 *
 * A reply from a modern client quotes the message it answers as lines with a leading greater
 * than sign, and says alongside which characters of it were only meant for clients that cannot
 * show replies. We are one of those, so we have to leave exactly those characters out.
 *
 * What is checked is OUR arithmetic, not glib's character counter: that the ranges are read as
 * characters and not as bytes, that nonsensical ranges are discarded rather than bent into
 * shape, and above all that the cutting runs from the back to the front, because otherwise the
 * first cut shifts every number after it. The sorting and the sanity check stand here word for
 * word as they do in adiumPurpleFallback.m; the pointer to the nth character is rebuilt here so
 * that the test runs without the bundled libraries.
 */
#import <Foundation/Foundation.h>

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

typedef struct { long start; long end; } Range;

/*! Like g_utf8_offset_to_pointer: the pointer to the nth CHARACTER, not to the nth byte */
static const char *characterAt(const char *text, long offset)
{
	while (offset-- > 0 && *text)
		do { text++; } while ((*text & 0xC0) == 0x80);	//skip continuation bytes
	return text;
}

static long characterCount(const char *text)
{
	long count = 0;
	for (const char *at = text; *at; at++)
		if ((*at & 0xC0) != 0x80)
			count++;
	return count;
}

/*! The order from adiumPurpleFallback.m: descending by start, so the cutting runs from the back */
static void sortDescending(Range *ranges, int count)
{
	for (int outer = 0; outer + 1 < count; outer++)
		for (int inner = 0; inner + 1 < count - outer; inner++)
			if (ranges[inner].start < ranges[inner + 1].start) {
				Range swap = ranges[inner];
				ranges[inner] = ranges[inner + 1];
				ranges[inner + 1] = swap;
			}
}

/*! The check from adiumPurpleFallback.m: what does not fit is discarded, not bent into shape */
static BOOL rangeIsSane(Range range, long length)
{
	return (range.start >= 0 && range.end <= length && range.start < range.end);
}

static char *textWithout(const char *text, Range *ranges, int count)
{
	NSMutableData *buffer = [NSMutableData dataWithBytes:text length:strlen(text) + 1];
	long length = characterCount(text);

	Range sane[16];
	int saneCount = 0;
	for (int index = 0; index < count && saneCount < 16; index++)
		if (rangeIsSane(ranges[index], length))
			sane[saneCount++] = ranges[index];
	sortDescending(sane, saneCount);

	for (int index = 0; index < saneCount; index++) {
		char *left = [buffer mutableBytes];
		const char *from = characterAt(left, sane[index].start);
		const char *to = characterAt(left, sane[index].end);
		memmove((void *)from, to, strlen(to) + 1);
	}
	return strdup([buffer bytes]);
}

static void expect(NSString *name, const char *text, Range *ranges, int count, const char *wanted)
{
	char *got = textWithout(text, ranges, count);
	check(name, strcmp(got, wanted) == 0,
		  [NSString stringWithFormat:@"expected \"%s\", got \"%s\"", wanted, got]);
	free(got);
}

int main(void) { @autoreleasepool {
	//The everyday case: a quotation in front, the actual answer behind it
	{
		Range r[] = {{0, 17}};
		expect(@"The quotation in front falls away", "> Will you come?\nYes, gladly", r, 1, "Yes, gladly");
	}

	//Accents: cut by bytes there would be nonsense here, the range counts characters
	{
		Range r[] = {{0, 20}};
		expect(@"Accents do not shift the cut", "> Café au lait, oui\nThanks!", r, 1, "Thanks!");
	}

	//An emoji is one character and takes up four bytes
	{
		Range r[] = {{0, 4}};
		expect(@"An emoji counts as one character too", "> 👍\nright", r, 1, "right");
	}

	//Several ranges, handed over in the wrong order on purpose
	{
		Range r[] = {{0, 3}, {6, 9}};
		expect(@"Several ranges, in whatever order", "AAABBBCCC", r, 2, "BBB");
	}

	//Nonsense is discarded, not bent into shape
	{
		Range r[] = {{5, 2}};
		expect(@"A back to front range is discarded", "untouched", r, 1, "untouched");
	}
	{
		Range r[] = {{0, 999}};
		expect(@"A range past the end is discarded", "untouched", r, 1, "untouched");
	}

	//Nothing marked means nothing touched
	expect(@"With no range everything stays", "simply text", NULL, 0, "simply text");

	//The whole body as a range: nothing is left, and that is right
	{
		Range r[] = {{0, 10}};
		expect(@"A range over everything leaves nothing", "spare text", r, 1, "");
	}

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
} }
