#!/bin/sh

cd "$(dirname $0)"

for x in LANGUAGE LC_ALL LANG; do
	export $x=C
done

title() {
	cat <<-EOT
	#
	# $*
	#
	EOT
}

err() {
	echo "$*" >&2
}

get_prefix() {
	local name="$1" remote="$2"
	local prefix="$name"

	if [ -n "$remote" -a "$remote" != "origin" ]; then
		prefix="$prefix-$remote"
	fi

	echo "$prefix"
}

name2gitdir() {
	echo "$PWD/$(get_prefix "$1" "${2:-origin}").git"
}

clone() {
	local name="$1" url="$2" remote="${3:-origin}"
	local dir=$(name2gitdir "$name" "$remote")
	local refdir=$(name2gitdir "$name")
	
	title "${dir#$PWD/} <- $url"

	if [ -s "$dir/config" ]; then
		cd "$dir"
		git remote update -p
		cd - > /dev/null
	elif [ "$dir" != "$refdir" -a -s "$refdir/config" ]; then
		git clone --reference "$refdir" --mirror "$url" "$dir"
	else
		git clone --mirror "$url" "$dir"
	fi
}

push_nightly() {
	mkdir -p "nightly/$1/"
	rsync -ai --delete-after "nightly/$1/" "linux-sunxi.org:nightly/$1/"
}

#
# linux
#
build_linux() {
	err "build_linux $*"
}

N=linux-sunxi
clone $N https://github.com/linux-sunxi/$N.git

for b in \
	sunxi-3.0 \
	sunxi-3.4 \
	stage/sunxi-3.0 \
	stage/sunxi-3.4 \
	experimental/sunxi-3.10 \
	sunxi-devel \
	sunxi-next \
	; do

	build_linux "$N" origin "$b"
done

clone $N https://github.com/arokux/linux.git arokux
build_linux $N arokux sunxi-next-usb

push_nightly $N

#
# u-boot
#
N=u-boot-sunxi

build_uboot() {
	err "build_uboot $*"
}

clone $N https://github.com/linux-sunxi/$N.git
build_uboot $N origin sunxi

push_nightly $N
