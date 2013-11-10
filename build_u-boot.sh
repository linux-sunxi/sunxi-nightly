#!/bin/sh

CROSS_COMPILE=${CROSS_COMPILE:-arm-linux-gnueabi-}
JOBS=8

title() {
	echo "# $*"
}

main() {
	local builddir_base="$1" nightly_base="$2" NAME="$3"
	local log= error=
	local prefix=
	local rev=$(git rev-parse HEAD | sed -e 's/^\(.......\).*/\1/')
	local tstamp=$(date +%Y%m%dT%H%M%S)
	local nightly="$builddir_base/$NAME-$tstamp-$rev"

	mkdir -p "$nightly_base" "$nightly"

	for board in $(awk '/sun[4567x]i/ {print $7;}' boards.cfg); do
		name=$(echo "$board" | tr 'A-Z' 'a-z')
		builddir="$builddir_base/build_$name"
		log="$builddir"
		prefix=$NAME-$name
		error=false

		title "$prefix ($rev)"

		mkdir -p "$builddir"
		rm -f "$log.out"

		for x in ${board}_config all; do
			make CROSS_COMPILE=$CROSS_COMPILE \
				O="$builddir" -j$JOBS \
				"$x" >> $log.out 2>&1

			if [ $? -ne 0 ]; then
				error=true
				break
			fi
		done

		if $error; then
			mv "$log.out" "$nightly/$prefix.err.txt"
		else
			mv "$log.out" "$nightly/$prefix.build.txt"

			mkdir -p "$nightly/$prefix-$tstamp-$rev"

			spl="$builddir/spl"
			if [ -s "$spl/sunxi-spl.bin" ]; then
				cp "$spl/sunxi-spl.bin" "$nightly/$prefix-$tstamp-$rev/"
			elif [ -s "$spl/u-boot-spl.bin" ]; then
				# FEL case
				cp "$spl/u-boot-spl.bin" "$nightly/$prefix-$tstamp-$rev/"
			fi
			for x in u-boot.bin u-boot-sunxi-with-spl.bin;  do
				[ -s "$builddir/$x" ] || continue
				cp "$builddir/$x" "$nightly/$prefix-$tstamp-$rev/"
			done

			tar -C "$nightly" -vJcf "$nightly/$prefix.tar.xz" "$prefix-$tstamp-$rev" > "$nightly/$prefix.txt"
			rm -rf "$nightly/$prefix-$tstamp-$rev/"

			cd "$nightly"
			sha1sum -b "$prefix.tar.xz" > "$prefix.sha1"
			cd - > /dev/null
		fi
	done

	mv "$nightly" "$nightly_base/"
	ln -snf "$NAME-$tstamp-$rev" "$nightly_base/$NAME-latest"
}

main "$@"
