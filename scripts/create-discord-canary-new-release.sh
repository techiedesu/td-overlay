#!/usr/bin/env bash

set -e

OVERLAY_ROOT=$(dirname $(dirname $(readlink -fm $0)))
OVERLAY_DISCORD_CANARY_MANIFEST_PATH="$OVERLAY_ROOT/net-im/discord-canary/Manifest"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

exec_jq() {
    if command_exists yq; then
        yq "$1"
    else
        jq "$1"
    fi
}

exec_git_add() {
    git -C "$OVERLAY_ROOT" add $1
}

exec_git_staged_files() {
    git -C "$OVERLAY_ROOT" diff --cached --name-only
}

exec_git_staged_files_count() {
    git -C "$OVERLAY_ROOT" diff --cached --name-only | wc -l
}

exec_git_commit() {
    git -C "$OVERLAY_ROOT" commit -m "$1"
}

exec_git_reset() {
    git -C "$OVERLAY_ROOT" reset
}

echo "Checking all required deps..."

command_exists jq || command_exists yq || (echo "jq nor yq not installed (app-misc/jq or app-misc/yq)"; exit 1)
command_exists pkgdev || (echo "pkgdev not installed (dev-util/pkgdev)"; exit 1)
command_exists curl || (echo "curl not installed (net-misc/curl)"; exit 1)
command_exists git || (echo "git not installed (dev-vcs/git)"; exit 1)

echo "Deps checked!"

echo ""
echo "Overlay root: $OVERLAY_ROOT"

DISCORD_CANARY_EBUILDS_PATH="$OVERLAY_ROOT/net-im/discord-canary"

LATEST_EBUILD_FILE_PATH=$(find $DISCORD_CANARY_EBUILDS_PATH ! -name 'Manifest' -type f | sort -n | tail -n1)
LATEST_EBUILD_PATH=$(find $DISCORD_CANARY_EBUILDS_PATH ! -name 'Manifest' | sort -n | tail -n1)

NEW_VERSION="$(curl -s 'https://discord.com/api/updates/canary?platform=linux' | jq -Mr .name)"

if [ -z "${NEW_VERSION}" ]; then
    echo "Failed to get discord latest version (empty NEW_VERSION). Exiting..."
    exit 1
fi

echo "Latest discord version: $NEW_VERSION!"

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
    exit 0
fi

GIT_STAGED_LIST_FILE_PATH="$(date '+%Y-%m0-%d-%H_%M_%S')_staged.txt"
GIT_STAGED_FILES=$(exec_git_staged_files)
GIT_STAGED_FILES_COUNT="$(printf \"$GIT_STAGED_FILES\" | wc -l)"

echo ""
echo "staged $GIT_STAGED_FILES_COUNT"
echo "files $GIT_STAGED_FILES"

if [ "${GIT_STAGED_FILES_COUNT}" != "0" ]; then
    echo "Saving staged git files to '$GIT_STAGED_LIST_FILES_PATH' before reset"
    print -r -- "$GIT_STAGED_FILES > $GIT_STAGED_LIST_FILE_PATH"

else
    echo "Staged files not found. List of staged files won't be created"
fi

echo "Marking ebuild and manifest in git as staged"
exec_git_add $NEW_EBUILD_PATH
exec_git_add $OVERLAY_DISCORD_CANARY_MANIFEST_PATH

GIT_STAGED_UPDATE_FILES_COUNT="$(exec_git_staged_files_count)"

if [ "${GIT_STAGED_UPDATE_FILES_COUNT}" != "2" ]; then
    echo "Failed to stage ebuild and manifest. Staged files are should be 2 but was '$GIT_STAGED_UPDATE_FILES_COUNT'. Reverting..."

    exec_git_reset
    exec_git_add $GIT_STAGED_FILES_PATH
    GIT_RESTORED_STAGED_FILES_COUNT="$(exec_git_staged_files_count)"
    if [ "$GIT_RESTORED_FILES_COUNT" != "$GIT_STAGED_FILES_COUNT" ]; then
            echo "Failed to restore staged files... Do it yourself."
            echo "Exiting..."
            exit 1
    fi

    echo "Restored previous staged files. Exiting..."
    exit 1
fi

exec_git_commit "Add $(basename $NEW_EBUILD_PATH)"
# git push

echo "Commited! '$(git log -1 --pretty=%B | xargs)'"
echo ""

if [ "$GIT_STAGED_FILES_COUNT" != "0" ]; then
git add $(cat "$GIT_STAGED_FILES_PATH")
    echo "Restored staged files"
else
    echo "Done! Exiting..."
fi
