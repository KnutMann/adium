cmake_minimum_required(VERSION 3.16)
project(purple2-ircv3 C)

# The Makefile beside this covers Linux and mingw32. This covers macOS, where
# neither branch of it works: it passes -shared where a loadable module has to
# be built, hardcodes Macports include paths, and asks pkg-config for a
# libsasl2.pc that macOS does not ship.
#
# The plugin still has to be told which libpurple to build against, because a
# machine that builds its own does not have it in the default search path:
#
#   PKG_CONFIG_PATH=<prefix>/lib/pkgconfig cmake -B build -S .
#   cmake --build build

find_package(PkgConfig REQUIRED)
pkg_check_modules(Purple REQUIRED purple)
pkg_check_modules(GLIB REQUIRED glib-2.0)
pkg_check_modules(ZLIB REQUIRED zlib)

add_library(ircv3 MODULE
    cmds.c
    dcc_send.c
    irc.c
    msgs.c
    parse.c
)

# libpurple loads its protocols through GModule, and it looks for the name the
# other protocols carry rather than a platform default.
set_target_properties(ircv3 PROPERTIES
    PREFIX "lib"
    SUFFIX ".so"
)

target_compile_definitions(ircv3 PRIVATE
    ENABLE_NLS
    HAVE_CYRUS_SASL
    PACKAGE_VERSION="${PROJECT_VERSION}"
)

target_compile_options(ircv3 PRIVATE
    -Wall
    -Wno-deprecated-declarations
    -fno-strict-aliasing
)

target_include_directories(ircv3 SYSTEM PRIVATE
    ${Purple_INCLUDE_DIRS}
    ${GLIB_INCLUDE_DIRS}
)

if (Purple_LIBRARY_DIRS OR GLIB_LIBRARY_DIRS)
    target_link_directories(ircv3 PRIVATE
        ${Purple_LIBRARY_DIRS}
        ${GLIB_LIBRARY_DIRS}
    )
endif()

target_link_libraries(ircv3 PRIVATE
    ${Purple_LIBRARIES}
    ${GLIB_LIBRARIES}
    ${ZLIB_LIBRARIES}
    sasl2
)

# Where the plugin has to end up depends on the client, so this only says what
# libpurple itself reports and leaves the rest to the caller.
if (NOT DEFINED PURPLE_PLUGIN_DIR)
    pkg_get_variable(PURPLE_PLUGIN_DIR purple plugindir)
endif()

if (PURPLE_PLUGIN_DIR)
    install(TARGETS ircv3 DESTINATION "${PURPLE_PLUGIN_DIR}")
endif()
