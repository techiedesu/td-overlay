#!/usr/bin/env bash

OVERLAY_ROOT=$(dirname $(dirname $(readlink -fm $0)))
DISCORD_CANARY_EBUILDS_PATH="$OVERLAY_ROOT/net-im/discord-canary"

LATEST_EBUILD_FILE_PATH=$(find $DISCORD_CANARY_EBUILDS_PATH ! -name 'Manifest' -type f | sort -n | tail -n1)
LATEST_EBUILD_PATH=$(find $DISCORD_CANARY_EBUILDS_PATH ! -name 'Manifest' | sort -n | tail -n1)

NEW_VERSION="$(curl -sS 'https://discord.com/api/updates/canary?platform=linux' | jq -Mr .name)"
NEW_EBUILD_PATH="$DISCORD_CANARY_EBUILDS_PATH/discord-canary-$NEW_VERSION.ebuild"

echo "ebuild file latest = $LATEST_EBUILD_FILE_PATH"
echo "ebuild latest      = $LATEST_EBUILD_PATH"
echo "ebuild new         = $NEW_EBUILD_PATH"

if [ "$LATEST_EBUILD_PATH" != "$NEW_EBUILD_PATH" ]; then
    echo "Creating new ebuild symlink for discord canary $NEW_VERSION"
    ln -s $(basename ${LATEST_EBUILD_FILE_PATH}) $NEW_EBUILD_PATH

    echo "Updating manifest..."
    pkgdev manifest
else
    echo "Discord canary $NEW_VERSION still actual."
fi