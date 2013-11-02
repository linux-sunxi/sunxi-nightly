#!/bin/sh

cd "$(dirname $0)"
exec >> run.out
exec 2>&1

cat <<EOT
===
=== $(date)
===

EOT

exec ./build.sh
