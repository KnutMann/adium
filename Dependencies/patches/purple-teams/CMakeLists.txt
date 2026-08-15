cmake_minimum_required(VERSION 3.16)
project(purple-teams C)

# The Makefile beside this covers Linux and mingw32. Its Darwin branch does not
# build here: it passes -shared where a loadable module has to be built, sets
# CC to gcc, and hardcodes Macports include paths.
#
# The plugin still has to be told which libpurple to build against, because a
# machine that builds its own does not have it in the default search path:
#
#   PKG_CONFIG_PATH=<prefix>/lib/pkgconfig cmake -B build -S .
#   cmake --build build

find_package(PkgConfig REQUIRED)
pkg_check_modules(Purple REQUIRED purple)
pkg_check_modules(GLIB REQUIRED glib-2.0)
pkg_check_modules(JSONGLIB REQUIRED json-glib-1.0)

set(TEAMS_SOURCES
    libteams.c
    teams_connection.c
    teams_contacts.c
    teams_login.c
    teams_messages.c
    teams_util.c
    teams_trouter.c
    teams_cards.c
    purple-websocket.c
    markdown.c
    purple2compat/http.c
    purple2compat/purple-socket.c
)

# The same sources build two protocols: work and school accounts against
# teams.microsoft.com, and personal ones against teams.live.com. They are
# separate protocol ids and can be used side by side.
function(add_teams_protocol target)
    add_library(${target} MODULE ${TEAMS_SOURCES})

    # libpurple loads its protocols through GModule, and it looks for the name
    # the other protocols carry rather than a platform default.
    set_target_properties(${target} PROPERTIES
        PREFIX "lib"
        SUFFIX ".so"
    )

    target_compile_definitions(${target} PRIVATE
        ENABLE_NLS
        PACKAGE_VERSION="${PROJECT_VERSION}"
        ${ARGN}
    )

    target_compile_options(${target} PRIVATE
        -Wall
        -Wno-deprecated-declarations
        -fno-strict-aliasing
    )

    target_include_directories(${target} SYSTEM PRIVATE
        purple2compat
        ${Purple_INCLUDE_DIRS}
        ${GLIB_INCLUDE_DIRS}
        ${JSONGLIB_INCLUDE_DIRS}
    )

    if (Purple_LIBRARY_DIRS OR GLIB_LIBRARY_DIRS OR JSONGLIB_LIBRARY_DIRS)
        target_link_directories(${target} PRIVATE
            ${Purple_LIBRARY_DIRS}
            ${GLIB_LIBRARY_DIRS}
            ${JSONGLIB_LIBRARY_DIRS}
        )
    endif()

    target_link_libraries(${target} PRIVATE
        ${Purple_LIBRARIES}
        ${GLIB_LIBRARIES}
        ${JSONGLIB_LIBRARIES}
        z
    )
endfunction()

add_teams_protocol(teams)
add_teams_protocol(teams-personal ENABLE_TEAMS_PERSONAL)

# Where the plugin has to end up depends on the client, so this only says what
# libpurple itself reports and leaves the rest to the caller.
if (NOT DEFINED PURPLE_PLUGIN_DIR)
    pkg_get_variable(PURPLE_PLUGIN_DIR purple plugindir)
endif()

if (PURPLE_PLUGIN_DIR)
    install(TARGETS teams teams-personal DESTINATION "${PURPLE_PLUGIN_DIR}")
endif()
