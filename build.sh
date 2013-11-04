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
	local remote= prefix=
	local x=

	if [ $# = 0 ]; then
		:
	elif [ $# -eq 1 ]; then
		prefix="$1"
		shift
	elif [ $# -gt 1 ]; then
		prefix="$1"
		remote="$2"
		shift 2
	fi

	# prefix developer trees
	if [ -n "$remote" -a "$remote" != "origin" ]; then
		prefix="$prefix-$remote"
	fi

	# branches and extras
	for x; do
		x="$(echo "$x" | tr '/' '-' | sed -e 's|sunxi-||g' )"
		if [ -n "$x" -a "$x" != sunxi ]; then
			prefix="$prefix-$x"
		fi
	done

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

updated() {
	local refdir="$1" branch="$2" name="$3"
	local dir="$PWD/$name"
	local rev= ret=false

	title "$name"

	if [ ! -s "$dir/.git/config" ]; then
		git clone -q -s "$refdir" -b "$branch" "$dir"
		if [ -s "$dir/.git/config" ]; then
			ret=true
		fi
	else
		cd "$dir"
		git remote update
		rev="$(git rev-parse origin/$branch)"
		if [ "$(git rev-parse HEAD)" != "$rev" ]; then
			ret=true
			git reset -q --hard "origin/$b"
		fi
		cd - > /dev/null
	fi

	$ret
}

push_nightly() {
	mkdir -p "nightly/$1/"
	rsync -ai --delete-after "nightly/$1/" "linux-sunxi.org:nightly/$1/"
}

#
# linux
#
build_linux() {
	local name="$1" remote="$2" branch="$3" rev=
	local refdir=$(name2gitdir "$name" "$remote")
	local prefix=$(get_prefix "$name" "$remote" "$branch")
	local build_all=false build=
	local base="$PWD" prefix2= x=
	local builddir= nightly=

	if updated "$refdir" "$branch" "$prefix"; then
		build_all=true
	elif [ ! -s "$prefix/.git/config" ]; then
		return
	fi

	cd "$prefix"
	rev=$(git rev-parse HEAD | sed -e 's/^\(.......\).*/\1/')

	for defconfig in arch/arm/configs/sun?i*_defconfig \
		arch/arm/configs/a[123][023]*_defconfig; do

		[ -s "$defconfig" ] || continue
		defconfig="${defconfig##*/}"
		if [ "$defconfig" != "sunxi_defconfig" ]; then
			prefix2="$prefix-${defconfig%_defconfig}"
		else
			prefix2="$prefix"
		fi

		builddir="$base/build_$(echo $prefix2 | sed -e 's|-sunxi||g')"
		nightly="$base/nightly/$name/$prefix2"

		if $build_all; then
			build=true
		elif [ ! -d "$builddir" ]; then
			build=true
		else
			build=false
			x="$(ls -1 "$nightly/$prefix2"-*-$rev.{build,err}.txt 2> /dev/null |
				sed -ne "/$prefix2-[0123456789T]\+-$rev\..*\.txt/p" |
				sort | tail -n1 | grep '.err.txt$')"
			if [ -s "$x" ]; then
				if grep -q 'internal error, aborting at' "$x" ||
				   grep -q 'mali_osk_atomics.o: invalid string offset' "$x"; then
					build=true
				fi
			fi
		fi

		$build || continue

		"$base/build_linux.sh" "$defconfig" "$builddir" "$nightly" "$prefix2"
	done

	cd - > /dev/null
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
	local name="$1" remote="$2" branch="$3"
	local refdir=$(name2gitdir "$name" "$remote")
	local prefix=$(get_prefix "$name" "$remote" "$branch")
	local build=false
	local base="$PWD"

	local builddir="$base/build_$(echo $prefix | sed -e 's|-sunxi||g')"
	local nightly="$base/nightly/$name/$prefix"

	if updated "$refdir" "$branch" "$prefix"; then
		build=true
	elif [ ! -s "$prefix/.git/config" ]; then
		return
	elif [ ! -d "$builddir" ]; then
		build=true
	fi

	$build || return

	cd "$prefix"
	"$base/build_u-boot.sh" "$builddir" "$nightly" "$prefix"
	cd - > /dev/null
}

clone $N https://github.com/linux-sunxi/$N.git
build_uboot $N origin sunxi

clone $N https://github.com/arokux/$N.git arokux
build_uboot $N arokux sunxi-usb

push_nightly $N
