#!/bin/sh

cd "$(dirname $0)"

GH=https://github.com/linux-sunxi
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

D=$NAME.git
title "$D"
if [ ! -s $D/config ]; then
	git clone --mirror $GH/$D
else
	cd $D
	git remote update
	git remote prune origin
	cd - > /dev/null
fi

rm -f $BUILD-*/.config $BUILD-*.{out,err,log}

for b in \
	sunxi \
	; do
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

done

exec rsync -ai --delete-after nightly/$NAME/ linux-sunxi.org:nightly/$NAME/
