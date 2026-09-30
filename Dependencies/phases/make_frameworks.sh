#!/bin/bash -eu

##
# prep_headers
#
prep_headers() {
	## purple prereqs
	quiet mkdir "${ROOTDIR}/build/lib/include" || true
	#libintl
	status "Staging libintl headers"
	local libintlDir="${ROOTDIR}/build/lib/include/libintl-${INTL_VERSION}"
	quiet mkdir "${libintlDir}" || true
	log cp "${ROOTDIR}/build/include/libintl.h" "${libintlDir}/"
	
	#glib
	status "Staging glib headers"
	local glibDir="${ROOTDIR}/build/lib/include/libglib-${GLIB_VERSION}.0"
	quiet mkdir "${glibDir}" || true
	log cp -R "${ROOTDIR}/build/include/glib-${GLIB_VERSION}" "${glibDir}"
	log cp "${ROOTDIR}/build/lib/glib-${GLIB_VERSION}/include/glibconfig.h" \
		"${glibDir}"
	
	#gmodule
	status "Staging gmodule headers"
	local gmoduleDir="${ROOTDIR}/build/lib/include/libgmodule-${GLIB_VERSION}.0"
	quiet mkdir "${gmoduleDir}" || true
	log cp "${ROOTDIR}/build/include/glib-${GLIB_VERSION}/gmodule.h" "${gmoduleDir}"
	
	#gobject
	status "Staging gobject headers"
	local gobjectDir="${ROOTDIR}/build/lib/include/libgobject-${GLIB_VERSION}.0"
	quiet mkdir "${gobjectDir}" || true
	log cp "${ROOTDIR}/build/include/glib-${GLIB_VERSION}/glib-object.h" "${gobjectDir}"
	log cp -R "${ROOTDIR}/build/include/glib-${GLIB_VERSION}/gobject/" "${gobjectDir}"
	
	#gthread
	status "Staging gthread non-headers"
	local gthreadDir="${ROOTDIR}/build/lib/include/libgthread-${GLIB_VERSION}.0"
	quiet mkdir "${gthreadDir}" || true
	touch "${gthreadDir}/no_headers_here.txt"
	
	if $BUILD_OTR; then
		# frameworkize.py looks for a framework's headers in build/lib/include under
		# the framework's own name, with the version appended when that version is
		# not A. All three of these are Versions/A, so the directory is the plain
		# name. The staged directory was libotr-4.1.1, a name nothing ever looked
		# for, and it held all three libraries' headers at once, so libgcrypt and
		# libgpgerror got none.
		#
		# What each one carries is what the application includes through it:
		# Adium.xcconfig puts all three Headers directories on the header search
		# path, the OTR sources say <libotr/context.h>, libotr's own headers say
		# <gcrypt.h>, and gcrypt.h says <gpg-error.h>.
	#libotr
		status "Staging libotr headers"
		local otrDir="${ROOTDIR}/build/lib/include/libotr"
		quiet rm -rf "${otrDir}"
		quiet mkdir -p "${otrDir}"
		log cp -R "${ROOTDIR}/build/include/libotr" "${otrDir}"

	#libgcrypt
		status "Staging libgcrypt headers"
		local gcryptDir="${ROOTDIR}/build/lib/include/libgcrypt"
		quiet rm -rf "${gcryptDir}"
		quiet mkdir -p "${gcryptDir}"
		log cp "${ROOTDIR}/build/include/gcrypt.h" "${gcryptDir}"
		# Gone since libgcrypt 1.7, which dropped the module API it declared
		if [ -f "${ROOTDIR}/build/include/gcrypt-module.h" ]; then
			log cp "${ROOTDIR}/build/include/gcrypt-module.h" "${gcryptDir}"
		fi
		log cp "${ROOTDIR}/build/include/gpg-error.h" "${gcryptDir}"

	#libgpgerror
		status "Staging libgpgerror headers"
		local gpgerrorDir="${ROOTDIR}/build/lib/include/libgpgerror"
		quiet rm -rf "${gpgerrorDir}"
		quiet mkdir -p "${gpgerrorDir}"
		log cp "${ROOTDIR}/build/include/gpg-error.h" "${gpgerrorDir}"
	else
		#json-glib
		status "Staging json-glib headers"
		local jsonDir="${ROOTDIR}/build/lib/include/libjson-glib-${JSON_GLIB_VERSION}.0"
		quiet rm -r "${jsonDir}" || true
		quiet mkdir "${jsonDir}" || true
		log cp -R "${ROOTDIR}/build/include/json-glib-${JSON_GLIB_VERSION}/json-glib" "${jsonDir}"
		

		#libpurple
		# One header the fork's own code includes is not a public one, so
		# libpurple's make install does not install it and it is not in
		# build/include. patches/pidgin-2.14.14/jabber adds stream management to
		# the jabber protocol, XEP-0198, and ESPurpleJabberAccount.m includes
		# <libpurple/stream_management.h> to reach it. Without this copy the
		# application fails to compile against a freshly built framework with
		# "file not found", while the framework that is committed in the tree has
		# the header, because someone put it there by hand. That is the kind of
		# difference that makes a fresh clone unbuildable, so the copy belongs here.
		#
		# The committed framework carries three more headers that install does not
		# install: oscar.h, peer.h and snactypes.h. Nothing in Adium has included
		# them since AIM went, so they are not copied and the new framework is that
		# much smaller.
		status "Staging the jabber stream management header"
		local jabberDir="${ROOTDIR}/source/libpurple/libpurple/protocols/jabber"
		if [ ! -f "${jabberDir}/stream_management.h" ]; then
			error "The jabber patches did not produce stream_management.h."
			error "Adium includes it, so the framework would not compile against."
			exit 1
		fi
		log cp "${jabberDir}/stream_management.h" "${ROOTDIR}/build/include/libpurple/"

		status "Staging libpurple headers"
		local purpleDir="${ROOTDIR}/build/lib/include/libpurple-${LIBPURPLE_VERSION}"
		quiet rm -rf "${purpleDir}"
		quiet mkdir "${purpleDir}"
		log cp -R "${ROOTDIR}/build/include/libpurple" "${purpleDir}"
		status "Completed staging headers"
	fi
}

