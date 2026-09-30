#!/bin/bash -eu

##
# pkg-config
#
# We only need a native pkg-config, so no worries about making it a Universal
# Binary.
#
build_pkgconfig() {
	prereq "pkg-config" \
		"http://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz" \
		"6fc69c01688c9458a57eb9a1664c9aba372ccda420a02bf4429fe610e7e7d591"
	
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
# This used to copy four files out of `brew --prefix gettext` and call it a build. It
# worked, on a machine that had Homebrew and had gettext installed in it, and the
# library it put in the prefix was stamped for the macOS that the Homebrew bottle had
# been built on. Measured rather than supposed: the bottle here says minos 15.0, while
# everything else in this directory says 12.0 and the application is built for 12.0.
# Every other package here is fetched, pinned and compiled; this one was a machine's
# opinion.
#
# 1.0 is what Homebrew ships as well, so nothing else about the result moves: gettext
# carries libtool version 12:6:4, current minus age is 8, and the library is
# libintl.8.dylib with compatibility version 13.0.0, byte for byte the same names the
# relink scripts under patches/ map onto libintl.framework/Versions/8/libintl.
#
# --with-included-libintl keeps configure from deciding that the libintl it finds on the
# machine, or the one this recipe installed the run before, is good enough and that it
# needs to build none of its own. The other two --with-included-* keep libunistring,
# which is a Homebrew package, and libxml2, which is the operating system's, out of the
# result. They cost something: xgettext with libxml2 compiled into it is thirteen
# megabytes. It sits in build/bin, is used to compile catalogues, and is never shipped.
#
# The languages are switched off because we want a library and three tools, not the
# Java, C#, D, Go and Modula-2 bindings, and each of them costs build time and a search
# for a compiler that may or may not be installed.
#
build_gettext() {
	prereq "gettext" \
		"https://ftp.gnu.org/gnu/gettext/gettext-1.0.tar.gz" \
		"85d99b79c981a404874c02e0342176cf75c7698e2b51fe41031cf6526d974f1a"

	quiet pushd "$ROOTDIR/source/gettext"

	if needsconfigure $@; then
	(
		status "Configuring gettext"
		export CFLAGS="$ARCH_CFLAGS"
		export LDFLAGS="$ARCH_LDFLAGS"
		# Without this line gettext does not build on this machine at all, and the
		# failure names nothing that has anything to do with the cause:
		#
		#   Undefined symbols for architecture arm64:
		#     "_iconv_ostream_create", referenced from: <initial-undefines>
		#   make[5]: *** [libtextstyle.la] Error 1
		#
		# gnulib runs the converter it found through six known bugs and decides whether
		# to trust it. One of the six is the macOS 14.4 bug: converting U+0142 from
		# UTF-8 to ISO-8859-1 should fail, and Apple's iconv quietly transliterates it
		# to "l" and reports success instead. Every macOS since 14.4 fails that test,
		# this one included, so gnulib writes "not working, consider installing GNU
		# libiconv" into its cache and leaves HAVE_ICONV undefined in all three
		# subtrees. libtextstyle then compiles iconv-ostream.c to nothing, while the
		# export list beside it is copied out of a distributed libtextstyle.sym.in
		# without regard for what was compiled and still names the symbol, so the link
		# falls over.
		#
		# Saying yes here is not papering over the failure: it puts the build back into
		# exactly the configuration that was being used before, because the Homebrew
		# bottle this recipe replaces was compiled on an older macOS, has HAVE_ICONV
		# set, and has been running against this same system iconv all along. It also
		# keeps the conversion that we actually want: with HAVE_ICONV undefined, libintl
		# loses bind_textdomain_codeset and msgfmt loses the ability to read a catalogue
		# that is not already UTF-8. What we give up is Apple's failure to report a
		# transliteration, which nothing here asks about.
		#
		# The alternative is to build GNU libiconv from source as well and point gettext
		# at it, which is what gnulib is suggesting. That is a whole further package and
		# a further library in the bundle, for one conversion no one makes.
		export am_cv_func_iconv_works=yes
		log ./configure --prefix="$ROOTDIR/build" \
			--disable-static \
			--enable-shared \
			--with-included-libintl \
			--with-included-libunistring \
			--with-included-libxml \
			--disable-java \
			--disable-csharp \
			--disable-d \
			--disable-go \
			--disable-modula2 \
			--disable-curses \
			--disable-openmp \
			--without-emacs \
			--without-git \
			--without-bzip2 \
			--without-xz \
			--disable-dependency-tracking
	)
	fi

	status "Building and installing gettext"
	log make -j $NUMBER_OF_CORES
	log make install

	# The rest of the build reaches for these three by name, through the prefix on PATH,
	# and a missing one shows up much later as a translation that silently did not get
	# compiled. Say it here instead.
	for tool in msgfmt xgettext msgmerge ; do
		if [ ! -x "$ROOTDIR/build/bin/$tool" ]; then
			error "gettext installed no $tool into $ROOTDIR/build/bin"
			exit 1
		fi
	done
	if [ ! -f "$ROOTDIR/build/lib/libintl.${INTL_VERSION}.dylib" ]; then
		error "gettext installed no libintl.${INTL_VERSION}.dylib; the framework version has moved"
		exit 1
	fi

	status "Successfully installed gettext"
	quiet popd
}

##
# glib
#
GLIB_VERSION=2.0
build_glib() {
	prereq "glib" \
		"https://download.gnome.org/sources/glib/2.88/glib-2.88.3.tar.xz" \
		"ab24d24e698dfa1e408b7bcdb508f4aafc906185a8b8ce72fdf79bbbdc9b383b"
	
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
		#The libffi that PKG_CONFIG_LIBDIR points meson at is now built by
		#phases/build_libffi.sh, which runs just before this and installs libffi.8.dylib
		#and a libffi.pc into the prefix. Until that recipe existed this found whatever
		#was lying in build/lib - on an old tree a libffi.7.dylib claiming 3.2.9999 that
		#nothing here had built, on a fresh clone nothing at all, in which case meson
		#silently built subprojects/libffi.wrap instead. So build_libffi has to stay
		#ahead of this one in build.sh, or the fallback comes back.
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
		"https://download.gnome.org/sources/intltool/0.40/intltool-0.40.6.tar.bz2" \
		"4d1e5f8561f09c958e303d4faa885079a5e173a61d28437d0013ff5efc9e3b64"
	
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

	# intltool 0.40.6 is from 2009 and writes \${?NAME}? in six regular expressions.
	# Since perl 5.26 an unescaped left brace in a pattern is a warning, and intltool
	# has had no release since, so every distribution carries this same one-line
	# patch. Without it intltool-update prints two pages of warnings into the middle
	# of libpurple's configure output, where they read like a real failure. It is only
	# noise, the scripts still exit 0, but noise that costs whoever reads the log next.
	log perl -pi -e 's/\\\$\{\?/\\\$\\{?/g' "$ROOTDIR/build/bin/intltool-update"

	# The shebang autoconf wrote names the perl that configure found, which on a Mac
	# with Homebrew is Homebrew's. These scripts run on any perl 5, and the one every
	# Mac has is the system one; naming it keeps the build from depending on a perl
	# that a fresh clone has no reason to have. build_libpurple used to do this to the
	# three scripts it copied out of Homebrew.
	log perl -0pi -e 's{^#!.*perl}{#!/usr/bin/perl}' \
		"$ROOTDIR/build/bin/intltool-extract" \
		"$ROOTDIR/build/bin/intltool-merge" \
		"$ROOTDIR/build/bin/intltool-update"

	status "Successfully installed intltool"
	quiet popd
}

##
# json-glib
#
JSON_GLIB_VERSION=1.0
build_jsonglib() {
	prereq "json-glib-1.10.8" \
		"https://download.gnome.org/sources/json-glib/1.10/json-glib-1.10.8.tar.xz" \
		"55c5c141a564245b8f8fbe7698663c87a45a7333c2a2c56f06f811ab73b212dd"
	
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
