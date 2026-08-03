#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Flush DNS
# @raycast.mode compact
# @raycast.packageName Network
# @raycast.icon 🌐
# @raycast.description Flush the macOS DNS cache

set -euo pipefail

sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
echo "DNS cache flushed"