##
# make_framework
#
make_framework() {
	FRAMEWORK_DIR="${ROOTDIR}/Frameworks"
	quiet mkdir "${FRAMEWORK_DIR}"
	
	status "Making the framework. If 'Done making framework!' is not displayed, check error.log."
	
	prep_headers
	
	log chmod +x "${ROOTDIR}/rtool/rtool"
	export PATH="${ROOTDIR}/rtool:$PATH"
	
	# resolve symlinks - rtool doesn't like lthem :(
	status "Resolving symlinks for frameworkize.py..."
	local files="${ROOTDIR}/build/lib/*.dylib"
	for file in ${files} ; do
		if [ -h ${file} ] ; then
			local resolvedLink=`/usr/bin/readlink -n ${file}`
			status "... ${file} -> ${ROOTDIR}/build/lib/${resolvedLink}"
			log rm "${file}"
			log cp "${ROOTDIR}/build/lib/${resolvedLink}" "${file}"
		fi
	done
	
	if $BUILD_OTR; then
		# The file is named after the library's own number, which is five, and not
		# after the release, which is 4.1.1. They have never been the same thing.
		# Which number it is does not matter to anything downstream, because
		# frameworkize.py pins all three OTR frameworks to Versions/A, so the file is
		# simply looked up the way the libpurple branch below looks its own up. It
		# used to be read off build/lib/libotr.dylib with readlink, but the loop
		# above has already replaced every symbolic link in build/lib with a copy, so
		# that readlink always failed and what ran was the fallback beside it, a hard
		# coded libotr.5.dylib.
		local otrLibPath
		otrLibPath="$(find "${ROOTDIR}/build/lib" -maxdepth 1 -type f -name 'libotr.*.dylib' ! -name 'libotr.dylib' | head -n 1)"
		if [ -z "${otrLibPath}" ]; then
			error "Could not find a built libotr dylib in ${ROOTDIR}/build/lib"
			exit 1
		fi
		status "Making a framework for libotr..."
		log python3 "${ROOTDIR}/framework_maker/frameworkize.py" \
			"${otrLibPath}" \
			"${FRAMEWORK_DIR}"

		# rtool copies the contents of what it is handed into Headers and keeps no
		# directory of its own, so libotr's eighteen headers land there loose. The
		# sources say #import <libotr/context.h> and Adium.xcconfig puts
		# libotr.framework/Headers on the header search path, so the directory is
		# what has to be there. Put it back, the way the libpurple branch below puts
		# libpurple's back.
		local otrHeaders="${FRAMEWORK_DIR}/libotr.subproj/libotr.framework/Versions/A/Headers"
		quiet rm -rf "${otrHeaders}"
		log ditto "${ROOTDIR}/build/include/libotr" "${otrHeaders}/libotr"

		log cp "${ROOTDIR}/Libotr-Info.plist" \
			"${FRAMEWORK_DIR}/libotr.subproj/libotr.framework/Resources/Info.plist"
	else
		local purpleLibPath
		purpleLibPath="$(find "${ROOTDIR}/build/lib" -maxdepth 1 -type f -name 'libpurple.*.dylib' ! -name 'libpurple.dylib' | head -n 1)"
		if [ -z "${purpleLibPath}" ]; then
			error "Could not find a built libpurple dylib in ${ROOTDIR}/build/lib"
			exit 1
		fi
		status "Making a framework for libpurple-${LIBPURPLE_VERSION} and all dependencies..."
		log python3 "${ROOTDIR}/framework_maker/frameworkize.py" \
			"${purpleLibPath}" \
			"${FRAMEWORK_DIR}"

		status "Adding the Adium framework header..."
		log cp "${ROOTDIR}/libpurple-full.h" \
			"${FRAMEWORK_DIR}/libpurple.subproj/libpurple.framework/Headers/libpurple.h"
		log ditto "${ROOTDIR}/build/include/libpurple" \
			"${FRAMEWORK_DIR}/libpurple.subproj/libpurple.framework/Headers"
		quiet mkdir -p "${FRAMEWORK_DIR}/libpurple.subproj/libpurple.framework/Headers/libpurple"
		log ditto "${ROOTDIR}/build/include/libpurple" \
			"${FRAMEWORK_DIR}/libpurple.subproj/libpurple.framework/Headers/libpurple"
		log cp "${ROOTDIR}/source/libpurple/config.h" \
			"${FRAMEWORK_DIR}/libpurple.subproj/libpurple.framework/Headers/config.h"
		log cp "${ROOTDIR}/source/libpurple/config.h" \
			"${FRAMEWORK_DIR}/libpurple.subproj/libpurple.framework/Headers/libpurple/config.h"

		log cp "${ROOTDIR}/Libpurple-Info.plist" \
			"${FRAMEWORK_DIR}/libpurple.subproj/libpurple.framework/Resources/Info.plist"
	fi
	
	status "Done making framework!"
}

