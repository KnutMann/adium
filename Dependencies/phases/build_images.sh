#!/bin/bash -eu

##
# The image libraries.
#
# Five dylibs under ../Frameworks used to be copies of whatever Homebrew happened to have
# on the machine that built the bundle: libpng16.16.dylib, libjpeg.8.dylib,
# libwebp.7.dylib, libsharpyuv.0.dylib and libgdk_pixbuf-2.0.0.dylib. They were copied in
# with their load paths rewritten by hand and no recipe anywhere, so a fresh clone could
# not reproduce them, and the bottles they came from are stamped for whatever macOS the
# bottle was built for. Measured on the copies that are in the tree today:
#
#   libpng16.16.dylib        minos 26.0
#   libjpeg.8.dylib          minos 26.0
#   libgdk_pixbuf-2.0.0.dylib  minos 26.0
#   libwebp.7.dylib          minos 15.0
#   libsharpyuv.0.dylib      minos 15.0
#
# Adium is built for MIN_OS_VERSION, which is 12.0, so each of them is one of the linker
# warnings the build prints. These recipes fetch pinned releases and build them with the
# project's own flags, which is what makes the warnings go away and what lets a second Mac
# produce the same libraries.
#
# WHO USES THEM. libpurple links none of the five; the users are the bundled protocol
# plug-ins under ../PurplePlugins:
#
#   libgdk_pixbuf  purple-presage draws the Signal linking QR code with it and asks it to
#                  encode a PNG (gdk_pixbuf_new / _get_pixels / _scale_simple /
#                  _save_to_buffer). That is the one use that cannot go away.
#                  purple-gowhatsapp also links it, but only for
#                  gdk_pixbuf_get_formats + gdk_pixbuf_format_get_mime_types, and the
#                  Adium build defines GOWHATSAPP_INLINE_ALL_IMAGES, which inlines every
#                  image/* regardless of the answer. That link is vestigial.
#   libpng         tdlib-purple writes PNGs with it directly (png_write_png and friends,
#                  converting Telegram stickers), and gdk-pixbuf needs it for the PNG
#                  loader that presage's save_to_buffer goes through.
#   libjpeg        nothing in Adium decodes a JPEG through it. It is here because
#                  gdk-pixbuf's default set of built-in loaders is exactly png+jpeg, so
#                  gdk-pixbuf links it. Keeping it preserves what the bundle does today;
#                  -Djpeg=disabled below would remove the library and shrink
#                  gdk_pixbuf_get_formats to PNG alone.
#   libwebp        tdlib-purple decodes WebP stickers with it (WebPDecode).
#   libsharpyuv    nobody calls it. It is the colour-conversion half that libwebp split
#                  out of itself in 1.3 and links, so it has to travel with libwebp.
#
# So all five are still load-bearing, in the sense that a shipped Mach-O names each of
# them; two of them (libjpeg, libsharpyuv) only because a library above them names them.
#
# ORDER. libpng, libjpeg and libwebp are independent of each other and of everything else
# here - they take nothing out of the prefix and can run in any order, before or after
# glib. gdk-pixbuf is the one with prerequisites: it needs glib, gobject, gmodule and gio
# from build_glib, and libpng and libjpeg from the two recipes above it, all already
# installed into $ROOTDIR/build. So:
#
#   build_libpng   \
#   build_libjpeg   >  any order, no prerequisites
#   build_libwebp  /
#   build_gdkpixbuf   after build_libffi, build_glib, build_libpng and build_libjpeg
#
# build_libffi is on that list and not only build_glib, because gobject-2.0.pc requires
# libffi and the pkg-config search path this recipe sets has nowhere else to find it. See
# the note on --wrap-mode=nofallback below for what happens when it is missing.
#
# and all four before anything that builds a plug-in from source, because
# purple-gowhatsapp, purple-presage and tdlib-purple find them through pkg-config.
#
# The independence of libwebp is not free: build.sh puts $ROOTDIR/build/bin first on PATH,
# so once libpng has installed libpng-config there, libwebp's configure would find it and
# link its example tools against it. --disable-png below (and jpeg, tiff, gif, gl) keeps
# that from happening, which is what makes the three genuinely order-free.
#
# INSTALL NAMES. Every recipe here leaves the install name at the prefix path, the way
# libtool and meson write it by default and the way every other recipe in this directory
# does - $ROOTDIR/build/lib/libpng16.16.dylib and so on. It is tempting to stamp
# @executable_path/../Frameworks/... in directly, since that is what the shipped copies
# carry, but gdk-pixbuf's install then breaks: its post-install script runs the
# gdk-pixbuf-query-loaders it has just built, and that binary has to be able to find
# libgdk_pixbuf, libpng and libjpeg on disk to start at all.
#
# So rewriting the names belongs in the step that stages these into ../Frameworks, and
# that step has three things to do, not one:
#
#   -id     on each of the five, to @executable_path/../Frameworks/<name>
#   -change on libwebp.7.dylib, whose reference to libsharpyuv.0.dylib is absolute
#   -change on libgdk_pixbuf-2.0.0.dylib, whose references to libpng16.16.dylib and
#           libjpeg.8.dylib are absolute, as are the five to the glib frameworks
#
# One naming detail for whoever writes the copy: libtool and meson install the versioned
# name as the real file, but cmake does not. In build/lib, libjpeg.8.dylib is a symbolic
# link and libjpeg.8.3.2.dylib is the file. A plain cp follows the link and produces a
# real file that already calls itself libjpeg.8.dylib, which is what is wanted; a cp -a
# would copy the link and ship a dangling one.
#

