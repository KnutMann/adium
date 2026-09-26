#!/bin/bash -eu

##
# gpg-error
#
build_libgpgerror(){
	prereq "gpgerror" \
		"https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-1.61.tar.bz2"

	quiet pushd "${ROOTDIR}/source/gpgerror"
	
	if needsconfigure $@; then
	(
		status "Configuring libgpg-error"
		export CFLAGS="$ARCH_CFLAGS -Os"
		export LDFLAGS="$ARCH_LDFLAGS"
		log ./configure --prefix="$ROOTDIR/build" \
			--disable-shared \
			--enable-static \
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
# disable assembly to help build universal.
#
build_libgcrypt(){
	build_libgpgerror
	prereq "libgcrypt" \
		"https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.12.4.tar.bz2"

	quiet pushd "${ROOTDIR}/source/libgcrypt"
	
	if needsconfigure $@; then
	(
		status "Configuring libgcrypt"
		# Its own assembly for this processor does not get past Apple's
		# assembler: the aarch64 sources under mpi carry frame directives it
		# rejects outright, and the build stops with "Unfinished frame!" on
		# mpih-add1, mpih-sub1 and the three multiply routines. Built from C
		# instead, which is what every package manager on this platform does.
		log ./configure --prefix=$ROOTDIR/build \
			--enable-ciphers=arcfour:blowfish:cast5:des:aes:twofish:serpent:rfc2268 \
			--enable-pubkey-ciphers=dsa:elgamal:rsa \
			--enable-digests=crc:md4:md5:rmd160:sha1:sha256:sha512:tiger \
			--disable-asm \
			--disable-endian-check \
			--disable-dependency-tracking
	)
	fi


	status "Building and installing libgcrypt"
	log make -j $NUMBER_OF_CORES
	log make install
	
	status "Successfully installed libgcrypt"
	quiet popd
}

##
# Libotr
#
OTR_VERSION=4.1.1
build_otr(){
	build_libgcrypt
	prereq "otr" \
		"https://otr.cypherpunks.ca/libotr-4.1.1.tar.gz"

	quiet pushd "${ROOTDIR}/source/otr"

	if needsconfigure $@; then
	(
    # The release tarball brings its own configure script and needs no autotools
    # on the machine; only a source checkout has to raise one first.
    if [ ! -x ./configure ]; then
        status "Bootstrapping libotr"
        ./bootstrap
    fi
		status "Configuring libotr"
		export CFLAGS="$ARCH_CFLAGS -Os"
		export LDFLAGS="$ARCH_LDFLAGS"
		log ./configure --prefix="$ROOTDIR/build" \
			--disable-dependency-tracking
	)
	fi
	status "Building and installing libotr"
	log make -j $NUMBER_OF_CORES
	log make install

	status "Successfully installed libotr"
	quiet popd
}
