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
		x="$(echo "$x" | tr '/' '-' | sed -e 's|sunxi[-_]||g' )"
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
	local rev0= rev1= ret=false

	title "$name"

	if [ ! -s "$dir/.git/config" ]; then
		git clone -q -s "$refdir" -b "$branch" "$dir"
		if [ -s "$dir/.git/config" ]; then
			ret=true
		fi
	else
		cd "$dir"
		rev0=$(git rev-parse HEAD)
		git fetch origin
		rev1="$(git rev-parse origin/$branch)"
		if [ "$rev0" != "$rev1" ]; then
			ret=true
			git reset -q --hard "origin/$branch"
		fi
		git remote update
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
		prefix2="$(echo ${defconfig%_defconfig} |
			sed -e 's/sunxi[_-]//g' -e 's/sunxi$//')"
		prefix2="$prefix${prefix2:+-$prefix2}"

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
	experimental/sunxi-3.14 \
	sunxi-devel \
	sunxi-next \
	; do

	build_linux "$N" origin "$b"
done

clone $N https://github.com/arokux/linux.git arokux
build_linux $N arokux sunxi-next-usb

clone $N https://github.com/bjzhang/linux-allwinner.git bjzhang
build_linux $N bjzhang sun7i-xen-dom0
build_linux $N bjzhang sun7i_xen_domU

push_nightly $N

#
# u-boot
#
N=u-boot-sunxi

simple_build() {
	local builder="$1"
	local name="$2" remote="$3" branch="$4"

	shift 4

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
	"$builder" "$builddir" "$nightly" "$prefix" "$@"
	cd - > /dev/null
}

build_uboot() {
	simple_build "$PWD/build_u-boot.sh" "$@"
}

clone $N https://github.com/linux-sunxi/$N.git
build_uboot $N origin sunxi

clone $N https://github.com/arokux/$N.git arokux
build_uboot $N arokux sunxi-usb

clone $N https://github.com/bjzhang/$N.git bjzhang
build_uboot $N bjzhang sunxi_hyp

push_nightly $N

#
# xen
#
N=xen-sunxi

_build_xen() {
	local builddir="$1" nightly="$2" name="$3" base="$4"
	local x= y=
	for x in $base/build_linux-bjzhang-sun7i-xen-dom0-sun7i_dom0/arch/arm/boot/dts/*-xen.dtb; do
		[ -s "$x" ] || continue

		y="${x##*/}"
		y="${y%-xen.dtb}"

		"$base/build_xen.sh" "$builddir/build_$y" "$nightly/$name-$y" "$name-$y" "$y" "$x"
	done
}

build_xen() {
	simple_build "_build_xen" "$@" "$PWD"
}

clone $N git://xenbits.xen.org/xen.git
build_xen $N origin master

push_nightly $N
