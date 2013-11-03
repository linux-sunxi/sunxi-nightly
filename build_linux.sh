#!/bin/sh

CROSS_COMPILE=${CROSS_COMPILE:-arm-linux-gnueabi-}
JOBS=8

title() {
	cat <<-EOT
	#
	# $*
	#
	EOT
}

main() {
	local defconfig="$1" builddir="$2" nightly="$3" name="$4"
	local log="$builddir" error=
	local tstamp= prefix=
	local rev=$(git rev-parse HEAD | sed -e 's/^\(.......\).*/\1/')

	rm -f "$builddir/.config" "$log.out"
	mkdir -p "$nightly" "$builddir"

	title "$name ($rev)"

	error=false
	for x in $defconfig uImage modules modules_install dtbs; do
		case "$x" in
		dtbs)
			ls -1 arch/arm/boot/dts/sun?i*.dts > /dev/null 2>&1 || continue
			;;
		modules|modules_install)
			grep -q '^CONFIG_MODULES=y' "$builddir/.config" || continue
			;;
		esac

		make ARCH=arm CROSS_COMPILE=$CROSS_COMPILE \
			O="$builddir" -j$JOBS \
			INSTALL_MOD_PATH=output \
			LOADADDR=0x40008000 \
			$x 2>&1 | tee -a "$log.out"

		if [ $? -ne 0 ]; then
			error=true
		elif grep -q -e '\[sub-make\]' "$log.out"; then
			error=true
		fi

		if $error; then
			break
		fi
	done

	tstamp=$(date +%Y%m%dT%H%M%S)
	prefix="$name-$tstamp-$rev"

	if $error; then
		mv "$log.out" "$nightly/$prefix.err.txt"
	else
		mv "$log.out" "$nightly/$prefix.build.txt"

		if [ -d "$builddir/output" ]; then
			mv "$builddir/output" "$builddir/$prefix"
		fi

		mkdir -p "$builddir/$prefix/boot"
		cp "$builddir/arch/arm/boot/uImage" "$builddir/$prefix/boot"
		cp "$builddir/arch/arm/boot/dts"/*.dtb "$builddir/$prefix/boot"

		tar -C "$builddir" -vJcf "$nightly/$prefix.tar.xz" "$prefix" > "$nightly/$prefix.txt"
		gzip -c "$builddir/.config" > "$nightly/$prefix.config.gz"

		cd "$nightly"
		sha1sum -b "$prefix.tar.xz" > "$prefix.sha1"

		for x in build.txt txt sha1 config.gz tar.xz; do
			ln -sf "$prefix.$x" "$name-latest.$x"
		done
		cd - > /dev/null

		rm -rf "$builddir/$prefix/"
	fi
}

main "$@"
