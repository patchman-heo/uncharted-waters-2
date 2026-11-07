#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/Godot_v4.3-stable_linux.x86_64" --path "$DIR" "$@"