##
# libpng
#
# Plain autotools. The only thing worth saying is that it finds zlib in the SDK and must
# keep doing so: /usr/lib/libz.1.dylib is the one dependency the finished library is
# allowed to have besides libSystem.
#
build_libpng() {
	prereq "libpng" \
		"https://downloads.sourceforge.net/project/libpng/libpng16/1.6.58/libpng-1.6.58.tar.xz" \
		"28eb403f51f0f7405249132cecfe82ea5c0ef97f1b32c5a65828814ae0d34775"

	quiet pushd "$ROOTDIR/source/libpng"

	if needsconfigure $@; then
	(
		status "Configuring libpng"
		export CFLAGS="$ARCH_CFLAGS"
		export LDFLAGS="$ARCH_LDFLAGS"
		log ./configure --prefix="$ROOTDIR/build" \
			--disable-static \
			--enable-shared \
			--disable-dependency-tracking
	)
	fi

	status "Building and installing libpng"
	log make -j $NUMBER_OF_CORES
	log make install

	# The file name is the one the plug-ins and the copy phase already name. libpng's
	# libtool version has said 16:x:0 since 1.6.0, so this is a regression check rather
	# than a real risk - but it is a silent one if it ever moves.
	if [ ! -f "$ROOTDIR/build/lib/libpng16.16.dylib" ]; then
		error "libpng installed no libpng16.16.dylib; the name the bundle uses has moved"
		exit 1
	fi

	# libpng16.pc ends with "Requires.private: zlib", and macOS ships zlib as a library
	# with no .pc file anywhere: not in /usr/lib/pkgconfig, not in the SDK, which has no
	# pkgconfig directory at all. Nothing notices until somebody looks libpng up with
	# PKG_CONFIG_LIBDIR restricted to this prefix - which is exactly what build_gdkpixbuf
	# must do to keep Homebrew's glib out of the bundle - and then pkg-config answers
	#
	#   Package 'zlib', required by 'libpng', not found
	#
	# and the gdk-pixbuf configure stops. Measured, not guessed: pkg-config --cflags --libs
	# libpng with PKG_CONFIG_LIBDIR set to the prefix alone exits 1 without this file.
	#
	# Describing the system zlib is the smaller and more honest of the two fixes; the other
	# is to delete the Requires line out of libpng16.pc and pretend the dependency is not
	# there. The library really is /usr/lib/libz.1.dylib, which is also the only thing
	# libpng16.16.dylib links besides libSystem, and zlib.h really is in the SDK. The
	# version is the current version that dylib reports.
	status "Describing the system zlib for pkg-config"
	quiet mkdir -p "$ROOTDIR/build/lib/pkgconfig"
	cat > "$ROOTDIR/build/lib/pkgconfig/zlib.pc" <<-PC
		prefix=/usr
		exec_prefix=\${prefix}
		libdir=\${exec_prefix}/lib
		includedir=\${prefix}/include

		Name: zlib
		Description: zlib compression library, the copy macOS ships in /usr/lib
		Version: 1.2.12
		Libs: -lz
		Cflags:
	PC

	status "Successfully installed libpng"
	quiet popd
}

