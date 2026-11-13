#!/bin/sh
# Runs the tests. Without Xcode installed, Swift doesn't look for its testing
# framework where the command line tools keep it, so it's pointed there.
set -e
cd "$(dirname "$0")/.."
tools=/Library/Developer/CommandLineTools/Library/Developer
if [ -d "$tools/Frameworks/Testing.framework" ] && ! xcodebuild -version >/dev/null 2>&1; then
    exec swift test \
        -Xswiftc -F"$tools/Frameworks" -Xlinker -F"$tools/Frameworks" \
        -Xlinker -rpath -Xlinker "$tools/Frameworks" \
        -Xlinker -rpath -Xlinker "$tools/usr/lib" "$@"
fi
exec swift test "$@"
