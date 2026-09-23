#!/usr/bin/env bash
# Builds dist/Olympus-<version>.zip (unzip into World of Warcraft/<flavor>/Interface/AddOns).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep '^## Version:' Olympus/Olympus.toc | awk '{print $3}')
mkdir -p dist
rm -f "dist/Olympus-$VERSION.zip"
zip -qr "dist/Olympus-$VERSION.zip" Olympus -x '*.DS_Store'
echo "dist/Olympus-$VERSION.zip"
