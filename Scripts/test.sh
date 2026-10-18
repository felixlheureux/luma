#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
developer_root="$(xcode-select -p)"
testing_plugin="$developer_root/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$testing_plugin" ] && [ ! -d "$developer_root/Platforms" ]; then
    # The macOS 27 Command Line Tools build backend does not discover this plugin.
    swift test -Xswiftc -load-plugin-library -Xswiftc "$testing_plugin" "$@"
else
    swift test "$@"
fi
