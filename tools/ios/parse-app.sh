#!/bin/sh
# Checks that every file of the iOS app (ios/CindyTracker, ios/CindyTrackerUITests) parses, on Linux,
# with the same pinned toolchain as swift.sh:
#
#     tools/ios/parse-app.sh
#
# This is syntax only. It cannot tell a missing import, a wrong argument label or a type that does
# not exist on iOS: SwiftUI, UIKit and the rest need Apple's SDK, and only Xcode (or the macOS job in
# .github/workflows/ios-app.yml) can compile against it. What it does catch is a brace left open or
# a keyword misspelt, which is the cheapest class of mistake to make while writing views blind.

set -eu

VERSION=6.1.2
NAME="swift-$VERSION-RELEASE-ubuntu24.04"
root=$(cd "$(dirname "$0")/../.." && pwd)
home=${CINDY_SWIFT_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/cindy-swift}
swiftc="$home/$NAME/usr/bin/swiftc"

# Fetch the toolchain the first time, the way swift.sh does.
[ -x "$swiftc" ] || CINDY_SWIFT_HOME="$home" "$root/tools/ios/swift.sh" --version >/dev/null

failed=0
for file in "$root"/ios/CindyTracker/*.swift "$root"/ios/CindyTrackerUITests/*.swift; do
    [ -f "$file" ] || continue
    if ! "$swiftc" -parse "$file" 2>/tmp/parse-app.$$; then
        echo "$file" >&2
        cat /tmp/parse-app.$$ >&2
        failed=1
    fi
done
rm -f /tmp/parse-app.$$
[ "$failed" = 0 ] && echo "parse-app.sh: every app file parses"
exit "$failed"