##
# libjpeg-turbo
#
# The third build system in this directory, after autotools and meson: libjpeg-turbo
# dropped its configure script in 2.1 and is cmake only. Three of the flags decide what
# comes out:
#
#   -DWITH_JPEG8=1        without it the library is libjpeg.62.dylib, emulating the 6b
#                         API. The bundle, the plug-ins that already name it and the
#                         Xcode copy phase all say libjpeg.8.dylib, so this is not
#                         optional. It also fixes the version triple at 8.3.2.
#   -DCMAKE_INSTALL_NAME_DIR   cmake's default install name on macOS is
#                         @rpath/libjpeg.8.dylib, not the absolute libdir that libtool and
#                         meson write. Left at the default, gdk-pixbuf records @rpath, the
#                         query-loaders binary cannot resolve it at install time, and the
#                         relink step later has nothing to match on.
#   -DENABLE_STATIC=0     no libjpeg.a; nothing here links one.
#
# WITH_TURBOJPEG=0 drops the second, TurboJPEG-API library, which nothing in Adium calls.
# SIMD stays on: on arm64 it is NEON written as intrinsics, so it needs no assembler.
#
build_libjpeg() {
	prereq "libjpeg-turbo" \
		"https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.2.0/libjpeg-turbo-3.2.0.tar.gz" \
		"6f30092cef9fb839779646608f4ee14ae3cbac989c47fa05e841b0841f09878e"

	quiet pushd "$ROOTDIR/source/libjpeg-turbo"

	# cmake leaves no config.status, so needsconfigure always says yes here, exactly as it
	# does for the meson packages. The configure step is cheap; _build is thrown away so a
	# moved pin cannot be answered out of a stale cache.
	if needsconfigure $@; then
	(
		status "Configuring libjpeg-turbo"
		export CFLAGS="$ARCH_CFLAGS"
		export LDFLAGS="$ARCH_LDFLAGS"
		quiet rm -rf _build
		# Called directly rather than through log: log does not quote its arguments, and
		# these carry paths. The meson recipes in build_dependencies.sh do the same.
		cmake -S . -B _build \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_INSTALL_PREFIX="$ROOTDIR/build" \
			-DCMAKE_INSTALL_LIBDIR=lib \
			-DCMAKE_INSTALL_NAME_DIR="$ROOTDIR/build/lib" \
			-DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_OS_VERSION" \
			-DCMAKE_OSX_SYSROOT="$SDK_ROOT" \
			-DWITH_JPEG8=1 \
			-DWITH_TURBOJPEG=0 \
			-DENABLE_STATIC=0
		status "Configured."
	)
	fi

	status "Building and installing libjpeg-turbo"
	cmake --build _build -j $NUMBER_OF_CORES
	cmake --install _build

	if [ ! -f "$ROOTDIR/build/lib/libjpeg.8.dylib" ] && [ ! -L "$ROOTDIR/build/lib/libjpeg.8.dylib" ]; then
		error "libjpeg-turbo installed no libjpeg.8.dylib; is WITH_JPEG8 still set?"
		exit 1
	fi

	status "Successfully installed libjpeg-turbo"
	quiet popd
}

