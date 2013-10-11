#!/bin/sh

cd "$(dirname $0)"

GH=https://github.com/linux-sunxi
BASE="$PWD"
CROSS_COMPILE=arm-linux-gnueabi-
JOBS=8

title() {
	echo "=== $* ==="
}
err() {
	echo "$*" >&2
}

D=linux-sunxi.git
title "$D"
if [ ! -s $D/config ]; then
	git clone --mirror $GH/$D
else
	cd $D
	git remote update
	git remote prune origin
	cd - > /dev/null
fi

rm -f build_linux-*/.config build_linux-*.{out,err,log}

for b in \
	sunxi-3.0 \
	sunxi-3.4 \
	stage/sunxi-3.0 \
	stage/sunxi-3.4 \
	experimental/sunxi-3.10 \
	sunxi-devel \
	; do
	b2="$(echo "$b" | tr '/' '-' | sed -e 's|sunxi-||g' )"
	D="linux-sunxi-$b2"
	updated=false

	case "$b2" in
	3.0|3.4|*-3.0|*-3.4)
		dtb=false
		;;
	*)
		dtb=true
		;;
	esac

	title "$D"
	if [ ! -s $D/.git/config ]; then
		git clone -s linux-sunxi.git -b $b "$D"
	else
		cd "$D"
		git remote update
		if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/$b)" ]; then
			updated=true
			git reset -q --hard "origin/$b"
		fi
		cd - > /dev/null
	fi

	$updated || continue

	for defconfig in $D/arch/arm/configs/sun?i*_defconfig \
		$D/arch/arm/configs/a[123][023]*_defconfig; do

		[ -s "$defconfig" ] || continue
		defconfig="${defconfig##*/}"
		if [ "$defconfig" != "sunxi_defconfig" ]; then
			name="$b2-${defconfig%_defconfig}"
		else
			name="$b2"
		fi
		builddir="build_linux-$name"
		nightly="nightly/linux-sunxi/linux-sunxi-$name"
		mkdir -p "$nightly" "$builddir"

		error=false
		for x in $defconfig uImage modules modules_install; do
			make -C "$BASE/$D" ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- \
				O="$BASE/$builddir" -j$JOBS \
				INSTALL_MOD_PATH=output \
				LOADADDR=0x40008000 \
				$x 2>&1 | tee -a $builddir.out
			if grep -q -e '\[sub-make\]' $builddir.out; then
				error=true
				break;
			fi
		done

		if $dtb; then
			# TODO: compile dtb files
			true
		fi

		tstamp=$(date +%Y%m%dT%H%M%S)
		prefix="linux-sunxi-$name-$tstamp"

		if $error; then
			mv $builddir.out "$nightly/$prefix.err.txt"
		else
			mv $builddir.out "$nightly/$prefix.build.txt"

			mv "$builddir/output" "$builddir/$prefix"
			mkdir -p "$builddir/$prefix/boot"
			cp "$builddir/arch/arm/boot/uImage" "$builddir/$prefix/boot"

			if $dtb; then
				# TODO: install dtb files
				true
			fi

			tar -C "$builddir" -vJcf "$nightly/$prefix.tar.xz" "$prefix" > "$nightly/$prefix.txt"

			cd "$nightly"
			sha1sum -b "$prefix.tar.xz" > "$prefix.sha1"

			for x in build.txt txt sha1 tar.xz; do
				ln -sf "$prefix.$x" "linux-sunxi-$name-latest.$x"
			done
			cd - > /dev/null
		fi
	done
done

exec rsync -ai --delete-after nightly/linux-sunxi/ linux-sunxi.org:nightly/linux-sunxi/
