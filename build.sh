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

name2dir() {
	local name="$1" remote="$2"
	local dir="$name"

	if [ -n "$remote" -a "$remote" != "origin" ]; then
		dir="$dir-$remote"
	fi

	echo "$dir.git"
}

clone() {
	local name="$1" url="$2" remote="${3:-origin}"
	local dir=$(name2dir "$name" "$remote")
	local refdir=$(name2dir "$name")
	
	title "$dir <- $url"

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

#
# linux
#
N=linux-sunxi
clone $N https://github.com/linux-sunxi/$N.git
clone $N https://github.com/arokux/linux.git arokux

#
# u-boot
#
N=u-boot-sunxi
clone $N https://github.com/linux-sunxi/$N.git
