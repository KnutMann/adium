#!/bin/bash -eu

##
# pkg-config
#
# We only need a native pkg-config, so no worries about making it a Universal
# Binary.
#
build_pkgconfig() {
	prereq "pkg-config" \
		"http://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz"
	
	quiet pushd "$ROOTDIR/source/pkg-config"
	
	if needsconfigure $@; then
		status "Configuring pkg-config"
		log ./configure --prefix="$ROOTDIR/build"
	fi
	
	status "Building and installing pkg-config"
	log make -j $NUMBER_OF_CORES
	log make install
	
	status "Successfully installed pkg-config"
	quiet popd
}

##
# gettext
#
build_gettext() {
	local gettext_prefix
	gettext_prefix="$(brew --prefix gettext)"

	status "Staging gettext from ${gettext_prefix}"
	quiet mkdir -p "$ROOTDIR/build/include" "$ROOTDIR/build/lib" "$ROOTDIR/build/bin"
	log cp -f "${gettext_prefix}/include/libintl.h" "$ROOTDIR/build/include/"
	log cp -f "${gettext_prefix}/lib/libintl.8.dylib" "$ROOTDIR/build/lib/"
	log cp -f "${gettext_prefix}/bin/msgfmt" "$ROOTDIR/build/bin/"
	log cp -f "${gettext_prefix}/bin/xgettext" "$ROOTDIR/build/bin/"
	log cp -f "${gettext_prefix}/bin/msgmerge" "$ROOTDIR/build/bin/"

	status "Successfully installed gettext"
}

##
# glib
#
GLIB_VERSION=2.0
build_glib() {
	prereq "glib" \
		"https://download.gnome.org/sources/glib/2.88/glib-2.88.3.tar.xz"
	
	quiet pushd "$ROOTDIR/source/glib"
	
	if needsconfigure $@; then
	(
		status "Configuring glib"
		log ln -sf /usr/bin/python3 "$ROOTDIR/build/bin/python3"
		export PYTHON=/usr/bin/python3
		#Meson has to be told about our tree five times over, and missing any one of them
		#fails in a way that looks like something else:
		#  - cpp_args/cpp_link_args as well as the c_ ones: glib is a C *and* C++ project, and
		#    the intl probe runs through the C++ compiler. Without them it reports
		#    "library 'intl' not found" and quietly falls back to the proxy-libintl
		#    subproject - a stub that answers every gettext call with the untranslated
		#    string and, on install, overwrites the real libintl staged from Homebrew.
		#  - PKG_CONFIG_LIBDIR, or it finds the SDK's libffi, whose include directory does
		#    not exist on macOS 26.
		#  - LIBRARY_PATH, which is what clang consults for -l at the final link; the meson
		#    options only reach the probes.
		#  - c_link_args/cpp_link_args have to carry -mmacosx-version-min as well, not only
		#    the compile arguments. A Mach-O's minimum is written by the linker, not the
		#    compiler, and clang with no flag on the link line falls back to the machine it
		#    runs on: the five glib libraries came out stamped for macOS 26 while every
		#    object inside them said 12, and the application, built for 12, collected a
		#    linker warning for each of them.
		#-Dnls=enabled makes the fallback an error rather than a silent downgrade.
		#
		#The libffi that PKG_CONFIG_LIBDIR points meson at is older than this script:
		#build/lib/libffi.7.dylib and its libffi.pc say version 3.2.9999, they date from
		#before the arm64 pipeline, and no recipe here has ever built them. So they are
		#reused forever and carry whatever minimum the machine had on the day they were
		#made, while a fresh clone has no libffi at all and silently builds
		#subprojects/libffi.wrap instead - a different library under the same name.
		#Deleting build/lib/libffi*, build/lib/pkgconfig/libffi.pc and
		#build/include/ffi*.h makes the wrap the only answer on every machine, which is
		#the shape this wants; it also renames the framework from Versions/7 to
		#Versions/8, so it is not a change to make halfway.
		export PKG_CONFIG_PATH="$ROOTDIR/build/lib/pkgconfig"
		export PKG_CONFIG_LIBDIR="$ROOTDIR/build/lib/pkgconfig"
		export LIBRARY_PATH="$ROOTDIR/build/lib"
		quiet rm -rf _build
    meson setup \
        -Dprefix=$ROOTDIR/build \
        -Dman-pages=disabled \
        -Dtests=false \
        -Dinstalled_tests=false \
        -Dintrospection=disabled \
        -Dnls=enabled \
        -Dc_args="-I$ROOTDIR/build/include -mmacosx-version-min=$MIN_OS_VERSION" \
        -Dc_link_args="-L$ROOTDIR/build/lib -Wl,-headerpad_max_install_names -mmacosx-version-min=$MIN_OS_VERSION" \
        -Dcpp_args="-I$ROOTDIR/build/include -mmacosx-version-min=$MIN_OS_VERSION" \
        -Dcpp_link_args="-L$ROOTDIR/build/lib -Wl,-headerpad_max_install_names -mmacosx-version-min=$MIN_OS_VERSION" \
        _build
    status "Configured."


#				--disable-static \
#				--enable-shared \
#				--with-libiconv=native \
#				--disable-fam \
#				--disable-selinux \
#				--with-threads=posix \
#				--disable-dependency-tracking"
#		xconfigure "${BASE_CFLAGS}" "${BASE_LDFLAGS} -lintl" "${CONFIG_CMD}" \
#			"${ROOTDIR}/source/glib/config.h" \
#			"${ROOTDIR}/source/glib/gmodule/gmoduleconf.h" \
#			"${ROOTDIR}/source/glib/glibconfig.h"
	)
	fi
	
	# meson installs the unversioned names as symbolic links and refuses to replace
	# a regular file, which is what an older build leaves behind. This has to happen
	# before every install and not only before a fresh configure: an install is where
	# it bites, and an install runs whether or not anything was configured again.
	# Whichever libraries glib happens to install, rather than a list of five, because
	# girepository joined them and was not on that list.
	for path in "$ROOTDIR"/build/lib/lib*-2.0.dylib ; do
		if [ -f "$path" ] && [ ! -L "$path" ] ; then
			quiet rm -f "$path"
		fi
	done

	status "Building and installing glib"
	export LIBRARY_PATH="$ROOTDIR/build/lib"
	export PKG_CONFIG_PATH="$ROOTDIR/build/lib/pkgconfig"
	export PKG_CONFIG_LIBDIR="$ROOTDIR/build/lib/pkgconfig"
	ninja -C _build install
	
	status "Successfully installed glib"
	quiet popd
}

