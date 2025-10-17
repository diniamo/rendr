#!/bin/sh
set -eu
cd "$(dirname "$0")"

COMMON_FLAGS="-collection:common=common/"
SPEED_FLAGS="-o:speed -microarch:native $COMMON_FLAGS"
DEBUG_FLAGS="-debug $COMMON_FLAGS"

usage() {
  echo 'Usage: build.sh <run/check/debug/time/bench <runs>> <raytracer/rasterizer/text> [odin args...]' 1>&2
  exit 1
}

[ "$#" -lt 2 ] && usage

command="$1"
shift

package="$1"
[ "$package" != "raytracer" -a "$package" != "rasterizer" -a "$package" != "text" ] && usage
shift

odin() {
  subcommand="$1"
  shift

  command odin "$subcommand" "$package" "$@"
}

hyperfine() {
  runs="$1"
  shift

  temp="$(mktemp)"
  odin build $SPEED_FLAGS "$@" -out:"$temp"
  command hyperfine --runs "$runs" -N "$temp"
  rm "$temp"
}

debug() {
  temp="$(mktemp)"
  odin build $DEBUG_FLAGS "$@" -out:"$temp"
  command nnd "$temp"
  rm "$temp"
}

case "$command" in
  run)   odin run $DEBUG_FLAGS "$@" ;;
  check) odin check $COMMON_FLAGS "$@" ;;
  debug) debug "$@" ;;
  time)  hyperfine 1 "$@" ;;
  bench) hyperfine "$@" ;;
  *)     fatal "Invalid subcommand: $command" ;;
esac
