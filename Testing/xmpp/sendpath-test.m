/* Does a stanza survive the detour through text that the counted send path makes necessary?
 *
 * Four places in Adium used to hand their stanzas straight to send_raw and thereby went around
 * the counter for XEP-0198: the server counts them, we do not, and the two numbers drift apart
 * for the rest of the connection. Two of those places hold finished TEXT and not a tree, so they
 * have to be parsed back in first for the counter to see them.
 *
 * That is exactly what is checked here: that nothing is lost on the way. A swallowed namespace
 * or a lost attribute would otherwise only be noticed by the other side, and even there only as
 * an answer that never comes.
 */
#import <Foundation/Foundation.h>
#import <libpurple/libpurple.h>

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

/*! @brief Parse in and write back out, the way the counted path does */
static NSString *throughTheParser(NSString *written)
{
	xmlnode *parsed = xmlnode_from_str([written UTF8String], -1);
	if (!parsed) return nil;

	char *again = xmlnode_to_str(parsed, NULL);
	NSString *result = again ? [NSString stringWithUTF8String:again] : nil;
	if (again) g_free(again);
	xmlnode_free(parsed);
	return result;
}

static void survives(NSString *name, NSString *written, NSArray<NSString *> *mustContain)
{
	NSString *after = throughTheParser(written);
	if (!after) {
		check(name, NO, @"could not be parsed at all");
		return;
	}

	for (NSString *needed in mustContain) {
		if ([after rangeOfString:needed].location == NSNotFound) {
			check(name, NO, [NSString stringWithFormat:@"\"%@\" is missing from %@", needed, after]);
			return;
		}
	}
	check(name, YES, nil);
}

int main(void) { @autoreleasepool {
	//What AMPurpleJabberNode sends while exploring, with the namespace on the query element
	survives(@"A discovery request keeps its namespace",
			 @"<iq type=\"get\" to=\"conference.example.org\" id=\"AMPurpleJabberNode1\">"
			  "<query xmlns=\"http://jabber.org/protocol/disco#items\"></query></iq>",
			 @[@"disco#items", @"conference.example.org", @"AMPurpleJabberNode1", @"type='get'"]);

	survives(@"And so does one asking about features",
			 @"<iq type=\"get\" to=\"example.org\" id=\"n2\">"
			  "<query xmlns=\"http://jabber.org/protocol/disco#info\" node=\"urn:x\"></query></iq>",
			 @[@"disco#info", @"node='urn:x'", @"id='n2'"]);

	//What the ad hoc server answers: nested, with a form
	survives(@"An ad hoc answer keeps its nesting",
			 @"<iq to=\"a@b/c\" type=\"result\" id=\"x1\">"
			  "<command xmlns=\"http://jabber.org/protocol/commands\" node=\"ping\" status=\"completed\">"
			  "<x xmlns=\"jabber:x:data\" type=\"result\">"
			  "<field var=\"beat\"><value>1</value></field></x></command></iq>",
			 @[@"protocol/commands", @"node='ping'", @"jabber:x:data", @"<value>1</value>"]);

	//What the file upload asks
	survives(@"An upload request keeps size and name",
			 @"<iq type=\"get\" to=\"upload.example.org\" id=\"u1\">"
			  "<request xmlns=\"urn:xmpp:http:upload:0\" filename=\"Picture ä.png\" size=\"4711\"/></iq>",
			 @[@"upload:0", @"Picture ä.png", @"size='4711'"]);

	//Accents and special characters in the text
	survives(@"A body with accented letters comes through intact",
			 @"<message to=\"x@y\" type=\"chat\"><body>Crème &amp; naïveté &lt;3</body></message>",
			 @[@"Crème", @"&amp;", @"&lt;3"]);

	//And the case that must NOT go through: broken XML has to come back as nil, so that the
	//caller passes it on unchanged rather than losing it in silence
	check(@"Incomplete XML cannot be parsed",
		  throughTheParser(@"<iq type='get'><query") == nil, nil);
	check(@"Nor can a bare fragment",
		  throughTheParser(@"</stream:stream>") == nil, nil);

	//A single element with no content, by contrast, is valid and has to go through
	check(@"An empty element goes through", throughTheParser(@"<presence/>") != nil, nil);

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
} }
