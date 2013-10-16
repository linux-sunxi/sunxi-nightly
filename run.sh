#!/bin/sh

cd "$(dirname $0)"
exec >> run.out
exec 2>&1

cat <<EOT
===
=== $(date)
==

EOT

./build_u-boot.sh
exec ./build_linux.sh
