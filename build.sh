#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

usage() {
	echo "Usage: build.sh <debug/release> <package>"
	exit 1
}

[ $# -lt 2 ] && usage

subcommand="$1"
package="$2"
shift 2

options=(
	-collection:common=common
    -error-pos-style:unix
    -out:out
)

case "$subcommand" in
    debug)   options+=(-debug) ;;
    release) options+=(-o:speed -microarch:native) ;;
    *)       usage ;;
esac

odin build "$package" "${options[@]}" "$@"

