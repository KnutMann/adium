/* config.h.  Generated from config.h.in by configure.  */
/* config.h.in.  Generated from configure.ac by autoheader.  */

/* Define if building universal (internal helper macro) */
/* #undef AC_APPLE_UNIVERSAL_BUILD */

/* configure arguments */
#define CONFIG_ARGS " '--disable-dependency-tracking' '--disable-gtkui' '--disable-consoleui' '--disable-perl' '--enable-debug' '--disable-static' '--enable-shared' '--enable-cyrus-sasl' '--prefix=/Users/chrimuel/Documents/Code/privat/AI/adium/Dependencies/build' '--with-static-prpls=bonjour,gg,irc,jabber,novell,simple,zephyr' '--disable-meanwhile' '--disable-plugins' '--disable-avahi' '--disable-dbus' '--enable-gnutls=no' '--enable-nss=no' '--enable-vv=no' '--disable-gstreamer' '--disable-idn' 'CC=/Applications/Xcode.app/Contents/Developer/usr/bin/gcc' 'CFLAGS=-I/Users/chrimuel/Documents/Code/privat/AI/adium/Dependencies/build/include -L/Users/chrimuel/Documents/Code/privat/AI/adium/Dependencies/build/lib -I/usr/include/kerberosIV -DHAVE_SSL 			        -DHAVE_OPENSSL -fno-common -DHAVE_ZLIB' 'LDFLAGS=-Wl,-headerpad_max_install_names 				-I/Users/chrimuel/Documents/Code/privat/AI/adium/Dependencies/build/include -L/Users/chrimuel/Documents/Code/privat/AI/adium/Dependencies/build/lib -lsasl2 -ljson-glib-1.0 -lz' 'LIBXML_CFLAGS=-I/usr/include/libxml2' 'LIBXML_LIBS=-lxml2'"

/* Define to 1 if using 'alloca.c'. */
/* #undef C_ALLOCA */

/* Define if debugging is enabled. */
#define DEBUG 1

/* display version info */
#define DISPLAY_VERSION "2.14.14"

/* Define if mono enabled. */
/* #undef ENABLE_MONO */

/* always defined to indicate that i18n is enabled */
/* #undef ENABLE_NLS */

/* use the given file as GnuTLS default trust store */
#define GG_CONFIG_GNUTLS_SYSTEM_TRUST_STORE "/etc/ssl/cert.pem"

/* Define to 1 if you have 'alloca', as a function or macro. */
#define HAVE_ALLOCA 1

/* Define to 1 if <alloca.h> works. */
#define HAVE_ALLOCA_H 1

/* Define if you have the external 'altzone' variable. */
/* #undef HAVE_ALTZONE */

/* Define to 1 if you have the <arpa/nameser_compat.h> header file. */
#define HAVE_ARPA_NAMESER_COMPAT_H 1

/* Define to 1 if you have the 'atexit' function. */
#define HAVE_ATEXIT 1

/* Define to 1 if you have the 'bind_textdomain_codeset' function. */
/* #undef HAVE_BIND_TEXTDOMAIN_CODESET */

/* Define to 1 if you have the Mac OS X function CFLocaleCopyCurrent in the
   CoreFoundation framework. */
#define HAVE_CFLOCALECOPYCURRENT 1

/* Define to 1 if you have the Mac OS X function CFPreferencesCopyAppValue in
   the CoreFoundation framework. */
#define HAVE_CFPREFERENCESCOPYAPPVALUE 1

/* Define to 1 if you have the 'connect' function. */
#define HAVE_CONNECT 1

/* Define to 1 if Cyrus SASL is present */
#define HAVE_CYRUS_SASL 1

/* Define if you have the external 'daylight' variable. */
#define HAVE_DAYLIGHT 1

/* Define if we are using D-Bus. */
/* #undef HAVE_DBUS */

/* Define to 1 if you have the 'dcgettext' function. */
/* #undef HAVE_DCGETTEXT */

/* Define to 1 if you have the declaration of 'tzname', and to 0 if you don't.
   */
/* #undef HAVE_DECL_TZNAME */

