#!/bin/bash -eu

##
# OpenSSL
#
# Frameworks/libcrypto.3.dylib and Frameworks/libssl.3.dylib used to be copies
# lifted out of Homebrew with their load paths rewritten by hand. Nothing in
# Dependencies built them, so nobody could reproduce them, every security update
# meant copying from Homebrew again, and the two libraries were stamped for
# whatever macOS the Mac that did the copying happened to run - which is where two
# of the application's linker warnings came from.
#
# Two consumers, and only two:
#
#   PurplePlugins/libtelegram-tdlib.so   TDLib's transport and its cryptography;
#                                        links both libraries, 154 symbols out of
#                                        libcrypto and 23 out of libssl
#   Dependencies/picomemo                the cryptographic half of OMEMO; a static
#                                        library, so its 27 libcrypto symbols are
#                                        resolved when AdiumLibpurple links, see
#                                        Frameworks/AIUtilities/xcconfigs/AdiumLibpurple.xcconfig
#
# libpurple does not use OpenSSL: its TLS goes through ssl-cdsa, which is Apple's
# Secure Transport. Nothing else in the bundle touches these two libraries.
#
# 3.5.9 rather than the 3.6.4 that was shipped, because 3.5 is the Long Term
# Support branch. OpenSSL supports it until 2030-04-08; 3.6 it supports until
# 2026-11-01 and 3.4 until 2026-10-22. So the branch we were copying out of
# Homebrew runs out in a month, and 3.6.5 would only move that by a release.
# Nothing is given up by going back one branch: security fixes are backported, and
# 3.5.9 and 3.6.5 name the same thirteen CVEs - the two lists are identical.
#
# The file name does not move with the release either. The shared-library version
# is 3 on both branches, so this is still libcrypto.3.dylib and libssl.3.dylib,
# and the compatibility and current version both stay 3.0.0, which is what
# PurplePlugins/libtelegram-tdlib.so was linked against.
#
# https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz
#
OPENSSL_VERSION=3.5.9

# The number in the file name, which is the shared-library version and not the
# release. They have been different things since 3.0.0 and the whole bundle - the
# Xcode project, the relink scripts under patches/ - spells the file name with
# this one.
OPENSSL_SOVERSION=3

