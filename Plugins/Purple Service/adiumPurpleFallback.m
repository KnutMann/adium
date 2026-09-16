/*
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 *
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import "adiumPurpleFallback.h"

/*
 * Fallback Indication (XEP-0428) for the jabber protocol.
 *
 * A modern client that says something our protocol cannot express writes it twice: once
 * properly, in an element we may or may not understand, and once as plain words in the body
 * so that nobody is left staring at an empty message. It then marks which part of the body
 * was only meant for that second case.
 *
 * Adium already honoured one single form of this, the one a reaction uses, where the whole
 * body stands in for the reaction and is therefore dropped. A REPLY marks something else:
 * it quotes the message it answers as a run of lines beginning with an angle bracket, names
 * the exact stretch of characters that quote occupies, and expects a client that shows the
 * quote properly to leave that stretch out. We do not show it properly yet, but we were also
 * not leaving it out, so every reply from Gajim, monocles or Kaidan arrived with its quoted
 * text spelled out in front of it. That is the visible half of the bug, and the cheap half
 * to fix.
 *
 * So: a fallback that names a stretch of the body has that stretch cut out here, before the
 * protocol ever sees the message. A fallback that names no stretch is left entirely alone,
 * which is what keeps the reaction behaviour exactly as it was.
 *
 * The offsets count characters, not bytes, which for anybody writing in a language with
 * umlauts or an emoji in the quote is the difference between a clean cut and a mangled one.
 */

#define NS_FALLBACK		"urn:xmpp:fallback:0"

static int adium_purple_fallback_handle;

/*! @brief One stretch of the body that was only ever there as a stand-in */
typedef struct {
	long start;
	long end;
} AdiumFallbackRange;

/*!
 * @brief Every stretch the sender marked, latest first
 *
 * Cutting from the back keeps the earlier offsets true, so the caller can simply walk the
 * list. Ranges that make no sense are dropped rather than clamped: a sender who cannot count
 * has not told us anything we should act on.
 */
static GArray *rangesMarkedIn(xmlnode *message, long length)
{
	GArray *ranges = g_array_new(FALSE, FALSE, sizeof(AdiumFallbackRange));

	for (xmlnode *fallback = xmlnode_get_child_with_namespace(message, "fallback", NS_FALLBACK);
		 fallback; fallback = xmlnode_get_next_twin(fallback)) {
		for (xmlnode *part = xmlnode_get_child(fallback, "body"); part;
			 part = xmlnode_get_next_twin(part)) {
			const char *from = xmlnode_get_attrib(part, "start");
			const char *to = xmlnode_get_attrib(part, "end");
			if (!from || !to)
				continue;			//no stretch named; the whole body, and not ours to touch

			AdiumFallbackRange range = { atol(from), atol(to) };
			if (range.start < 0 || range.end > length || range.start >= range.end)
				continue;

			g_array_append_val(ranges, range);
		}
	}

	//Back to front, so that cutting one does not move the next
	for (guint outer = 0; outer + 1 < ranges->len; outer++)
		for (guint inner = 0; inner + 1 < ranges->len - outer; inner++) {
			AdiumFallbackRange *one = &g_array_index(ranges, AdiumFallbackRange, inner);
			AdiumFallbackRange *two = &g_array_index(ranges, AdiumFallbackRange, inner + 1);
			if (one->start < two->start) {
				AdiumFallbackRange swap = *one; *one = *two; *two = swap;
			}
		}

	return ranges;
}

/*! @brief The text with those stretches taken out */
static char *textWithout(const char *text, GArray *ranges)
{
	GString *left = g_string_new(text);

	for (guint index = 0; index < ranges->len; index++) {
		AdiumFallbackRange range = g_array_index(ranges, AdiumFallbackRange, index);
		const char *from = g_utf8_offset_to_pointer(left->str, range.start);
		const char *to = g_utf8_offset_to_pointer(left->str, range.end);
		if (!from || !to || to < from)
			continue;

		g_string_erase(left, from - left->str, to - from);
	}

	return g_string_free(left, FALSE);
}

/*!
 * @brief Put the shortened text back where the old one was
 *
 * The body's words live in one or more data children next to its attributes. The first of
 * them takes the whole new text and the rest are emptied, which leaves every attribute,
 * every namespace and the order of everything else exactly as it was. Building a fresh
 * element instead would mean copying all of that by hand and getting xml:lang wrong.
 */
static void putBodyText(xmlnode *body, const char *text)
{
	gboolean written = FALSE;

	for (xmlnode *part = body->child; part; part = part->next) {
		if (part->type != XMLNODE_TYPE_DATA)
			continue;

		g_free(part->data);
		part->data = g_strdup(written ? "" : text);
		part->data_sz = strlen(part->data);
		written = TRUE;
	}

	if (!written)
		xmlnode_insert_data(body, text, -1);
}

static void fallback_receiving_xmlnode_cb(PurpleConnection *gc, xmlnode **packet, gpointer data)
{
	if (!packet || !*packet || strcmp((*packet)->name, "message"))
		return;

	xmlnode *body = xmlnode_get_child(*packet, "body");
	if (!body)
		return;

	char *text = xmlnode_get_data(body);
	if (!text)
		return;

	GArray *ranges = rangesMarkedIn(*packet, g_utf8_strlen(text, -1));
	if (!ranges->len) {
		g_array_free(ranges, TRUE);
		g_free(text);
		return;
	}

	/* The stanza is changed in place rather than replaced: every other handler on this
	 * signal, ours and the protocol's own, keeps the pointer it was given. */
	char *shortened = textWithout(text, ranges);
	putBodyText(body, shortened);

	purple_debug_info("fallback", "took %u marked stretch(es) out of a message body\n", ranges->len);

	g_free(shortened);
	g_free(text);
	g_array_free(ranges, TRUE);
}

void configureAdiumPurpleFallback(void)
{
	PurplePlugin *jabber = purple_find_prpl("prpl-jabber");
	if (!jabber)
		return;

	/* Before anything that reads the body, and the protocol's own reader runs last of all */
	purple_signal_connect_priority(jabber, "jabber-receiving-xmlnode", &adium_purple_fallback_handle,
								   PURPLE_CALLBACK(fallback_receiving_xmlnode_cb), NULL,
								   PURPLE_SIGNAL_PRIORITY_HIGHEST);
}
