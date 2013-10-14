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

set -x

D=u-boot-sunxi.git
title "$D"
if [ ! -s $D/config ]; then
	git clone --mirror $GH/$D
else
	cd $D
	git remote update
	git remote prune origin
	cd - > /dev/null
fi

rm -f build_u-boot-*/.config build_uboot-*.{out,err,log}

for b in \
	sunxi \
	; do
	b2="$(echo "$b" | tr '/' '-' | sed -e 's|sunxi-||g' )"
	updated=false
	rev=
	D="u-boot-sunxi"
	if [ "$b2" != "sunxi" ]; then
		D="$D-$b2"
	fi

	title "$D"
	if [ ! -s $D/.git/config ]; then
		git clone -s u-boot-sunxi.git -b $b "$D" || continue
		cd "$D"
		rev="$(git rev-parse origin/$b)"
		update=tru
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
done

exec rsync -ai --delete-after nightly/u-boot-sunxi/ linux-sunxi.org:nightly/u-boot-sunxi/
