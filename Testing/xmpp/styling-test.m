/* Prueft den Leser fuer XEP-0393: was ist Auszeichnung, und was ist gewoehnlicher Text.
 *
 * Die Regeln des Standards sind fast alle dazu da, das Zweite vom Ersten zu trennen. Ein
 * Unterstrich mitten in einer Adresse, ein Sternchen am Satzanfang ohne Gegenstueck, ein
 * Bindestrich in einer Aufzaehlung: nichts davon darf die halbe Zeile kursiv machen. Genau
 * diese Faelle stehen hier, neben den Faellen, die wirklich Auszeichnung sind.
 *
 * Gerechnet wird in denselben Einheiten, in denen NSString zaehlt, also UTF-16. Ein Emoji
 * vor einer Direktive verschiebt sie um zwei, nicht um eins; das hat diesem Baum bei
 * XEP-0428 schon einmal wehgetan und steht deshalb als eigener Fall darin.
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

/* Erwartet wird eine Liste von "art:text", wobei text der Ausschnitt ist, den die Spanne
   abdeckt, Direktiven eingeschlossen. Reihenfolge spielt keine Rolle. */
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
		printf("FEHLER  %s\n        erwartet %s\n        bekommen %s\n",
			   [body UTF8String],
			   [[wanted componentsJoinedByString:@" | "] UTF8String],
			   [[got componentsJoinedByString:@" | "] UTF8String]);
	}
}

int main(void)
{
	@autoreleasepool {
		//Das Einfache
		Expect(@"*fett*", @[@"strong:*fett*"]);
		Expect(@"_kursiv_", @[@"emphasis:_kursiv_"]);
		Expect(@"~weg~", @[@"strikethrough:~weg~"]);
		Expect(@"`code`", @[@"preformatted:`code`"]);
		Expect(@"ein *fettes* Wort", @[@"strong:*fettes*"]);
		Expect(@"*zwei* und *drei*", @[@"strong:*zwei*", @"strong:*drei*"]);

		//Verschachtelung: verschiedene Arten ja, gleiche Art nicht
		Expect(@"*_beides_*", @[@"strong:*_beides_*", @"emphasis:_beides_"]);

		//In Festbreite wird innen nichts gelesen
		Expect(@"`kein *fett* hier`", @[@"preformatted:`kein *fett* hier`"]);

		//Die Regeln, die gewoehnlichen Text schuetzen
		Expect(@"https://example.com/a_b_c", @[]);			//Oeffner folgt keinem Leerzeichen
		Expect(@"*kein Schliesser", @[]);
		Expect(@"* nicht offen*", @[]);						//Leerzeichen hinter dem Oeffner
		Expect(@"*nicht zu *", @[]);						//Leerzeichen vor dem Schliesser
		Expect(@"**", @[]);									//nichts dazwischen
		Expect(@"5 * 3 * 2", @[]);							//Rechnen ist keine Auszeichnung
		Expect(@"snake_case_name", @[]);

		//Zitat
		Expect(@"> gesagt", @[@"quotation:> gesagt"]);
		Expect(@"> *laut* gesagt", @[@"quotation:> *laut* gesagt", @"strong:*laut*"]);
		Expect(@"nicht > mitten drin", @[]);

		//Block, geschlossen und offen
		Expect(@"```\nzeile\n```", @[@"preformatted:```\nzeile\n```"]);
		Expect(@"```\nohne Ende", @[@"preformatted:```\nohne Ende"]);
		Expect(@"vorher\n```\ndrin *nicht fett*\n```\nnachher",
			   @[@"preformatted:```\ndrin *nicht fett*\n```"]);

		//Mehrere Zeilen: eine Spanne endet an ihrer Zeile
		Expect(@"*auf\nzwei*", @[]);

		//UTF-16: ein Emoji zaehlt zwei
		Expect(@"\U0001F600 *fett*", @[@"strong:*fett*"]);
		{
			checks++;
			NSString *body = @"\U0001F600 *fett*";
			NSArray *spans = AIMessageStylingSpans(body);
			NSRange r = [spans.firstObject range];
			if (r.location != 3) {			//zwei Einheiten Emoji plus ein Leerzeichen
				failures++;
				printf("FEHLER  Emoji-Versatz: erwartet 3, bekommen %lu\n", (unsigned long)r.location);
			}
		}

		//Leeres und Harmloses
		Expect(@"", @[]);
		Expect(@"ganz gewoehnlicher Text", @[]);

		printf("%d Pruefungen, %d Fehler\n", checks, failures);
	}
	return failures ? 1 : 0;
}
