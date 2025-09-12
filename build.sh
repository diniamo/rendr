#!/bin/sh
set -eu
cd "$(dirname "$0")"

usage() {
  echo 'Usage: build.sh <build/run/time> raytracer [odin args...]' 1>&2
  exit 1
}

[ "$#" -lt 2 ] && usage

command="$1"
shift

package="$1"
[ "$package" != "raytracer" ] && usage
shift

odin() {
  subcommand="$1"
  shift

  command odin "$subcommand" "$package" \
    -collection:common=common/ \
    -o:speed \
    "$@"
}

case "$command" in
  build) odin build "$@" ;;
  run)   odin run "$@" ;;
  time)
    temp="$(mktemp)"
    odin build -out:"$temp" "$@"
    hyperfine --runs 1 -N "$temp"
    rm "$temp"
    ;;
  *) fatal "Invalid subcommand: $command" ;;
esac
