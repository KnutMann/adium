/* Asks libpurple itself whether the protocol plugins in a directory actually
 * register a protocol.
 *
 * This exists because the failure it guards against is SILENT: a protocol
 * plug-in that links its own copy of libpurple (a build-tree path instead of
 * the bundle's framework) probes cleanly, loads cleanly, reports no error,
 * and registers its protocol in the copy nobody asks - libpurple's directory
 * scan then drops it without a line of log, and the user's first symptom is
 * an account that never connects. Static checks on the load commands catch
 * the known shapes of that mistake; this probe catches the mistake itself,
 * whatever shape it takes next time, by doing what the application does and
 * counting what arrives.
 *
 * Deliberately self-contained: no libpurple or glib headers, so it compiles
 * on a fresh checkout with nothing but Xcode's clang. The handful of
 * declarations below mirror the stable ABI of the libpurple 2.14 and glib
 * this repository pins and ships; they are the contract of the bundled
 * frameworks, not of whatever is installed on the machine.
 *
 * Usage: purple-plugin-probe <plugin-directory>
 * Prints the number of registered protocols and their ids, one per line, as
 * "prpl <id>". The caller compares against a baseline run over an empty
 * directory: every plugin file must add at least one.
 *
 * Link against the bundle's own libpurple and libglib binaries, and run it
 * from a MacOS/ directory beside a Frameworks/ that holds (or links to) the
 * bundle's frameworks, so that the @executable_path references in both the
 * frameworks and the plugins resolve exactly as they do inside Adium.
 */

typedef unsigned int guint;
typedef int gboolean;
typedef void *gpointer;
typedef gboolean (*GSourceFunc)(gpointer);

typedef struct _GList {
	void *data;
	struct _GList *next;
	struct _GList *prev;
} GList;

/* struct _PurpleEventLoopUiOps, libpurple 2.14 eventloop.h: six callbacks,
 * three reserved slots. Only the timeout family is ever exercised here. */
typedef struct {
	guint    (*timeout_add)(guint interval, GSourceFunc function, gpointer data);
	gboolean (*timeout_remove)(guint handle);
	guint    (*input_add)(int fd, int cond, void (*func)(gpointer, int, int), gpointer data);
	gboolean (*input_remove)(guint handle);
	int      (*input_get_error)(int fd, int *error);
	guint    (*timeout_add_seconds)(guint interval, GSourceFunc function, gpointer data);
	void     (*_purple_reserved2)(void);
	void     (*_purple_reserved3)(void);
	void     (*_purple_reserved4)(void);
} PurpleEventLoopUiOps;

extern void      purple_util_set_user_dir(const char *dir);
extern void      purple_debug_set_enabled(gboolean enabled);
extern void      purple_eventloop_set_ui_ops(PurpleEventLoopUiOps *ops);
extern gboolean  purple_core_init(const char *ui);
extern void      purple_plugins_add_search_path(const char *path);
extern void      purple_plugins_probe(const char *ext);
extern GList    *purple_plugins_get_protocols(void);
extern const char *purple_plugin_get_id(void *plugin);

extern guint     g_timeout_add(guint interval, GSourceFunc function, gpointer data);
extern gboolean  g_source_remove(guint handle);
extern guint     g_timeout_add_seconds(guint interval, GSourceFunc function, gpointer data);

extern int  printf(const char *format, ...);
extern int  mkdir(const char *path, unsigned short mode);

static guint probe_input_add(int fd, int cond, void (*func)(gpointer, int, int), gpointer data)
{
	return 0;
}

static PurpleEventLoopUiOps eventloop = {
	g_timeout_add,
	g_source_remove,
	probe_input_add,
	g_source_remove,
	0,
	g_timeout_add_seconds,
	0, 0, 0,
};

int main(int argc, char **argv)
{
	if (argc < 2) {
		printf("usage: purple-plugin-probe <plugin-directory>\n");
		return 2;
	}

	/* A scratch home, so the probe neither reads nor touches any real profile */
	mkdir("/tmp/purple-plugin-probe-home", 0700);
	purple_util_set_user_dir("/tmp/purple-plugin-probe-home");
	purple_debug_set_enabled(0);
	purple_eventloop_set_ui_ops(&eventloop);
	purple_plugins_add_search_path(argv[1]);

	if (!purple_core_init("plugin-probe")) {
		printf("purple_core_init failed\n");
		return 2;
	}

	purple_plugins_probe("so");

	int count = 0;
	for (GList *l = purple_plugins_get_protocols(); l; l = l->next) {
		printf("prpl %s\n", purple_plugin_get_id(l->data));
		count++;
	}
	printf("protocols %d\n", count);

	return 0;
}
