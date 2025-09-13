#!/bin/sh
set -eu
cd "$(dirname "$0")"

usage() {
  echo 'Usage: build.sh <build/run/time> <raytracer/rasterizer> [odin args...]' 1>&2
  exit 1
}

[ "$#" -lt 2 ] && usage

command="$1"
shift

package="$1"
[ "$package" != "raytracer" -a "$package" != "rasterizer" ] && usage
shift

odin() {
  subcommand="$1"
  shift

  command odin "$subcommand" "$package" \
    -collection:common=common/ \
    -o:speed \
    "$@"
}

hyperfine() {
  runs="$1"
  shift

  temp="$(mktemp)"
  odin build "$@" -out:"$temp"
  command hyperfine --runs "$runs" -N "$temp"
  rm "$temp"
}

case "$command" in
  build) odin build "$@" ;;
  time)  hyperfine 1 "$@" ;;
  run)   odin run "$@" ;;
  bench) hyperfine 10 "$@" ;;
  *) fatal "Invalid subcommand: $command" ;;
esac
