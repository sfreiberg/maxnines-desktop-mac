#!/bin/sh
# Runs the tests. Swift only finds its testing framework by itself when Xcode is
# the selected developer folder, so this helps where it isn't.
set -e
cd "$(dirname "$0")/.."
if ! xcodebuild -version >/dev/null 2>&1; then
    xcode=/Applications/Xcode.app/Contents/Developer
    tools=/Library/Developer/CommandLineTools/Library/Developer
    if [ -d "$xcode" ]; then
        # Installed, but the command line tools are selected: use it for this run.
        export DEVELOPER_DIR="$xcode"
    elif [ -d "$tools/Frameworks/Testing.framework" ]; then
        # No Xcode at all, so point at where the command line tools keep it.
        exec swift test \
            -Xswiftc -F"$tools/Frameworks" -Xlinker -F"$tools/Frameworks" \
            -Xlinker -rpath -Xlinker "$tools/Frameworks" \
            -Xlinker -rpath -Xlinker "$tools/usr/lib" "$@"
    fi
fi
exec swift test "$@"
