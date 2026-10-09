#!/usr/bin/env bash
# Shared helpers for the update workflows. Sourced by the update and
# resolve-continue jobs. No side effects at source time.

# refsafe encodes a Debian version into a git-ref-safe form for a branch name:
# ':' -> '.' and '~' -> '_'. The branch name is a convenience; the exact version
# lives in the PR body's state block, which is authoritative — so this need not
# be reversible, only collision-free enough for a branch label.
refsafe() {
	printf '%s' "$1" | tr ':~' '._'
}

# branch_name prints the staging branch for an update:
#   update-staging/<target>/<pkg>-<refsafe(version)>
# The leading update-staging/ is the marker resolve-continue greps on.
branch_name() {
	local target="$1" pkg="$2" version="$3"
	printf 'update-staging/%s/%s-%s' "$target" "$pkg" "$(refsafe "$version")"
}

# state_block emits the greppable YAML state block (wrapped in an HTML comment so
# it is hidden in the rendered PR view). resolve-continue recovers the update
# decision from it. All arguments are required.
state_block() {
	local pkg="$1" old="$2" new="$3" target="$4" tag="$5" repo="$6" dist="$7" update_lockfile="$8" import_commit="$9"
	cat <<EOF
<!-- glbf-update-state
\`\`\`yaml
pkg: $pkg
old: $old
new: $new
target: $target
update_tag: $tag
repo: $repo
dist: $dist
update_lockfile: $update_lockfile
import_commit: $import_commit
\`\`\`
-->
EOF
}

# state_get reads one field from a PR body's state block on stdin. Usage:
#   echo "$body" | state_get pkg
# It extracts the fenced yaml inside the glbf-update-state comment and prints the
# value for the given key. Exits non-zero if the block or key is absent.
state_get() {
	local key="$1"
	awk -v key="$key" '
		/glbf-update-state/ { inblock = 1; next }
		inblock && /^-->/   { inblock = 0 }
		inblock {
			line = $0
			sub(/^```yaml$/, "", line)
			if (line ~ "^" key ":") {
				sub("^" key ":[ \t]*", "", line)
				print line
				found = 1
			}
		}
		END { exit(found ? 0 : 1) }
	'
}

# format_conflict_paths reads conflicting paths (one per line) on stdin, in a
# working tree where the conflicted merge is staged, and prints a markdown
# bullet per path with its conflict-marker count. Prints a fallback bullet when
# no paths are given.
format_conflict_paths() {
	local any=0 p n
	while IFS= read -r p; do
		[ -z "$p" ] && continue
		any=1
		n="$(grep -c '^<<<<<<<' "$p" 2>/dev/null || echo '?')"
		printf -- '- %s  (%s conflict markers)\n' "$p" "$n"
	done
	if [ "$any" = 0 ]; then
		printf -- '- (conflicting paths could not be enumerated)\n'
	fi
}

# clean_body prints the PR body for a clean (non-draft) update. Args:
#   pkg old new target update_tag repo dist update_lockfile U
clean_body() {
	local pkg="$1" old="$2" new="$3" target="$4" tag="$5" repo="$6" dist="$7" lockfile="$8" u="$9"
	cat <<EOF
This updates **$pkg** from \`$old\` to \`$new\` (import \`${u:0:12}\`).

The import merges cleanly into \`$target\`. Lockfile bumped: $lockfile.

$(state_block "$pkg" "$old" "$new" "$target" "$tag" "$repo" "$dist" "$lockfile" "$u")
EOF
}

# conflict_body prints the draft PR body for a conflicting update. Args:
#   pkg old new target update_tag repo dist update_lockfile U branch pathlist
conflict_body() {
	local pkg="$1" old="$2" new="$3" target="$4" tag="$5" repo="$6" dist="$7" lockfile="$8" u="$9" branch="${10}" pathlist="${11}"
	cat <<EOF
This updates **$pkg** from \`$old\` to \`$new\` (import \`${u:0:12}\`).

The import does **not** merge cleanly into \`$target\`. Conflicting paths:

$pathlist
To resolve:

    git fetch origin
    git checkout $branch
    git merge origin/$target
    # resolve conflicts, stage, commit
    git push

When the branch merges cleanly with \`$target\`, comment \`/continue-update\`
on this PR and automation will finish it (lockfile bump if requested) and mark
it ready for review.

CI will run once a maintainer pushes to the branch or the PR is approved.

$(state_block "$pkg" "$old" "$new" "$target" "$tag" "$repo" "$dist" "$lockfile" "$u")
EOF
}