##
# make_po_files
#
make_po_files() {
	PURPLE_RSRC_DIR="${ROOTDIR}/Frameworks/libpurple.subproj/libpurple.framework/Resources"
	
	status "Building libpurple po files"
	quiet pushd "${ROOTDIR}/source/libpurple/po"
		log make all
		log make install
	quiet popd
	
	status "Copy po files to framework"
	quiet pushd "${ROOTDIR}/build/share/locale"
		quiet mkdir "${PURPLE_RSRC_DIR}" || true
		log cp -v -r * "${PURPLE_RSRC_DIR}"
	quiet popd
	
	# What is being trimmed is every catalogue that belongs to a library rather than to
	# libpurple. make install in po/ copies the whole of build/share/locale, and every
	# package built before this one has put its own catalogues there. gdk-pixbuf is the
	# newest of them and the largest, 109 files and about two megabytes of messages
	# about image loaders that Adium never puts on screen: its only callers ask
	# gdk-pixbuf to draw a QR code and to list format names.
	status "Trimming the fat..."
	quiet pushd "${PURPLE_RSRC_DIR}"
		log find . \( -name gettext-runtime.mo -or -name gettext-tools.mo \
			-or -name glib20.mo -or -name gdk-pixbuf.mo \) -type f -delete

		# Deleting the files leaves the directories that held them, and a language
		# whose only catalogue was one of those is now an empty LC_MESSAGES inside
		# an otherwise empty language directory. Twice, because the inner one has
		# to go before the outer one is empty.
		log find . -type d -empty -delete
		log find . -type d -empty -delete
	quiet popd
	
	status "libpurple po files built!"
}

##
# stage_bundled_dylibs
#
# Seven libraries travel in Adium.app/Contents/Frameworks as bare dylibs rather than as
# frameworks: the two OpenSSL ones and the five image ones. frameworkize.py does not
# reach them, because it walks the dependency graph of libpurple and libpurple links
# none of them; their users are the protocol plug-ins, which are built outside this
# script. So nothing here produced them, and what sits in ../Frameworks today is a set
# of Homebrew bottles that were copied in by hand, relinked by hand and committed. The
# cost of that is measurable: every one of them is stamped for the macOS of the Mac that
# did the copying, which is why the tree ships libraries that require macOS 15 or macOS
# 26 while the application is built for 12.0.
#
# This is the step that closes the gap. It takes the libraries the recipes above have
# just built, gives them the names they must carry inside the bundle, and leaves them
# in Frameworks/dylibs for copy_frameworks.sh to place beside the frameworks.
#
# The rewriting happens here and not in the recipes for a reason worth keeping: an
# install name of @executable_path/../Frameworks/... cannot be resolved by anything
# running out of the prefix, and gdk-pixbuf's own install step runs the
# gdk-pixbuf-query-loaders it has just built. So the libraries keep their prefix names
# until they leave the prefix. OpenSSL is the exception, and stamps its own names,
# because build/bin/openssl has to keep working for the configure scripts that follow
# it; that recipe gives the prefix a Frameworks directory of symbolic links so that its
# tool still resolves them.
#
# A plain cp is deliberate. libtool and meson install the versioned name as the real
# file, but cmake does not: in build/lib, libjpeg.8.dylib is a symbolic link and
# libjpeg.8.3.2.dylib is the file. cp follows the link and writes a real file that
# already calls itself libjpeg.8.dylib, which is what has to ship. cp -a would copy the
# link and ship a dangling one.
#
BUNDLED_DYLIBS=(
	"libcrypto.${OPENSSL_SOVERSION:-3}.dylib"
	"libssl.${OPENSSL_SOVERSION:-3}.dylib"
	"libpng16.16.dylib"
	"libjpeg.8.dylib"
	"libwebp.7.dylib"
	"libsharpyuv.0.dylib"
	"libgdk_pixbuf-${GDK_PIXBUF_VERSION:-2.0}.0.dylib"
)

