#!/bin/bash -eu

##
# libffi
#
# There was no recipe here for years, and what the build linked against was whatever
# happened to be lying in build/lib. On the machine this was written on that was
# libffi.7.dylib beside a libffi.pc claiming version 3.2.9999, both dated long before
# the arm64 pipeline and produced by nothing in this repository. glib finds them through
# PKG_CONFIG_LIBDIR, links against them, and never asks again. A fresh clone has no
# libffi at all, so meson quietly falls back to glib's own subprojects/libffi.wrap
# instead, which is a different library carrying the same name. Two machines, two
# libffis, one framework, and nothing to say which one you got.
#
# The library number is not the release number. libffi 3.8.0 carries libtool version
# 13:0:5, so current minus age is 8 and the installed file is libffi.8.dylib, where the
# stale one was libffi.7.dylib. frameworkize.py reads that number out of the file name,
# so the framework under ../Frameworks becomes libffi.framework/Versions/8 and the load
# command inside libgobject, the only thing in the bundle that links libffi, follows it
# by itself. Nothing in the tree spells "Versions/7" out, so no project file has to be
# touched; a tree built before this simply keeps an unused Versions/7 next to the new
# one until somebody removes it.
#
# glib 2.88 asks for libffi >= 3.0.0 and its own wrap names 3.5.2, which has libtool
# version 10:0:2 and is therefore also libffi.8.dylib. Moving the pin back to 3.5.2 is
# a one line change and changes no name.
#
FFI_VERSION=8
build_libffi() {
	prereq "libffi" \
		"https://github.com/libffi/libffi/releases/download/v3.8.0/libffi-3.8.0.tar.gz" \
		"7da3e2d9a171eb0a038f592ecad3ff2bb2550f3496d87b3b29ad0cf4430c0db4"

	quiet pushd "$ROOTDIR/source/libffi"

	if needsconfigure $@; then
	(
		status "Configuring libffi"
		export CFLAGS="$ARCH_CFLAGS"
		export LDFLAGS="$ARCH_LDFLAGS"
		# Two of these are not taste:
		#   --disable-builddir, or configure re-executes itself inside a directory named
		#     after the host triplet and leaves config.status in there. needsconfigure()
		#     looks for config.status beside the sources, finds none, and configures
		#     again on every single run.
		#   --disable-docs, or the build reaches doc/ and stops because this machine has
		#     no makeinfo. We install no documentation from any package here.
		log ./configure --prefix="$ROOTDIR/build" \
			--disable-builddir \
			--disable-docs \
			--disable-static \
			--enable-shared \
			--disable-multi-os-directory \
			--disable-dependency-tracking
	)
	fi

	# What an install cannot tidy up after: the files from before this recipe existed.
	# make install writes libffi.8.dylib, libffi.pc, ffi.h and ffitarget.h over whatever
	# is there, but libffi.7.dylib and the two muxed headers beside it have no
	# counterpart in a 3.8 install and would sit in the prefix for ever, the first of
	# them close enough to the real thing to be picked up by accident. The unversioned
	# name has to go too when an older build left a regular file where libtool wants to
	# put a symbolic link.
	for leftover in \
		"$ROOTDIR/build/lib/libffi.7.dylib" \
		"$ROOTDIR/build/include/ffi-aarch64.h" \
		"$ROOTDIR/build/include/ffitarget-aarch64.h" ; do
		if [ -f "$leftover" ]; then
			status "Removing $(basename "$leftover"), left over from before this recipe"
			quiet rm -f "$leftover"
		fi
	done
	if [ -f "$ROOTDIR/build/lib/libffi.dylib" ] && [ ! -L "$ROOTDIR/build/lib/libffi.dylib" ]; then
		quiet rm -f "$ROOTDIR/build/lib/libffi.dylib"
	fi

	status "Building and installing libffi"
	log make -j $NUMBER_OF_CORES
	log make install

	# Said out loud, because the number in the file name is what decides the name of the
	# framework and everything that points at it.
	if [ ! -f "$ROOTDIR/build/lib/libffi.${FFI_VERSION}.dylib" ]; then
		error "libffi installed no libffi.${FFI_VERSION}.dylib; the framework version has moved"
		exit 1
	fi

	status "Successfully installed libffi"
	quiet popd
}
