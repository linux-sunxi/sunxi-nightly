#!/bin/sh

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

rebuild() {
	local branch="$1" name="$2"
	local d= dir=


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
		mkdir -p "$builddir"

		error=false
		for x in $defconfig uImage modules; do
			make -C "$BASE/$D" ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- \
				O="$BASE/$builddir" -j$JOBS \
				LOADADDR=0x40008000 \
				$x 2>&1 | tee -a $builddir.out
			if grep -q -e '\[sub-make\]' $builddir.out; then
				error=true
				break;
			fi
		done
		if $error; then
			mv $builddir.out $builddir.err
		else
			mv $builddir.out $builddir.log
		fi

	done
done