##
# libwebp, and libsharpyuv with it
#
# One build produces both: sharpyuv/ is a directory inside the libwebp tree that installs
# its own libsharpyuv.0.dylib, and libwebp.7.dylib links it. There is no separate release
# to pin and no separate recipe to write, and there is no flag to ask for it either -
# --enable-libsharpyuv looks like it exists because configure.ac mentions the name, but
# only inside --enable-everything, and configure answers a bare one with
# "WARNING: unrecognized options" and builds the library regardless. So it is not passed.
#
# Everything optional is switched off. --disable-png and the other four format flags are
# not cosmetic: they only affect cwebp/dwebp, the example tools, but with
# $ROOTDIR/build/bin first on PATH those tools would pick up the libpng-config that
# build_libpng just installed, and libwebp would quietly grow an ordering constraint it
# does not otherwise have. mux and demux are off because the bundle carries neither; if a
# plug-in ever asks pkg-config for libwebpdemux, that is the line to change.
#
build_libwebp() {
	prereq "libwebp" \
		"https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz" \
		"e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564"

	quiet pushd "$ROOTDIR/source/libwebp"

	if needsconfigure $@; then
	(
		status "Configuring libwebp"
		export CFLAGS="$ARCH_CFLAGS"
		export LDFLAGS="$ARCH_LDFLAGS"
		log ./configure --prefix="$ROOTDIR/build" \
			--disable-static \
			--enable-shared \
			--disable-libwebpmux \
			--disable-libwebpdemux \
			--disable-png \
			--disable-jpeg \
			--disable-tiff \
			--disable-gif \
			--disable-gl \
			--disable-sdl \
			--disable-wic \
			--disable-dependency-tracking
	)
	fi

	status "Building and installing libwebp"
	log make -j $NUMBER_OF_CORES
	log make install

	for lib in libwebp.7.dylib libsharpyuv.0.dylib ; do
		if [ ! -f "$ROOTDIR/build/lib/$lib" ] && [ ! -L "$ROOTDIR/build/lib/$lib" ]; then
			error "libwebp installed no $lib; the name the bundle uses has moved"
			exit 1
		fi
	done

	status "Successfully installed libwebp and libsharpyuv"
	quiet popd
}

