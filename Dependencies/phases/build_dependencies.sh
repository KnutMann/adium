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
		"https://download.gnome.org/sources/glib/2.66/glib-2.66.7.tar.xz"
	
	quiet pushd "$ROOTDIR/source/glib"
	perl -0pi -e "s/build_tests = not meson\\.is_cross_build\\(\\) or \\(meson\\.is_cross_build\\(\\) and meson\\.has_exe_wrapper\\(\\)\\) or installed_tests_enabled/build_tests = false/" meson.build
	
	if needsconfigure $@; then
	(
		status "Configuring glib"
		log ln -sf /usr/bin/python3 "$ROOTDIR/build/bin/python3"
		export PYTHON=/usr/bin/python3
		quiet rm -rf _build
    meson \
        -Dprefix=$ROOTDIR/build \
        -Dman=false \
        -Diconv=auto \
        -Dinstalled_tests=false \
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
	
	status "Building and installing glib"
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
	prereq "json-glib-1.6.2" \
		"https://download.gnome.org/sources/json-glib/1.6/json-glib-1.6.2.tar.xz"
	
	quiet pushd "$ROOTDIR/source/json-glib-1.6.2"
	
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
	ninja -C _build install
	
	# C'mon, why do you make me do this?
#	log ln -fs "$ROOTDIR/build/include/json-glib-1.0/json-glib" \
#		"$ROOTDIR/build/include/json-glib"
	
	status "Successfully installed json-glib"
	quiet popd
}
