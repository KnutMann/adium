#!/bin/bash -eu

##
# sniff_libpurple_version
#
# We pull libpurple from monotone, so we may not know the version number
# ahead of time
#
sniff_libpurple_version() {
	LIBPURPLE_VERSION=''
	while read LINE ; do
		local version=`expr "'${LINE}'" : '.* PURPLE_.*_VERSION (\([0-9]*\)).*'`
		if [[ '' != ${version} ]] ; then
			LIBPURPLE_VERSION="${LIBPURPLE_VERSION}.${version}"
		fi
	done < "${ROOTDIR}/source/libpurple/libpurple/version.h"
	LIBPURPLE_VERSION="0.${LIBPURPLE_VERSION:3}"
}

##
# fetch_libpurple
#
fetch_libpurple() {
	local libpurple_url="${LIBPURPLE_URL:-https://downloads.sourceforge.net/project/pidgin/Pidgin/2.14.14/pidgin-2.14.14.tar.bz2}"

	if [ -d "$ROOTDIR/source/libpurple" ]; then
		status "Using existing libpurple checkout in $ROOTDIR/source/libpurple"
		return 0
	fi

	prereq "libpurple" "${libpurple_url}"
}

##
# libpurple
#
build_libpurple() {
	if $DOWNLOAD_LIBPURPLE; then
	  fetch_libpurple
	fi
	if [ ! -d "$ROOTDIR/source/libpurple" ]; then
	  error "libpurple checkout not found; use --download-libpurple"
	  exit 1;
	fi
	
	prereq "cyrus-sasl" \
		"https://github.com/cyrusimap/cyrus-sasl/releases/download/cyrus-sasl-2.1.27/cyrus-sasl-2.1.27.tar.gz"
	
	# Copy the headers from Cyrus-SASL
	status "Copying headers from Cyrus-SASL"
	quiet mkdir -p "$ROOTDIR/build/include/sasl"
	log cp -f "$ROOTDIR/source/cyrus-sasl/include/"*.h "$ROOTDIR/build/include/sasl"
	
	quiet pushd "$ROOTDIR/source/libpurple"
	
	PROTOCOLS="bonjour,gg,irc,jabber,novell,"
	PROTOCOLS+="simple,zephyr"
	
	# Leopard's 64-bit Kerberos library is missing symbols, as evidenced by
	#    $ nm -arch x86_64 /usr/lib/libkrb4.dylib | grep krb_rd_req
	# So, only enable it on Snow Leopard or newer
	if [ "$(sysctl -b kern.osrelease | awk -F '.' '{ print $1}')" -ge 10 ]; then
		#KERBEROS="--with-krb4"
		warning "Kerberos support is disabled for unknown reasons (TBD by developers; this can be ignored for now)."
		KERBEROS=""
	else
		warning "Kerberos support is disabled for Leopard and earlier."
		KERBEROS=""
	fi
	
	if needsconfigure $@; then
	(
		status "Configuring libpurple"
		log cp -f /opt/homebrew/bin/intltool-extract /opt/homebrew/bin/intltool-merge /opt/homebrew/bin/intltool-update "$ROOTDIR/build/bin/"
		perl -0pi -e 's{^#!.*perl\n}{#!/usr/bin/perl\n}' "$ROOTDIR/build/bin/intltool-extract" "$ROOTDIR/build/bin/intltool-merge" "$ROOTDIR/build/bin/intltool-update"
		export PATH="$ROOTDIR/build/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$DEVELOPER/usr/bin:$DEVELOPER/usr/sbin"
		export ACLOCAL_FLAGS="-I $ROOTDIR/build/share/aclocal"
		export LIBXML_CFLAGS="-I/usr/include/libxml2"
		export LIBXML_LIBS="-lxml2"
		export MSGFMT="$ROOTDIR/build/bin/msgfmt"
		if [ -x "./configure" ]; then
			CONFIGURE_SCRIPT="./configure"
		else
			CONFIGURE_SCRIPT="./autogen.sh"
		fi
		CONFIG_CMD="${CONFIGURE_SCRIPT} \
				--disable-dependency-tracking \
				--disable-gtkui \
				--disable-consoleui \
				--disable-perl \
				--disable-tcl \
				--enable-debug \
				--disable-static \
				--enable-shared \
				--enable-cyrus-sasl \
				--prefix=$ROOTDIR/build \
				--with-static-prpls=$PROTOCOLS \
				--disable-meanwhile \
				--disable-avahi \
				--disable-dbus \
				--enable-gnutls=no \
				--enable-nss=no \
				--enable-vv=no \
				--disable-gstreamer \
				--disable-idn \
				$KERBEROS"
		xconfigure "$BASE_CFLAGS -I/usr/include/kerberosIV -DHAVE_SSL \
			        -DHAVE_OPENSSL -fno-common -DHAVE_ZLIB" \
			"$BASE_LDFLAGS -lsasl2 -ljson-glib-1.0 -lz" \
			"${CONFIG_CMD}" \
			"${ROOTDIR}/source/libpurple/libpurple/purple.h" \
			"${ROOTDIR}/source/libpurple/config.h"
	)
	fi
	
	status "Building and installing libpurple"
	log make -j $NUMBER_OF_CORES
	log make install

	# Loadable-plugin support is enabled for third-party prpls, but the
	# stock pidgin convenience plugins installed into lib/purple-2 must
	# not exist: libpurple probes this baked-in path at startup and would
	# load a second copy of the entire library stack into Adium.
	status "Removing stock libpurple plugins"
	log rm -rf "$ROOTDIR/build/lib/purple-2"
	
	status "Copying internal libpurple headers"
	log cp -f "$ROOTDIR/source/libpurple/libpurple/cmds.h" \
		  "$ROOTDIR/source/libpurple/libpurple/internal.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/gg/buddylist.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/gg/gg.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/gg/search.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/jabber/auth.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/jabber/bosh.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/jabber/buddy.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/jabber/caps.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/jabber/chat.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/jabber/jutil.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/jabber/presence.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/jabber/si.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/jabber/jabber.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/jabber/iq.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/jabber/namespaces.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/irc/irc.h" \
		  "$ROOTDIR/source/libpurple/libpurple/protocols/gg/lib/libgadu.h" \
		  "$ROOTDIR/build/include/libpurple"
	
	status "Successfully installed libpurple"
	quiet popd
	sniff_libpurple_version
}