/* Define to 1 if you have the <dlfcn.h> header file. */
#define HAVE_DLFCN_H 1

/* whether or not we have dot */
/* #undef HAVE_DOT */

/* whether or not we have doxygen */
/* #undef HAVE_DOXYGEN */

/* Define if we're using evolution addressbook. */
/* #undef HAVE_EVOLUTION_ADDRESSBOOK */

/* Define to 1 if you have the <EXTERN.h> header file. */
/* #undef HAVE_EXTERN_H */

/* Use Farsight instead of Farstream */
/* #undef HAVE_FARSIGHT */

/* Define to 1 if you have the <fcntl.h> header file. */
#define HAVE_FCNTL_H 1

/* Define to 1 if your stdio has int fileno(FILE *). */
#define HAVE_FILENO 1

/* Define to 1 if you have the getaddrinfo function. */
#define HAVE_GETADDRINFO 1

/* Define to 1 if you have the 'gethostid' function. */
#define HAVE_GETHOSTID 1

/* Define to 1 if you have the 'getifaddrs' function. */
#define HAVE_GETIFADDRS 1

/* Define to 1 if you have the 'getopt_long' function. */
#define HAVE_GETOPT_LONG 1

/* Define if the GNU gettext() function is already present or preinstalled. */
/* #undef HAVE_GETTEXT */

/* Have gio-unix */
#define HAVE_GIOUNIX 1

/* Define if you have GnuTLS */
/* #undef HAVE_GNUTLS */

/* Defined if GnuTLS >= 2.10.0 is available. */
/* #undef HAVE_GNUTLS_2_10 */

/* gnutls contains the gnutls_certificate_set_x509_system_trust function */
/* #undef HAVE_GNUTLS_CERTIFICATE_SET_X509_SYSTEM_TRUST */

/* Define if your gnutls has the GNUTLS_CERT_INSECURE_ALGORITHM flag */
/* #undef HAVE_GNUTLS_CERT_INSECURE_ALGORITHM */

/* Define to 1 if you have the <gnutls/gnutls.h> header file. */
/* #undef HAVE_GNUTLS_GNUTLS_H */

/* Define if your gnutls has gnutls_priority_set_direct and friends */
/* #undef HAVE_GNUTLS_PRIORITY_FUNCS */

/* Define to 1 if you have the 'inet_ntop' function. */
#define HAVE_INET_NTOP 1

/* Define to 1 if you have the <inttypes.h> header file. */
#define HAVE_INTTYPES_H 1

/* Define if we have IOKit */
#define HAVE_IOKIT 1

/* Define if the IPV6_V6ONLY setsockopt option exists */
#define HAVE_IPV6_V6ONLY 1

/* Define to 1 if you have the 'krb_get_err_text' function. */
/* #undef HAVE_KRB_GET_ERR_TEXT */

/* Define to 1 if you have the 'krb_get_lrealm' function. */
/* #undef HAVE_KRB_GET_LREALM */

/* Define to 1 if you have the 'krb_log' function. */
/* #undef HAVE_KRB_LOG */

/* Define to 1 if you have the 'krb_rd_req' function. */
/* #undef HAVE_KRB_RD_REQ */

/* Define to 1 if you have the 'krb_set_key' function. */
/* #undef HAVE_KRB_SET_KEY */

/* Define if your <locale.h> file defines LC_MESSAGES. */
#define HAVE_LC_MESSAGES 1

/* Linked with external libgadu */
/* #undef HAVE_LIBGADU */

/* Define to 1 if you have the 'nsl' library (-lnsl). */
/* #undef HAVE_LIBNSL */

/* Define to 1 if you have the 'resolv' library (-lresolv). */
#define HAVE_LIBRESOLV 1

/* Define to 1 if you have the 'socket' library (-lsocket). */
/* #undef HAVE_LIBSOCKET */

/* Define to 1 if you have the <locale.h> header file. */
#define HAVE_LOCALE_H 1

/* Define to 1 if you have the 'lrand48' function. */
#define HAVE_LRAND48 1

/* Define to 1 if you have the <malloc.h> header file. */
/* #undef HAVE_MALLOC_H */

