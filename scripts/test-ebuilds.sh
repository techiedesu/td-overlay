#!/usr/bin/env bash
# Validate every ebuild in this repository. Usable both locally and as a CI
# entrypoint: a non-zero exit status means something is wrong with the repo.
#
# Usage:
#   scripts/test-ebuilds.sh                 # syntax gate + pkgcheck (needs dev-util/pkgcheck)
#   scripts/test-ebuilds.sh --syntax-only   # bash syntax gate only, no Gentoo tooling needed
#   scripts/test-ebuilds.sh <atom> ...      # extra arguments are passed to `pkgcheck scan`
#
# The pkgcheck run picks up this repo's QA policy from metadata/pkgcheck.conf.
# Failing keyword severities are error and above; warnings and style results are
# printed but do not fail the run, matching what pkgcore/pkgcheck-action gates on.
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(git -C "${script_dir}" rev-parse --show-toplevel 2>/dev/null || dirname -- "${script_dir}")
cd -- "${repo_root}"

syntax_only=0
if [[ ${1-} == --syntax-only ]]; then
	syntax_only=1
	shift
fi

status=0

printf '== bash syntax: ebuilds, eclasses, scripts\n'
count=0
while IFS= read -r -d '' file; do
	if ! bash -n -- "${file}"; then
		printf 'syntax error: %s\n' "${file}" >&2
		status=1
	fi
	count=$((count + 1))
done < <(find . -path ./.git -prune -o \
	\( -name '*.ebuild' -o -name '*.eclass' -o -name '*.sh' \) -print0)
printf 'checked %d files\n' "${count}"

if [[ ${count} -eq 0 ]]; then
	printf 'no ebuilds found — wrong working directory?\n' >&2
	exit 1
fi

if [[ ${syntax_only} -eq 1 ]]; then
	exit "${status}"
fi

if ! command -v pkgcheck >/dev/null 2>&1; then
	printf '\npkgcheck is not installed; install dev-util/pkgcheck or run with --syntax-only\n' >&2
	exit 127
fi

printf '\n== pkgcheck scan\n'
# --exit error: fail on error-level results only. MissingManifest, MetadataError,
# UnknownLicense, NonsolvableDepsInStable and friends are errors, so a green run
# means every ebuild sources, has a complete Manifest and resolvable deps.
pkgcheck scan --exit error "$@" || status=1

printf '\n'
if [[ ${status} -eq 0 ]]; then
	printf 'all checks passed\n'
else
	printf 'checks failed\n' >&2
fi
exit "${status}"
