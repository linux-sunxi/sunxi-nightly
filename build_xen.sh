#!/bin/sh

CROSS_COMPILE=${CROSS_COMPILE:-arm-linux-gnueabi-}
JOBS=8

title() {
	echo "# $*"
}

main() {
	local builddir="$1" nightly="$2" name="$3" suffix="$4" dtb="$5"
	local log="$builddir" error=
	local tstamp= prefix=
	local rev=$(git rev-parse HEAD | sed -e 's/^\(.......\).*/\1/')
	local XEN_ROOT="$PWD"

	rm -f "$log.out"
	mkdir -p "$nightly" "$builddir"

	title "$name ($rev)"

	error=false

	make -j$JOBS distclean > $log.out 2>&1
	make -j$JOBS dist-xen \
		XEN_TARGET_ARCH=arm32 CROSS_COMPILE=$CROSS_COMPILE \
		CONFIG_EARLY_PRINTK=${suffix%%-*} CONFIG_DTB_FILE=$dtb >> $log.out 2>&1

	if [ $? -ne 0 ]; then
		error=true
	else
		mkimage -A arm -T kernel \
			-a 0x40200000 -e 0x40200000 \
			-C none -d "xen/xen" xen-uImage >> $log.out 2>&1 ||
			error=true
	fi

	tstamp=$(date +%Y%m%dT%H%M%S)
	prefix="$name-$tstamp-$rev"

	if $error; then
		mv "$log.out" "$nightly/$prefix.err.txt"
	else
		mv "$log.out" "$nightly/$prefix.build.txt"

		mkdir -p "$builddir/$prefix"
		mv xen-uImage "$builddir/$prefix"

		tar -C "$builddir" -vJcf "$nightly/$prefix.tar.xz" "$prefix" | sort > "$nightly/$prefix.txt"

		cd "$nightly"
		sha1sum -b "$prefix.tar.xz" > "$prefix.sha1"

		for x in build.txt txt sha1 tar.xz; do
			ln -sf "$prefix.$x" "$name-latest.$x"
		done
		cd - > /dev/null

		rm -rf "$builddir/$prefix/"
	fi
}

main "$@"