/* Define if we have support for application media type. */
/* #undef HAVE_MEDIA_APPLICATION */

/* Define to 1 if you have the 'memcpy' function. */
#define HAVE_MEMCPY 1

/* Define to 1 if you have the 'memmove' function. */
#define HAVE_MEMMOVE 1

/* Define to 1 if you have the 'mono_jit_init' function. */
/* #undef HAVE_MONO_JIT_INIT */

/* Define to 1 if you have the <mono/jit/jit.h> header file. */
/* #undef HAVE_MONO_JIT_JIT_H */

/* Define to 1 if you have the <mono/metadata/object.h> header file. */
/* #undef HAVE_MONO_METADATA_OBJECT_H */

/* Define if we have NetworkManager. */
/* #undef HAVE_NETWORKMANAGER */

/* Define to 1 if you have the <nspr.h> header file. */
/* #undef HAVE_NSPR_H */

/* Define if you have Mozilla NSS */
/* #undef HAVE_NSS */

/* Define to 1 if you have the <nss.h> header file. */
/* #undef HAVE_NSS_H */

/* Define if we have Pango 1.4 or newer. */
/* #undef HAVE_PANGO14 */

/* Define to 1 if you have the <paths.h> header file. */
#define HAVE_PATHS_H 1

/* Compile with support for perl */
/* #undef HAVE_PERL */

/* Define to 1 if you have the 'Perl_eval_pv' function. */
/* #undef HAVE_PERL_EVAL_PV */

/* Define to 1 if you have the <perl.h> header file. */
/* #undef HAVE_PERL_H */

/* Define to 1 if you have the 'perl_run' function. */
/* #undef HAVE_PERL_RUN */

/* Define to 1 if you have the <prio.h> header file. */
/* #undef HAVE_PRIO_H */

/* Define to 1 if you have the 'random' function. */
#define HAVE_RANDOM 1

/* Define to 1 if you have the <regex.h> header file. */
#define HAVE_REGEX_H 1

/* Define to 1 if you have the 'setlocale' function. */
#define HAVE_SETLOCALE 1

/* Define to 1 if you have the <sgtty.h> header file. */
#define HAVE_SGTTY_H 1

/* Define to 1 if you have the <signal.h> header file. */
#define HAVE_SIGNAL_H 1

/* Define if we have silcmime.h */
/* #undef HAVE_SILCMIME_H */

/* Define to 1 if you have the <smime.h> header file. */
/* #undef HAVE_SMIME_H */

/* Define to 1 if you have the 'snprintf' function. */
#define HAVE_SNPRINTF 1

/* Define if you have SSL */
/* #undef HAVE_SSL */

/* Define to 1 if you have the <ssl.h> header file. */
/* #undef HAVE_SSL_H */

/* Define to 1 if you have the <stdarg.h> header file. */
#define HAVE_STDARG_H 1

/* Define to 1 if you have the <stdint.h> header file. */
#define HAVE_STDINT_H 1

/* Define to 1 if you have the <stdio.h> header file. */
#define HAVE_STDIO_H 1

/* Define to 1 if you have the <stdlib.h> header file. */
#define HAVE_STDLIB_H 1

/* Define to 1 if you have the 'strchr' function. */
#define HAVE_STRCHR 1

/* Define to 1 if you have the 'strdup' function. */
#define HAVE_STRDUP 1

/* Define to 1 if you have the 'strerror' function. */
#define HAVE_STRERROR 1

/* Define to 1 if you have the 'strftime' function. */
#define HAVE_STRFTIME 1

/* Define to 1 if you have a strftime() that supports the %z format string. */
#define HAVE_STRFTIME_Z_FORMAT 1

/* Define to 1 if you have the <strings.h> header file. */
#define HAVE_STRINGS_H 1

/* Define to 1 if you have the <string.h> header file. */
#define HAVE_STRING_H 1

/* Define to 1 if you have the 'strstr' function. */
#define HAVE_STRSTR 1

/* Define if struct sockaddr has an sa_len member */
#define HAVE_STRUCT_SOCKADDR_SA_LEN 1

