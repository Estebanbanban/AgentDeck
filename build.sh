#!/bin/zsh
# Build AgentDeck.app into dist/ and (re)launch it.
set -e
cd "$(dirname "$0")"

swift build -c release

APP=dist/AgentDeck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/AgentDeck "$APP/Contents/MacOS/AgentDeck"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force -s - "$APP"

if [[ "$1" == "run" ]]; then
    pkill -x AgentDeck 2>/dev/null || true
    sleep 0.3
    open "$APP"
fi
echo "Built $APP"