##
# gdk-pixbuf
#
# Meson, and the same five-fold briefing build_glib needs, for the same reasons: this is a
# glib consumer, and the one thing that must not happen is that it finds Homebrew's glib
# instead of ours and the bundle ends up with two copies of glib in one process.
# PKG_CONFIG_LIBDIR, not only PKG_CONFIG_PATH, is what makes the prefix the only place
# pkg-config looks; LIBRARY_PATH is what clang consults at the final link, which the meson
# options do not reach; and c_link_args has to carry -mmacosx-version-min, because a
# Mach-O's minimum is written by the linker, not the compiler.
#
# --wrap-mode=nofallback is the one flag here that was learned the hard way rather than
# copied. gdk-pixbuf declares glib, gobject, gmodule and gio with
# fallback: ['glib', ...], so when pkg-config cannot answer for any one of the four -
# and the way that happens is not a missing glib but a missing libffi, because
# gobject-2.0.pc requires it and PKG_CONFIG_LIBDIR has shut off every other place to look -
# meson does not stop. It builds a whole second glib inside gdk-pixbuf, from
# subprojects/glib.wrap, and the finished library carries its own copy of the thing the
# bundle already has one of. That is the same failure as the proxy-libintl one that
# build_glib documents, in a different package: the run goes green and the damage is
# discovered much later. With nofallback a missing dependency is an error with a name on
# it, which is what we want. It also means this recipe has to run after build_libffi and
# build_glib, not merely after glib's files exist.
#
# The loaders are the other half of the recipe. builtin_loaders is left at its default,
# which on this platform expands to exactly png,jpeg - the two the shipped copy has, so
# nothing about what the bundle can decode moves. Everything else is disabled explicitly
# rather than left at auto: tiff would otherwise attach a libtiff that nothing ships, and
# gif, others and glycin would build loadable modules into
# build/lib/gdk-pixbuf-2.0/2.10.0/loaders/, which never reaches the bundle and so is only
# a way to be confused later. man needs rst2man, introspection needs g-ir-scanner and glib
# here is built without it, and the thumbnailer is a program for a desktop we do not have.
#
# One thing this fixes that was not on the list: the Homebrew copy has /opt/homebrew/lib
# compiled in as GDK_PIXBUF_LIBDIR, so on any Mac that also has Homebrew's gdk-pixbuf the
# shipped library would read Homebrew's loaders.cache and dlopen Homebrew's loader modules
# into Adium. A copy built here names $ROOTDIR/build/lib, which exists on no user's
# machine, so it is built-in loaders and nothing else.
#
GDK_PIXBUF_VERSION=2.0
build_gdkpixbuf() {
	prereq "gdk-pixbuf" \
		"https://download.gnome.org/sources/gdk-pixbuf/2.44/gdk-pixbuf-2.44.7.tar.xz" \
		"172f80e3626ec31520a970400f1a3694e04718f6c2cd2885f75250fb5a6995a4"

	quiet pushd "$ROOTDIR/source/gdk-pixbuf"

	if needsconfigure $@; then
	(
		status "Configuring gdk-pixbuf"
		log ln -sf /usr/bin/python3 "$ROOTDIR/build/bin/python3"
		export PYTHON=/usr/bin/python3
		export PKG_CONFIG_PATH="$ROOTDIR/build/lib/pkgconfig"
		export PKG_CONFIG_LIBDIR="$ROOTDIR/build/lib/pkgconfig"
		export LIBRARY_PATH="$ROOTDIR/build/lib"
		quiet rm -rf _build
		meson setup \
			--wrap-mode=nofallback \
			-Dprefix=$ROOTDIR/build \
			-Dpng=enabled \
			-Djpeg=enabled \
			-Dtiff=disabled \
			-Dgif=disabled \
			-Dothers=disabled \
			-Dglycin=disabled \
			-Dandroid=disabled \
			-Dlegacy_xpm=disabled \
			-Dthumbnailer=disabled \
			-Dintrospection=disabled \
			-Ddocumentation=false \
			-Dman=false \
			-Dtests=false \
			-Dinstalled_tests=false \
			-Drelocatable=false \
			-Dc_args="-I$ROOTDIR/build/include -mmacosx-version-min=$MIN_OS_VERSION" \
			-Dc_link_args="-L$ROOTDIR/build/lib -Wl,-headerpad_max_install_names -mmacosx-version-min=$MIN_OS_VERSION" \
			_build
		status "Configured."
	)
	fi

	# Same trap as glib and json-glib: meson installs the unversioned name as a symbolic
	# link and refuses to replace a regular file, which is what an older build leaves
	# behind. glib's own loop over lib*-2.0.dylib runs before this recipe has installed
	# anything, so it does not cover this one.
	if [ -f "$ROOTDIR/build/lib/libgdk_pixbuf-${GDK_PIXBUF_VERSION}.dylib" ] && \
	   [ ! -L "$ROOTDIR/build/lib/libgdk_pixbuf-${GDK_PIXBUF_VERSION}.dylib" ] ; then
		quiet rm -f "$ROOTDIR/build/lib/libgdk_pixbuf-${GDK_PIXBUF_VERSION}.dylib"
	fi

	status "Building and installing gdk-pixbuf"
	export PKG_CONFIG_PATH="$ROOTDIR/build/lib/pkgconfig"
	export PKG_CONFIG_LIBDIR="$ROOTDIR/build/lib/pkgconfig"
	export LIBRARY_PATH="$ROOTDIR/build/lib"
	ninja -C _build install

	# 2.44.7 gives libgdk_pixbuf-2.0.0.dylib with compatibility version 4401, which is
	# what the three plug-ins already record. A gdk-pixbuf whose minor version moved would
	# rename the file and silently stop satisfying them.
	if [ ! -f "$ROOTDIR/build/lib/libgdk_pixbuf-${GDK_PIXBUF_VERSION}.0.dylib" ] && \
	   [ ! -L "$ROOTDIR/build/lib/libgdk_pixbuf-${GDK_PIXBUF_VERSION}.0.dylib" ]; then
		error "gdk-pixbuf installed no libgdk_pixbuf-${GDK_PIXBUF_VERSION}.0.dylib; the name the bundle uses has moved"
		exit 1
	fi

	status "Successfully installed gdk-pixbuf"
	quiet popd
}