/* Define to 1 if 'tm_zone' is a member of 'struct tm'. */
#define HAVE_STRUCT_TM_TM_ZONE 1

/* Define to 1 if you have the <sys/cdefs.h> header file. */
#define HAVE_SYS_CDEFS_H 1

/* Define to 1 if you have the <sys/file.h> header file. */
#define HAVE_SYS_FILE_H 1

/* Define to 1 if you have the <sys/filio.h> header file. */
#define HAVE_SYS_FILIO_H 1

/* Define to 1 if you have the <sys/ioctl.h> header file. */
#define HAVE_SYS_IOCTL_H 1

/* Define to 1 if you have the <sys/msgbuf.h> header file. */
#define HAVE_SYS_MSGBUF_H 1

/* Define to 1 if you have the <sys/param.h> header file. */
#define HAVE_SYS_PARAM_H 1

/* Define to 1 if you have the <sys/select.h> header file. */
#define HAVE_SYS_SELECT_H 1

/* Define to 1 if you have the <sys/socket.h> header file. */
#define HAVE_SYS_SOCKET_H 1

/* Define to 1 if you have the <sys/stat.h> header file. */
#define HAVE_SYS_STAT_H 1

/* Define to 1 if you have the <sys/sysctl.h> header file. */
#define HAVE_SYS_SYSCTL_H 1

/* Define to 1 if you have the <sys/time.h> header file. */
#define HAVE_SYS_TIME_H 1

/* Define to 1 if you have the <sys/types.h> header file. */
#define HAVE_SYS_TYPES_H 1

/* Define to 1 if you have the <sys/uio.h> header file. */
#define HAVE_SYS_UIO_H 1

/* Define to 1 if you have the <sys/utsname.h> header file. */
#define HAVE_SYS_UTSNAME_H 1

/* Define to 1 if you have the <sys/wait.h> header file. */
#define HAVE_SYS_WAIT_H 1

/* Compile with support for the Tcl toolkit */
/* #undef HAVE_TCL */

/* Define to 1 if you have the <termios.h> header file. */
#define HAVE_TERMIOS_H 1

/* Define to 1 if you have the 'timegm' function. */
#define HAVE_TIMEGM 1

/* Define if you have the external 'timezone' variable. */
#define HAVE_TIMEZONE 1

/* Compile with support for the Tk toolkit */
/* #undef HAVE_TK */

/* Define if you have a tm_gmtoff member in struct tm */
#define HAVE_TM_GMTOFF 1

/* Define to 1 if your 'struct tm' has 'tm_zone'. Deprecated, use
   'HAVE_STRUCT_TM_TM_ZONE' instead. */
#define HAVE_TM_ZONE 1

/* Define to 1 if you don't have 'tm_zone' but do have the external array
   'tzname'. */
/* #undef HAVE_TZNAME */

/* Define to 1 if you have the <unistd.h> header file. */
#define HAVE_UNISTD_H 1

/* Define to 1 if you have the 'vprintf' function. */
#define HAVE_VPRINTF 1

/* Define to 1 if you have X11 */
/* #undef HAVE_X11 */

/* Define to 1 if you have the <X11/SM/SMlib.h> header file. */
/* #undef HAVE_X11_SM_SMLIB_H */

/* whether or not we have xsltproc for devhelp index */
/* #undef HAVE_XSLTPROC */

/* Define if external libzephyr should be used. */
/* #undef LIBZEPHYR_EXT */

/* Define to the sub-directory where libtool stores uninstalled libraries. */
#define LT_OBJDIR ".libs/"

/* Define to 1 if you don't have wide-character support. */
/* #undef NO_WIDECHAR */

/* Define if old perl is installed. */
/* #undef OLD_PERL */

/* Name of package */
#define PACKAGE "pidgin"

/* Define to the address where bug reports for this package should be sent. */
#define PACKAGE_BUGREPORT "devel@pidgin.im"

/* Define to the full name of this package. */
#define PACKAGE_NAME "pidgin"

/* Define to the full name and version of this package. */
#define PACKAGE_STRING "pidgin 2.14.14"

/* Define to the one symbol short name of this package. */
#define PACKAGE_TARNAME "pidgin"