build_openssl() {
	prereq "openssl" \
		"https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" \
		"603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a"

	quiet pushd "$ROOTDIR/source/openssl"

	local cryptoLib="libcrypto.${OPENSSL_SOVERSION}.dylib"
	local sslLib="libssl.${OPENSSL_SOVERSION}.dylib"
	local frameworksPath="@executable_path/../Frameworks"

	# OpenSSL does not use autotools. Its Configure script names a target rather
	# than probing the machine, and the two Darwin targets that matter are these.
	# build.sh only ever builds for the machine it runs on, so the target follows
	# ARCHS the same way ARCH_CFLAGS does.
	local opensslTarget
	case "${ARCHS[0]}" in
		arm64)  opensslTarget="darwin64-arm64" ;;
		x86_64) opensslTarget="darwin64-x86_64" ;;
		*)
			error "No OpenSSL Configure target for ${ARCHS[0]}"
			exit 1
			;;
	esac

	# Configure takes compiler flags two ways and they must not be mixed: either as
	# bare arguments on the command line, or as environment variables, and INSTALL.md
	# says plainly that the environment is ignored the moment a bare flag appears.
	# The environment is the only one open to us, because log() splits its arguments
	# on whitespace and a CFLAGS="a b c" assignment would arrive as an assignment
	# followed by two bare flags - exactly the mixture that is forbidden.
	#
	# The prefix's own -I and -L come out of the flags first. Every other package
	# here wants them, this one must not have them: OpenSSL links nothing but
	# libSystem, and the headers it needs are its own. With -I$ROOTDIR/build/include
	# on the compile line, the next time a pin moves, the build would read the
	# openssl/*.h of the version it is replacing out of the prefix; with
	# -L$ROOTDIR/build/lib on the link line, the new libssl would link against the
	# old libcrypto sitting beside it.
	local opensslCFLAGS opensslLDFLAGS
	opensslCFLAGS=$(echo " $ARCH_CFLAGS " | sed \
		-e "s#-I$ROOTDIR/build/include##g" \
		-e "s#-L$ROOTDIR/build/lib##g")
	opensslLDFLAGS=$(echo " $ARCH_LDFLAGS " | sed \
		-e "s#-I$ROOTDIR/build/include##g" \
		-e "s#-L$ROOTDIR/build/lib##g")

	# make links, and make does not run inside the subshell that sets the flags.
	export MACOSX_DEPLOYMENT_TARGET="${MIN_OS_VERSION}"

	if needsconfigure $@; then
	(
		status "Configuring OpenSSL ${OPENSSL_VERSION}"
		export CFLAGS="$opensslCFLAGS"
		export LDFLAGS="$opensslLDFLAGS"
		# no-tests keeps a thousand test programs out of the build; no-docs keeps
		# the manual pages out of the prefix. Neither changes the libraries.
		# --libdir is spelled out because Configure's default is derived from the
		# platform and the rest of this tree assumes build/lib.
		#
		# --openssldir is the one option here that is not about this machine. Its
		# value is compiled into libcrypto as a string, and these two libraries are
		# committed to this repository and shipped inside Adium.app to other people,
		# so the obvious choice - a directory under the prefix - would carry the name
		# of whoever built them into a binary that strangers run, and would name a
		# path that on some other machine exists and belongs to someone else.
		# /private/etc/ssl is on every Mac and names nobody. no-autoload-config then
		# settles the question rather than moving it: libcrypto reads no
		# configuration file at all unless it is asked to, and nothing in this bundle
		# asks. Neither TDLib nor picomemo loads a config or fetches an algorithm
		# from a module; the default provider is compiled into libcrypto itself.
		# ENGINESDIR and MODULESDIR still follow --prefix, and nothing loads from
		# either.
		log ./Configure "$opensslTarget" \
			--prefix="$ROOTDIR/build" \
			--openssldir=/private/etc/ssl \
			--libdir=lib \
			shared \
			no-tests \
			no-docs \
			no-autoload-config

		# needsconfigure() asks whether there is a config.status here, which is an
		# autotools question. OpenSSL writes configdata.pm and no config.status at
		# all, so without this marker the answer would be yes on every run, and
		# every ./build.sh would reconfigure and therefore recompile the whole of
		# OpenSSL. Nothing reads the file - OpenSSL does not use the name - it only
		# answers the question the helper asks, and --configure still forces a fresh
		# configure because needsconfigure looks at FORCE_CONFIGURE first.
		echo "Written by phases/build_openssl.sh so that needsconfigure() can tell a configured tree from a fresh one. OpenSSL's own record is configdata.pm." \
			> config.status
	)
	fi

	status "Building and installing OpenSSL"
	log make -j $NUMBER_OF_CORES
	# install_sw and not install. The difference between them is install_ssldirs,
	# which creates OPENSSLDIR and writes an openssl.cnf into it - and OPENSSLDIR is
	# now /private/etc/ssl, which belongs to the system and already holds one. A
	# plain install would need root to do it and would be wrong if it got it.
	# install_sw is the libraries, the headers, the tool, pkg-config and cmake, which
	# is everything this tree wants.
	log make install_sw

	# If this ever fails, the shared-library version has moved and OPENSSL_SOVERSION
	# above is stale - which also means the file names the Xcode project and the
	# relink scripts under patches/ spell out have moved with it. Say so here rather
	# than three steps later.
	local path
	for path in "$ROOTDIR/build/lib/$cryptoLib" "$ROOTDIR/build/lib/$sslLib" ; do
		if [ ! -f "$path" ]; then
			error "OpenSSL installed no $(basename "$path"); the shared library version has moved"
			exit 1
		fi
	done

	status "Built $("$ROOTDIR/build/bin/openssl" version)"

	# Adium does not wrap these two in frameworks the way it wraps libpurple and
	# glib. They are copied flat into ../Frameworks and the application finds them
	# by @executable_path, which is the name the shipped copies already carry and
	# the name PurplePlugins/libtelegram-tdlib.so already asks for. Setting it here
	# means the wiring is a plain copy and no install_name_tool by hand.
	status "Naming the OpenSSL libraries for the bundle"
	log install_name_tool -id "$frameworksPath/$cryptoLib" "$ROOTDIR/build/lib/$cryptoLib"
	log install_name_tool -id "$frameworksPath/$sslLib" "$ROOTDIR/build/lib/$sslLib"
	log install_name_tool -change "$ROOTDIR/build/lib/$cryptoLib" \
		"$frameworksPath/$cryptoLib" "$ROOTDIR/build/lib/$sslLib"

	# Rewriting load commands invalidates the ad-hoc signature the linker put there,
	# and on arm64 dyld refuses to load an unsigned Mach-O. patches/tdlib-purple/
	# relink_for_bundle.sh signs again for the same reason.
	log codesign --force --sign - "$ROOTDIR/build/lib/$cryptoLib"
	log codesign --force --sign - "$ROOTDIR/build/lib/$sslLib"

	# That rewrite takes build/bin/openssl down with it if nothing else is done:
	# the tool loads libssl from the prefix, libssl now asks for libcrypto by the
	# bundle name, and dyld resolves @executable_path against the directory the
	# running program sits in, which is build/bin/../Frameworks. So give the prefix
	# that directory. Two symbolic links, and they buy two things: build/bin is
	# first on PATH for every configure script that runs after this one, and a
	# broken openssl sitting there is a trap; and the libraries now stand in the
	# same relative position they will have inside Adium.app, so the tool exercises
	# the names that ship.
	quiet mkdir -p "$ROOTDIR/build/Frameworks"
	log ln -sf "$ROOTDIR/build/lib/$cryptoLib" "$ROOTDIR/build/Frameworks/$cryptoLib"
	log ln -sf "$ROOTDIR/build/lib/$sslLib" "$ROOTDIR/build/Frameworks/$sslLib"

	# Asking it again is the check that the rewritten, re-signed libraries load.
	status "Successfully installed OpenSSL ($("$ROOTDIR/build/bin/openssl" version))"
	quiet popd
}
