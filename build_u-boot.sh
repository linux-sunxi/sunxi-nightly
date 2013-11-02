#!/bin/sh

cd "$(dirname $0)"

BASE="$PWD"
CROSS_COMPILE=arm-linux-gnueabi-
JOBS=8

NAME=u-boot-sunxi
BUILD=build_u-boot

title() {
	echo "=== $* ==="
}
err() {
	echo "$*" >&2
}

rm -f $BUILD-*/.config $BUILD-*.{out,err,log}

	b2="$(echo "$b" | tr '/' '-' | sed -e 's|sunxi-||g' )"
	D="$NAME"
	if [ "$b2" != "sunxi" ]; then
		D="$D-$b2"
	fi
	updated=false
	rev=

	title "$D"
	if [ ! -s $D/.git/config ]; then
		git clone -s $NAME.git -b $b "$D" || continue
		cd "$D"
		rev="$(git rev-parse origin/$b)"
		update=true
		cd - > /dev/null
	else
		cd "$D"
		git remote update
		rev="$(git rev-parse origin/$b)"
		if [ "$(git rev-parse HEAD)" != "$rev" ]; then
			updated=true
			git reset -q --hard "origin/$b"
		fi
		cd - > /dev/null
	fi

	$updated || continue

	tstamp=$(date +%Y%m%dT%H%M%S)
	rev=$(echo $rev | sed -e 's/^\(.......\).*/\1/')

	builddir_base=$BUILD"${D##$NAME}"
	nightly=$builddir_base/$D-$tstamp-$rev

	mkdir -p "$nightly"

	for board in $(grep sun.i $D/boards.cfg | awk '{ print $7; }'); do
		name=$(echo "$board" | tr 'A-Z' 'a-z')
		log=$builddir_base-$name
		builddir=${builddir_base}/$name
		prefix=$D-$name
		error=false

		title "$prefix"

		mkdir -p "$builddir"

		for x in ${board}_config all; do
			make -C "$BASE/$D" CROSS_COMPILE=$CROSS_COMPILE \
				O="$BASE/$builddir" -j$JOBS \
				"$x" >> $log.out 2>&1

			if [ $? -ne 0 ]; then
				error=true
				break
			fi
		done

		if $error; then
			mv $log.out "$nightly/$prefix.err.txt"
		else
			mv $log.out "$nightly/$prefix.build.txt"

			mkdir -p "$nightly/$prefix-$tstamp-$rev"

			spl="$builddir/spl"
			if [ -s "$spl/sunxi-spl.bin" ]; then
				mv "$spl/sunxi-spl.bin" "$nightly/$prefix-$tstamp-$rev/"
			elif [ -s "$spl/u-boot-spl.bin" ]; then
				# FEL case
				mv "$spl/u-boot-spl.bin" "$nightly/$prefix-$tstamp-$rev/"
			fi
			for x in u-boot.bin u-boot-sunxi-with-spl.bin;  do
				[ -s "$builddir/$x" ] || continue
				mv "$builddir/$x" "$nightly/$prefix-$tstamp-$rev/"
			done

			tar -C "$nightly" -vJcf "$nightly/$prefix.tar.xz" "$prefix-$tstamp-$rev" > "$nightly/$prefix.txt"
			rm -rf "$nightly/$prefix-$tstamp-$rev/"

			cd "$nightly"
			sha1sum -b "$prefix.tar.xz" > "$prefix.sha1"
			cd - > /dev/null
		fi
	done

	mv "$nightly" "nightly/$NAME/"
	ln -snf "$D-$tstamp-$rev" "nightly/$NAME/$D-latest"