/* Define to the home page for this package. */
#define PACKAGE_URL ""

/* Define to the version of this package. */
#define PACKAGE_VERSION "2.14.14"

/* Define if plugins are enabled. */
/* #undef PURPLE_PLUGINS */

/* Define as the return type of signal handlers ('int' or 'void'). */
#define RETSIGTYPE void

/* The size of 'time_t', as computed by sizeof. */
#define SIZEOF_TIME_T 8

/* If using the C implementation of alloca, define if you know the
   direction of stack growth for your system; otherwise it will be
   automatically deduced at runtime.
	STACK_DIRECTION > 0 => grows toward higher addresses
	STACK_DIRECTION < 0 => grows toward lower addresses
	STACK_DIRECTION = 0 => direction of growth unknown */
/* #undef STACK_DIRECTION */

/* Loads static protocol plugin module initialization functions. */
#define STATIC_PROTO_INIT extern gboolean purple_init_gg_plugin(); extern gboolean purple_init_irc_plugin(); extern gboolean purple_init_jabber_plugin(); extern gboolean purple_init_novell_plugin(); extern gboolean purple_init_simple_plugin(); extern gboolean purple_init_zephyr_plugin(); static void static_proto_init(void) {  purple_init_gg_plugin(); purple_init_irc_plugin(); purple_init_jabber_plugin(); purple_init_novell_plugin(); purple_init_simple_plugin(); purple_init_zephyr_plugin(); }

/* Define to 1 if all of the C89 standard headers exist (not just the ones
   required in a freestanding environment). This macro is provided for
   backward compatibility; new code need not use it. */
#define STDC_HEADERS 1

/* Define to 1 if your <sys/time.h> declares 'struct tm'. */
/* #undef TM_IN_SYS_TIME */

/* Use GStreamer Video Overlay support */
/* #undef USE_GSTAPP */

/* Use GStreamer 0.10 interfaces for X overlay support */
/* #undef USE_GSTINTERFACES */

/* Use GStreamer 0.10 for playing sounds */
/* #undef USE_GSTREAMER */

/* Use GStreamer Video Overlay support */
/* #undef USE_GSTVIDEO */

/* Define if we're using GtkSpell */
/* #undef USE_GTKSPELL */

/* Use GNU Libidn for stringprep and IDN */
/* #undef USE_IDN */

/* Define if we're using XScreenSaver. */
/* #undef USE_SCREENSAVER */

/* Define if we're using X Session Management. */
/* #undef USE_SM */

/* Use voice and video */
/* #undef USE_VV */

/* 'va_lists' cannot be copied as values */
/* #undef VA_COPY_AS_ARRAY */

/* Version number of package */
#define VERSION "2.14.14"

/* Define WORDS_BIGENDIAN to 1 if your processor stores words with the most
   significant byte first (like Motorola and SPARC, unlike Intel). */
#if defined AC_APPLE_UNIVERSAL_BUILD
# if defined __BIG_ENDIAN__
#  define WORDS_BIGENDIAN 1
# endif
#else
# ifndef WORDS_BIGENDIAN
/* #  undef WORDS_BIGENDIAN */
# endif
#endif

/* Define to 1 if the X Window System is missing or not being used. */
#define X_DISPLAY_MISSING 1

/* Size of an int32. */
#define ZEPHYR_INT32 long

/* Define if kerberos should be used in Zephyr. */
/* #undef ZEPHYR_USES_KERBEROS */

/* Number of bits in a file offset, on hosts where this is settable. */
/* #undef _FILE_OFFSET_BITS */

/* Define to 1 on platforms where this makes off_t a 64-bit type. */
/* #undef _LARGE_FILES */

/* Number of bits in time_t, on hosts where this is settable. */
/* #undef _TIME_BITS */

/* Define to 1 on platforms where this makes time_t a 64-bit type. */
/* #undef __MINGW_USE_VC2005_COMPAT */

/* Define to empty if 'const' does not conform to ANSI C. */
/* #undef const */

/* Define as 'unsigned int' if <stddef.h> doesn't define. */
/* #undef size_t */

/* socklen_t size */
/* #undef socklen_t */
