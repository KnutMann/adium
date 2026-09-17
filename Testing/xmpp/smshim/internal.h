/* A stand-in for libpurple's internal.h, which is not shipped in the framework.
 *
 * stream_management.c wants exactly two things from it: the gettext macro and the ordinary C
 * headers. Everything else it needs comes from libpurple's public headers, which are shipped.
 * Keeping this here rather than vendoring the real internal.h means the test cannot quietly
 * start depending on private libpurple behaviour. */
#ifndef ADIUM_TEST_INTERNAL_H
#define ADIUM_TEST_INTERNAL_H

#include <glib.h>
#include <stdlib.h>
#include <string.h>

#define _(String) (String)
#define N_(String) (String)

#endif