##
# intltool
#
INTL_VERSION=8
build_intltool() {
	# We used to use 0.36.2, but I switched to the latest MacPorts is using
	prereq "intltool" \
		"https://download.gnome.org/sources/intltool/0.40/intltool-0.40.6.tar.bz2"
	
	quiet pushd "$ROOTDIR/source/intltool"
	
	if needsconfigure $@; then
	(
		status "Configuring intltool"
		export CFLAGS="$ARCH_CFLAGS"
		export LDFLAGS="$ARCH_LDFLAGS"
		log ./configure --prefix="$ROOTDIR/build" --disable-dependency-tracking
	)
	fi
	
	status "Building and installing intltool"
	log make -j $NUMBER_OF_CORES
	log make install
	
	status "Successfully installed intltool"
	quiet popd
}

##
# json-glib
#
JSON_GLIB_VERSION=1.0
build_jsonglib() {
	prereq "json-glib-1.10.8" \
		"https://download.gnome.org/sources/json-glib/1.10/json-glib-1.10.8.tar.xz"
	
	quiet pushd "$ROOTDIR/source/json-glib-1.10.8"
	
	if needsconfigure $@; then
	(
		status "Configuring json-glib"
		log ln -sf /usr/bin/python3 "$ROOTDIR/build/bin/python3"
		export CFLAGS="$ARCH_CFLAGS"
		export LDFLAGS="$ARCH_LDFLAGS"
		export GLIB_LIBS="$ROOTDIR/build/lib"
		export GLIB_CFLAGS="-I$ROOTDIR/build/include/glib-2.0 -I$ROOTDIR/build/lib/glib-2.0/include"
		export PYTHON=/usr/bin/python3
		quiet rm -rf _build
		meson \
        -Dprefix=$ROOTDIR/build \
        -Dintrospection=disabled \
        -Dman=false \
        -Dtests=false \
        _build
		status "Configured."
	)
	fi
	
	status "Building and installing json-glib"
	#Same as glib: meson wants the unversioned name to be a symlink and will not
	#replace a regular file left by an older build.
	if [ -f "$ROOTDIR/build/lib/libjson-glib-1.0.dylib" ] && [ ! -L "$ROOTDIR/build/lib/libjson-glib-1.0.dylib" ] ; then
		quiet rm -f "$ROOTDIR/build/lib/libjson-glib-1.0.dylib"
	fi
	ninja -C _build install
	
	# C'mon, why do you make me do this?
#	log ln -fs "$ROOTDIR/build/include/json-glib-1.0/json-glib" \
#		"$ROOTDIR/build/include/json-glib"
	
	status "Successfully installed json-glib"
	quiet popd
}
