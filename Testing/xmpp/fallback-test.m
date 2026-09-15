/* Schneidet XEP-0428 die richtige Stelle heraus?
 *
 * Eine Antwort aus einem modernen Client zitiert die Nachricht, auf die sie antwortet, als
 * Zeilen mit vorangestelltem Groesserzeichen, und sagt daneben, welche Zeichen davon nur fuer
 * Clients gedacht waren, die Antworten nicht darstellen koennen. Wir sind so einer, also
 * muessen wir genau diese Zeichen weglassen.
 *
 * Geprueft wird UNSERE Rechnung, nicht glibs Zeichenzaehler: dass die Bereiche als Zeichen
 * und nicht als Bytes gelesen werden, dass unsinnige Bereiche verworfen statt zurechtgebogen
 * werden, und vor allem, dass von hinten nach vorn geschnitten wird, denn sonst verschiebt
 * der erste Schnitt alle folgenden Zahlen. Die Sortierung und die Pruefung stehen hier
 * wortgleich wie in adiumPurpleFallback.m; der Zeiger auf das n-te Zeichen wird hier
 * nachgebaut, damit der Test ohne die gebuendelten Bibliotheken laeuft.
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

/*! Wie g_utf8_offset_to_pointer: der Zeiger auf das n-te ZEICHEN, nicht auf das n-te Byte */
static const char *characterAt(const char *text, long offset)
{
	while (offset-- > 0 && *text)
		do { text++; } while ((*text & 0xC0) == 0x80);	//Folgebytes ueberspringen
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

/*! Die Reihenfolge aus adiumPurpleFallback.m: absteigend nach Anfang, damit von hinten geschnitten wird */
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

/*! Die Pruefung aus adiumPurpleFallback.m: was nicht passt, wird verworfen, nicht zurechtgebogen */
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
		  [NSString stringWithFormat:@"erwartet \"%s\", bekommen \"%s\"", wanted, got]);
	free(got);
}

int main(void) { @autoreleasepool {
	//Der Alltagsfall: ein Zitat vorn, die eigentliche Antwort dahinter
	{
		Range r[] = {{0, 17}};
		expect(@"Das Zitat vorn faellt weg", "> Kommst du mit?\nJa, gerne", r, 1, "Ja, gerne");
	}

	//Umlaute: byteweise geschnitten stuende hier Unsinn, der Bereich zaehlt Zeichen
	{
		Range r[] = {{0, 20}};
		expect(@"Umlaute verschieben den Schnitt nicht", "> Grüße aus München\nDanke!", r, 1, "Danke!");
	}

	//Ein Emoji ist ein Zeichen und belegt vier Bytes
	{
		Range r[] = {{0, 4}};
		expect(@"Auch ein Emoji zaehlt als ein Zeichen", "> 👍\nstimmt", r, 1, "stimmt");
	}

	//Mehrere Bereiche, absichtlich in der falschen Reihenfolge uebergeben
	{
		Range r[] = {{0, 3}, {6, 9}};
		expect(@"Mehrere Bereiche, egal in welcher Reihenfolge", "AAABBBCCC", r, 2, "BBB");
	}

	//Unsinn wird verworfen, nicht zurechtgebogen
	{
		Range r[] = {{5, 2}};
		expect(@"Ein verdrehter Bereich wird verworfen", "unberuehrt", r, 1, "unberuehrt");
	}
	{
		Range r[] = {{0, 999}};
		expect(@"Ein Bereich ueber das Ende hinaus wird verworfen", "unberuehrt", r, 1, "unberuehrt");
	}

	//Nichts markiert heisst nichts angefasst
	expect(@"Ohne Bereich bleibt alles stehen", "einfach nur Text", NULL, 0, "einfach nur Text");

	//Der ganze Body als Bereich: uebrig bleibt nichts, und das ist richtig so
	{
		Range r[] = {{0, 10}};
		expect(@"Ein Bereich ueber alles laesst nichts uebrig", "nur Ersatz", r, 1, "");
	}

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
