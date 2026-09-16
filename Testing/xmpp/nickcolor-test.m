/* Rechnet unsere Namensfarbe dasselbe wie alle anderen?
 *
 * Der ganze Sinn von XEP-0392 ist, dass derselbe Mensch in jedem Programm dieselbe Farbe
 * bekommt. Das gilt genau dann, wenn der Winkel auf dem Farbkreis stimmt, und dafuer hat der
 * XEP Pruefwerte. Geprueft wird die ECHTE Methode aus AIUtilities, nicht ein Nachbau.
 *
 * Die Helligkeit wird bewusst nicht mitgeprueft: sie darf sich nach dem Untergrund richten
 * und ist gerade nicht Teil dessen, worauf sich die Clients geeinigt haben.
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
 * @brief Der Farbton, direkt aus den Hexwerten gerechnet
 *
 * Bewusst ohne NSColor: dessen HTML-Leser liefert eine KALIBRIERTE Farbe, und jede Umrechnung
 * daraus verschiebt den Ton um zwei bis vier Grad. Genau diese Falle hat schon die erste
 * Fassung der Methode selbst erwischt, der Test darf nicht in dieselbe treten.
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
	//Die Pruefwerte aus Abschnitt 13.1 des XEP
	NSArray *samples = @[@[@"Romeo", @327.255249],
						 @[@"juliet@capulet.lit", @209.410400],
						 @[@"\U0001F63A", @331.199341],
						 @[@"council", @359.994507],
						 @[@"Board", @171.430664]];

	for (NSArray *sample in samples) {
		NSString *text = sample[0];
		CGFloat wanted = [sample[1] doubleValue];
		CGFloat got = angleOf([NSColor consistentColorForIdentifier:text onDarkBackground:NO]);

		/* Anderthalb Grad Spielraum: mehr gibt acht Bit je Farbkanal nicht her, der Farbkreis
		 * hat bei voller Saettigung rund 1,4 Grad je Stufe. Ein Rechenfehler laege um
		 * Groessenordnungen darueber, ein Farbraumfehler bei zwei bis vier Grad. */
		CGFloat apart = fabs(got - wanted);
		if (apart > 180.0) apart = 360.0 - apart;		//einmal um den Kreis herum

		check([NSString stringWithFormat:@"Der Winkel fuer %@ stimmt", text], apart < 1.5,
			  [NSString stringWithFormat:@"berechnet %.3f, erwartet %.3f", got, wanted]);
	}

	//Derselbe Name, zweimal gefragt, muss dasselbe liefern
	check(@"Dieselbe Eingabe gibt dieselbe Farbe",
		  [[NSColor consistentColorForIdentifier:@"Romeo" onDarkBackground:NO]
		   isEqualToString:[NSColor consistentColorForIdentifier:@"Romeo" onDarkBackground:NO]], nil);

	//Der Untergrund darf die Helligkeit aendern, den Farbton aber nicht
	check(@"Der Untergrund aendert den Farbton nicht",
		  fabs(angleOf([NSColor consistentColorForIdentifier:@"Romeo" onDarkBackground:YES]) -
			   angleOf([NSColor consistentColorForIdentifier:@"Romeo" onDarkBackground:NO])) < 1.5, nil);

	//Ein leerer Name darf nicht abstuerzen
	check(@"Ein leerer Name liefert trotzdem etwas",
		  [[NSColor consistentColorForIdentifier:@"" onDarkBackground:NO] length] > 0, nil);

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
