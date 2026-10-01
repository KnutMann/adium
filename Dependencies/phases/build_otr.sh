#!/bin/bash -eu

##
# The OTR corner of the bundle: libgpg-error, libgcrypt and libotr.
#
# Everything here is built from the release tarballs at gnupg.org and
# otr.cypherpunks.ca. The three frameworks under ../Frameworks used to be copies
# taken out of Homebrew instead, which is why the libgcrypt we shipped carried
# every cipher and digest the project has and was stamped for whatever macOS the
# Mac that copied it happened to run. What is built here is deliberately smaller:
# libotr asks libgcrypt for AES in counter mode, SHA-1, SHA-256, HMAC over both,
# and DSA, and for nothing else. The note above build_libgcrypt says which
# algorithms that leaves out and which three had to stay in regardless.
#
# The three version numbers live in one place each so that moving a pin is one
# edit and prereq() notices it (it compares the URL it fetched from).
#
# The file names these three install carry each library's own number rather than
# its release: libgpg-error.0.dylib, libgcrypt.20.dylib, libotr.5.dylib. The
# frameworks the application links are libgpgerror.framework, libgcrypt.framework
# and libotr.framework, all three with a Versions/A. frameworkize.py holds that
# mapping, in FRAMEWORK_NAME_OVERRIDES, so what make_framework writes is a drop in
# replacement for what sits in ../Frameworks and no project file has to be touched
# when one of these numbers moves.
#
LIBGPGERROR_VERSION=1.61
LIBGCRYPT_VERSION=1.12.4
OTR_VERSION=4.1.1

##
# gpg-error
#
# Built as a shared library as well as a static one. It was static only, which
# meant there was no libgpg-error dylib for libgcrypt to link against and none
# for make_framework to wrap, and the libgpgerror.framework we ship therefore
# could not have come from here.
#
# Native language support is switched off on purpose. It is the one knob in this
# file whose answer depends on what happens to be installed: with NLS on, the
# library links libintl when gettext has been built before it and quietly does
# not when it has not, so the same script produced two different libraries.
# Nothing is lost by it. The Homebrew copy we ship has NLS compiled in, and the
# directory it was told to read its catalogues from is
# /opt/homebrew/Cellar/libgpg-error/1.61/share/locale, which is not inside the
# bundle and is not on a user's Mac, so it has never translated a word either.
# Dropping it also drops three load commands: libintl, and the CoreFoundation
# and CoreServices that come with it.
#
build_libgpgerror(){
	prereq "gpgerror" \
		"https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-${LIBGPGERROR_VERSION}.tar.bz2" \
		"7a85413f2bc354f4f8aa832b718af122e48965e9e0eb9012ee659c13c6385c93"

	quiet pushd "${ROOTDIR}/source/gpgerror"

	# libtool reads this when it links, which happens during make and therefore
	# outside the subshell below. build.sh puts the minimum into BASE_CFLAGS and
	# BASE_LDFLAGS but does not export it, so each function here sets it itself.
	export MACOSX_DEPLOYMENT_TARGET="${MIN_OS_VERSION}"

	if needsconfigure $@; then
	(
		status "Configuring libgpg-error"
		export CFLAGS="$ARCH_CFLAGS -Os"
		export LDFLAGS="$ARCH_LDFLAGS"
		log ./configure --prefix="$ROOTDIR/build" \
			--enable-shared \
			--enable-static \
			--disable-nls \
			--disable-languages \
			--disable-doc \
			--disable-tests \
			--disable-dependency-tracking
	)
	fi

	status "Building and installing gpg-error"
	log make -j $NUMBER_OF_CORES
	log make install

	status "Successfully installed gpgerror"
	quiet popd
}

