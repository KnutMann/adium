/**
 * @file glibcompat.h Compatibility for many glib versions.
 * @ingroup core
 */

/* purple
 *
 * Purple is the legal property of its developers, whose names are too numerous
 * to list here.  Please refer to the COPYRIGHT file distributed with this
 * source distribution.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02111-1301 USA
 */

#ifndef PURPLE_GLIBCOMPAT_H
#define PURPLE_GLIBCOMPAT_H

#include <string.h>

#include <glib.h>

#if !GLIB_CHECK_VERSION(2,28,0)
static inline void
g_list_free_full(GList *l, GDestroyNotify free_func) {
	GList *ll = NULL;

	for(ll = l; ll != NULL; ll = ll->next) {
		free_func(ll->data);
	}

	g_list_free(l);
}

static inline void
g_slist_free_full(GSList *l, GDestroyNotify free_func) {
	GSList *ll = NULL;

	for(ll = l; ll != NULL; ll = ll->next) {
		free_func(ll->data);
	}

	g_slist_free(l);
}
#endif /* !GLIB_CHECK_VERSION(2,23,0) */

#if !GLIB_CHECK_VERSION(2,32,0)
# define G_GNUC_BEGIN_IGNORE_DEPRECATIONS
# define G_GNUC_END_IGNORE_DEPRECATIONS

static inline void
g_queue_free_full(GQueue *queue, GDestroyNotify free_func) {
	GList *l = NULL;

	for(l = queue->head; l != NULL; l = l->next) {
		free_func(l->data);
	}

	g_queue_free(queue);
}

static inline gboolean
g_hash_table_contains(GHashTable *hash_table, gconstpointer key) {
	return g_hash_table_lookup_extended(hash_table, key, NULL, NULL);
}

#endif /* !GLIB_CHECK_VERSION(2,32,0) */

#ifdef __clang__

#undef G_GNUC_BEGIN_IGNORE_DEPRECATIONS
#define G_GNUC_BEGIN_IGNORE_DEPRECATIONS \
	_Pragma ("clang diagnostic push") \
	_Pragma ("clang diagnostic ignored \"-Wdeprecated-declarations\"")

#undef G_GNUC_END_IGNORE_DEPRECATIONS
#define G_GNUC_END_IGNORE_DEPRECATIONS \
	_Pragma ("clang diagnostic pop")

#endif /* __clang__ */

/* Backport the static inline version of g_memdup2 if we don't have g_memdup2.
 * see https://mail.gnome.org/archives/desktop-devel-list/2021-February/msg00000.html
 * for more information.
 */
#if !GLIB_CHECK_VERSION(2, 67, 3)
static inline gpointer
g_memdup2(gconstpointer mem, gsize byte_size) {
	gpointer new_mem = NULL;

	if(mem && byte_size != 0) {
		new_mem = g_malloc (byte_size);
		memcpy (new_mem, mem, byte_size);
	}

	return new_mem;
}
#endif /* !GLIB_CHECK_VERSION(2, 67, 3) */

#endif /* PURPLE_GLIBCOMPAT_H */

