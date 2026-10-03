#!/bin/sh
# Runs `swift` from a pinned Linux toolchain, fetching it once, so CindyCore can be built and
# tested on a Linux machine with no Xcode:
#
#     tools/ios/swift.sh test                 # all of CindyCore's tests
#     tools/ios/swift.sh test --filter WorkoutEngineTests
#     tools/ios/swift.sh build
#
# `build`, `test`, `run` and `package` default to `--package-path ios/CindyCore`. Any other
# command is passed to swift unchanged.
#
# The toolchain is ~880 MB to download and 2.8 GB unpacked. It goes in $CINDY_SWIFT_HOME
# (default ~/.cache/cindy-swift) and is checked against the SHA-256 below before it is unpacked.
# CINDY_SWIFT_ARCHIVE names an already downloaded copy of the same file, for working offline.
#
# On a Mac, use Xcode's own swift instead: `swift test --package-path ios/CindyCore`.

set -eu

VERSION=6.1.2
NAME="swift-$VERSION-RELEASE-ubuntu24.04"
URL="https://download.swift.org/swift-$VERSION-release/ubuntu2404/swift-$VERSION-RELEASE/$NAME.tar.gz"
SHA256=d749d5fe2d6709ee988e96b16f02bca7b53304d09925e31063fd5ec56019de9f

root=$(cd "$(dirname "$0")/../.." && pwd)
home=${CINDY_SWIFT_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/cindy-swift}
swift_bin="$home/$NAME/usr/bin/swift"

if [ ! -x "$swift_bin" ]; then
    if [ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]; then
        echo "swift.sh: this fetches the Linux x86_64 toolchain, and this is $(uname -s)-$(uname -m)." >&2
        echo "On a Mac use Xcode's swift: swift test --package-path ios/CindyCore" >&2
        exit 1
    fi
    mkdir -p "$home"
    archive=${CINDY_SWIFT_ARCHIVE:-}
    if [ -z "$archive" ]; then
        archive="$home/$NAME.tar.gz.partial"
        echo "swift.sh: downloading Swift $VERSION (about 880 MB) to $home" >&2
        curl -fSL --retry 3 -o "$archive" "$URL"
        downloaded=1
    fi
    if [ "$(sha256sum "$archive" | cut -d' ' -f1)" != "$SHA256" ]; then
        echo "swift.sh: $archive does not match the pinned SHA-256; not unpacking it." >&2
        [ "${downloaded:-}" = 1 ] && rm -f "$archive"
        exit 1
    fi
    echo "swift.sh: unpacking" >&2
    tar -xzf "$archive" -C "$home"
    [ "${downloaded:-}" = 1 ] && rm -f "$archive"
fi

if [ $# -gt 0 ]; then
    case "$1" in
        build|test|run|package)
            case " $* " in
                *" --package-path "*) ;;
                *) cmd=$1; shift; set -- "$cmd" --package-path "$root/ios/CindyCore" "$@" ;;
            esac
            ;;
    esac
fi

exec "$swift_bin" "$@"