##
# gcrypt
#
# The selection below is not an old habit, it is what libotr reaches for, taken
# from its sources rather than guessed:
#
#   cipher    AES, always through GCRY_CIPHER_MODE_CTR
#   digest    SHA-1 and SHA-256, both also with GCRY_MD_FLAG_HMAC
#   pubkey    DSA, for the long term key and for gcry_pk_genkey
#   plus      the MPI, S-expression and random layers, which are not optional
#
# SHA-1 is needed twice over: libgcrypt's own generator mixes its pool with it
# (random/random-csprng.c calls _gcry_sha1_mixblock), so switching SHA-1 off
# would take the random numbers with it. RIPEMD-160, MD4, MD5, CRC, Tiger,
# SHA-512, Arcfour, Blowfish, CAST5, 3DES, Twofish, Serpent, RFC2268, ElGamal and
# RSA are surplus to libotr; they are kept because narrowing the list further is
# a change nobody asked for and because the list below already had them.
#
# Three entries are here for libgcrypt's sake rather than libotr's: sha3, blake2
# and ecc. The library is not as modular as its configure switches suggest, and
# in 1.12.4 its own objects reach for algorithms that cannot be switched off,
# whatever the lists say. Read off the object files rather than the sources:
#
#   cipher/kdf.o        _gcry_digest_spec_blake2b_512 and the three SHA-3 specs
#   cipher/md.o         the same, plus _gcry_cshake_customize
#   cipher/pubkey.o     _gcry_pk_ecc_get_sexp
#   src/visibility.o    _gcry_mpi_ec_new, _gcry_ecc_mul_point and one more
#   mpi/ec.o            seven _gcry_ecc_* point and scalar helpers
#   cipher/kem.o        five more, for the key encapsulation front end
#
# Left out of them, libgcrypt still links, because libtool on this platform
# resolves what it cannot see at load time instead of refusing; and it still
# installs, because nothing here loads it. It simply does not run: the first
# process that maps it dies before main with "symbol not found in flat
# namespace: __gcry_digest_spec_blake2b_512", since a missing data symbol is
# bound eagerly. The library this recipe produced before these three were added
# has that defect, and so does the one sitting in Dependencies/build today,
# which is one more reason the frameworks we ship were copied from Homebrew.
#
# What is still left out of the full library, and what libotr names nowhere:
# Camellia, ChaCha20, Salsa20, SEED, IDEA, GOST28147, SM4 and ARIA; Whirlpool,
# Stribog, GOST R 34.11-94, MD2 and SM3; and Kyber and Dilithium keys.
#
build_libgcrypt(){
	build_libgpgerror
	prereq "libgcrypt" \
		"https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-${LIBGCRYPT_VERSION}.tar.bz2" \
		"d77f68f48879510e79a2f65977ccc68981781ea0923e5bdffac2a193ea3d660e"

	quiet pushd "${ROOTDIR}/source/libgcrypt"

	# See the note in build_libgpgerror: make links, and make does not run in the
	# subshell that sets the flags.
	export MACOSX_DEPLOYMENT_TARGET="${MIN_OS_VERSION}"

	if needsconfigure $@; then
	(
		status "Configuring libgcrypt"
		# Its neighbours in this file export these two and it did not, which is why the
		# dylib it produced was the only one here stamped for the running macOS rather
		# than for MIN_OS_VERSION.
		#
		# The extra warning switch is not cosmetic. BASE_CFLAGS in build.sh carries a
		# -L, which clang reports as an unused argument whenever it only compiles, and
		# seven of libgcrypt's configure probes append -Werror to CFLAGS and ask the
		# compiler a question. With the -L in there every one of those seven answered
		# "no" for the wrong reason: the aligned, packed, may_alias, optimize, ms_abi
		# and sysv_abi attributes, and thread local storage. The last of them is the
		# one that shows: fips.c then stops the build outright with "libgcrypt
		# requires thread-local storage to support FIPS mode". The other six went
		# through silently and gave us a library built without its own alignment and
		# aliasing attributes. With the switch, config.h now carries
		# HAVE_GCC_ATTRIBUTE_ALIGNED, _PACKED and _MAY_ALIAS; optimize, ms_abi and
		# sysv_abi stay off because clang really does not have them.
		export CFLAGS="$ARCH_CFLAGS -Os -Wno-unused-command-line-argument"
		export LDFLAGS="$ARCH_LDFLAGS"
		# Its own assembly for this processor does not get past Apple's
		# assembler: the aarch64 sources under mpi carry frame directives it
		# rejects outright, and the build stops with "Unfinished frame!" on
		# mpih-add1, mpih-sub1 and the three multiply routines. Built from C
		# instead, which is what every package manager on this platform does.
		#
		# --with-libgpg-error-prefix points it at the one we just built. Without
		# it, configure runs whichever gpgrt-config is first on PATH, and on a
		# Mac with Homebrew that is Homebrew's.
		log ./configure --prefix=$ROOTDIR/build \
			--enable-shared \
			--with-libgpg-error-prefix="$ROOTDIR/build" \
			--enable-ciphers=arcfour:blowfish:cast5:des:aes:twofish:serpent:rfc2268 \
			--enable-pubkey-ciphers=dsa:elgamal:rsa:ecc \
			--enable-digests=crc:md4:md5:rmd160:sha1:sha256:sha512:tiger:sha3:blake2 \
			--disable-asm \
			--disable-endian-check \
			--disable-doc \
			--disable-dependency-tracking
	)
	fi


	status "Building and installing libgcrypt"
	log make -j $NUMBER_OF_CORES
	log make install

	# A narrowed libgcrypt that refers to something it did not build links and
	# installs without complaint and only fails when a process maps it, which is
	# in Adium rather than here. Say so here instead. Every internal name begins
	# with _gcry_, which Mach-O writes as __gcry_; the library's own dependencies
	# are libgpg-error and libSystem, and neither owns a name in that shape.
	local dangling
	dangling=$(nm -u "$ROOTDIR/build/lib/libgcrypt.dylib" \
		| grep -E '^__gcry_|^_blake2b_|^_reverse_buffer$|^_aria_' || true)
	if [ -n "$dangling" ]; then
		error "libgcrypt was built without algorithms its own sources still call:"
		echo "$dangling" | sed 's/^/    /' 1>&2
		error "Widen --enable-digests or --enable-pubkey-ciphers above until this is empty."
		exit 1
	fi

	status "Successfully installed libgcrypt"
	quiet popd
}

