#!/usr/bin/env bash
## Rejects tracked paths that are not plain ASCII, and orphaned Godot .uid
## files. Both have already cost this project a silent failure.
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_DIR"

status=0

## A Cyrillic С reads exactly like a Latin C and defeats every grep, glob and
## path comparison written against it. See docs/technical/COMMERCIAL_ASSESSMENT.md.
non_ascii="$(git -c core.quotePath=false ls-files | LC_ALL=C grep -P '[^\x00-\x7F]' || true)"
if [ -n "$non_ascii" ]; then
	echo "FAIL: non-ASCII characters in tracked paths:"
	printf '  %s\n' $non_ascii
	status=1
fi

## A .uid whose script is gone keeps handing out an id nothing owns, and the
## scene that references it loads by text path with a warning until it does not.
orphans=""
while IFS= read -r uid_file; do
	source_file="${uid_file%.uid}"
	[ -f "$source_file" ] || orphans="${orphans}${uid_file}"$'\n'
done < <(git -c core.quotePath=false ls-files '*.uid')
if [ -n "$orphans" ]; then
	echo "FAIL: .uid files with no source script:"
	printf '  %s\n' $orphans
	status=1
fi

if [ "$status" -eq 0 ]; then
	echo "filenames: clean"
fi
exit "$status"