##
# bundled_dylib_target
#
# Where a dependency one of these libraries names ends up inside the bundle. Either it is
# one of the seven, and stays a bare dylib beside them, or it is a framework and is
# addressed the way frameworkize.py laid it out: libgobject-2.0.0.dylib becomes
# libgobject.framework/Versions/2.0.0/libgobject, and libintl.8.dylib, which separates
# its version with a dot rather than a dash, becomes libintl.framework/Versions/8/libintl.
#
bundled_dylib_target() {
	local base="$1"
	local candidate

	for candidate in "${BUNDLED_DYLIBS[@]}"; do
		if [ "${base}" = "${candidate}" ]; then
			echo "${base}"
			return 0
		fi
	done

	local stem="${base%.dylib}"
	local name="${stem%-*}"
	local version="${stem##*-}"
	if [ "${name}" = "${stem}" ]; then
		name="${stem%.*}"
		version="${stem##*.}"
	fi

	echo "${name}.framework/Versions/${version}/${name}"
}

stage_bundled_dylibs() {
	local stageDir="${ROOTDIR}/Frameworks/dylibs"
	quiet rm -rf "${stageDir}"
	quiet mkdir -p "${stageDir}"

	status "Staging the bundled dylibs"

	local name built
	for name in "${BUNDLED_DYLIBS[@]}"; do
		built="${ROOTDIR}/build/lib/${name}"
		if [ ! -f "${built}" ]; then
			error "${name} was not built. ${ROOTDIR}/build/lib holds no such library."
			exit 1
		fi
		log cp -f "${built}" "${stageDir}/${name}"
		log chmod u+w "${stageDir}/${name}"
		log install_name_tool -id "@executable_path/../Frameworks/${name}" "${stageDir}/${name}"
	done

	# Every reference that points at the prefix or at Homebrew becomes the copy that
	# travels in the bundle. A framework it names has to be one this build produced,
	# or the application launches and the plug-in that loads it does not.
	local dependency base target frameworkFile
	for name in "${BUNDLED_DYLIBS[@]}"; do
		while read -r dependency; do
			[ -n "${dependency}" ] || continue
			base="${dependency##*/}"
			target="$(bundled_dylib_target "${base}")"

			case "${target}" in
				*.framework/*)
					frameworkFile="${ROOTDIR}/Frameworks/${target%%.framework/*}.subproj/${target}"
					if [ ! -f "${frameworkFile}" ]; then
						error "${name} names ${dependency}, which would become ${target}."
						error "This build produced no such framework."
						exit 1
					fi
					;;
			esac

			log install_name_tool -change "${dependency}" \
				"@executable_path/../Frameworks/${target}" "${stageDir}/${name}"
		done < <(otool -L "${stageDir}/${name}" | tail -n +2 | awk '{print $1}' \
			| grep -E "${ROOTDIR}/build/lib/|/opt/homebrew/|/usr/local/opt/" || true)
	done

	# Nothing absolute may be left. A library that still names the build tree works on
	# this Mac and on no other, which is the failure that is hardest to notice.
	local leftover
	leftover=$(for name in "${BUNDLED_DYLIBS[@]}"; do
		otool -L "${stageDir}/${name}" | tail -n +2 | awk -v n="${name}" \
			'$1 ~ /^\/(Users|opt|usr\/local)\// {print n": "$1}'
	done)
	if [ -n "${leftover}" ]; then
		error "Absolute paths are left in the staged dylibs:"
		error "${leftover}"
		exit 1
	fi

	# Rewriting load commands invalidates the signature, and on arm64 dyld will not load
	# an unsigned Mach-O.
	for name in "${BUNDLED_DYLIBS[@]}"; do
		log codesign --force --sign - "${stageDir}/${name}"
	done

	status "Staged ${#BUNDLED_DYLIBS[@]} bundled dylibs in Frameworks/dylibs"
}