##
# Libotr
#
build_otr(){
	build_libgcrypt
	prereq "otr" \
		"https://otr.cypherpunks.ca/libotr-${OTR_VERSION}.tar.gz" \
		"8b3b182424251067a952fb4e6c7b95a21e644fbb27fbd5f8af2b2ed87ca419f5"

	# Two declarations in libotr's own headers say () where they mean (void), and the
	# headers travel in the framework, so every file that includes <libotr/context.h>
	# collects a -Wstrict-prototypes warning: ten of them in a Release build. The
	# framework committed in this tree does not have the problem, because somebody
	# edited the two lines in place after it was built, and that edit was in no
	# recipe. See patches/libotr-4.1.1/README.
	if [ -d "$ROOTDIR/patches/libotr-${OTR_VERSION}" ] && \
	   [ ! -f "$ROOTDIR/source/otr/.adium-otr-patches-applied" ]; then
		status "Applying Adium libotr patches"
		for otr_patch in "$ROOTDIR/patches/libotr-${OTR_VERSION}/"*.patch; do
			patch -d "$ROOTDIR/source/otr" -p1 -N < "$otr_patch"
		done
		touch "$ROOTDIR/source/otr/.adium-otr-patches-applied"
	fi

	quiet pushd "${ROOTDIR}/source/otr"

	# See the note in build_libgpgerror.
	export MACOSX_DEPLOYMENT_TARGET="${MIN_OS_VERSION}"

	if needsconfigure $@; then
	(
    # The release tarball brings its own configure script and needs no autotools
    # on the machine; only a source checkout has to raise one first.
    if [ ! -x ./configure ]; then
        status "Bootstrapping libotr"
        ./bootstrap
    fi
		status "Configuring libotr"
		# The same trap as in libgcrypt, and here it costs the hardening. libotr
		# turns --enable-gcc-hardening and --enable-linker-hardening on by itself
		# and then asks the compiler whether it accepts each flag, compiling a tiny
		# program with -pedantic -Werror. Every one of those ten questions was
		# answering no, for two reasons stacked on top of each other: the stray -L
		# in BASE_CFLAGS, as in libgcrypt, and the test program itself, which
		# autoconf still writes as "main ()" and which clang now rejects under
		# -pedantic as a function declaration without a prototype. So
		# -fstack-protector-all, -Wstack-protector, -fwrapv, -fno-strict-overflow,
		# -Wall, -Wextra, -Wformat-security, ssp-buffer-size, -fPIE and -pie were
		# all quietly dropped from a library whose whole job is to take bytes from
		# strangers. Only plain -fstack-protector survived, and only because
		# build.sh puts it in BASE_CFLAGS. Silencing the two warnings about the test
		# program's own shape lets all ten through; measured afterwards, the library
		# builds without a new warning and grows from 96 to 112 kilobytes.
		export CFLAGS="$ARCH_CFLAGS -Os -Wno-unused-command-line-argument \
			-Wno-strict-prototypes -Wno-deprecated-non-prototype"
		export LDFLAGS="$ARCH_LDFLAGS"
		# Same reason as libgcrypt's prefix above: libgcrypt-config is a name
		# Homebrew also owns, and the one in our own build directory is the one
		# that describes the library we are about to link against.
		log ./configure --prefix="$ROOTDIR/build" \
			--with-libgcrypt-prefix="$ROOTDIR/build" \
			--disable-dependency-tracking
	)
	fi
	status "Building and installing libotr"
	log make -j $NUMBER_OF_CORES
	log make install

	status "Successfully installed libotr"
	quiet popd
}
