#!/usr/bin/env bash
# Shared helpers for the update workflows. Sourced by the update and
# resolve-continue jobs. No side effects at source time.

# refsafe encodes a Debian version into a git-ref-safe form for a branch or tag
# name: ':' -> '.' and '~' -> '_'. The ref name is a convenience label; the exact
# version lives in the authoritative source (the PR body's state block, the
# import commit's metadata) — so this need not be reversible, only collision-free
# enough as a label.
refsafe() {
	printf '%s' "$1" | tr ':~' '._'
}

# import_meta_get reads one field from an import commit message on stdin. The
# message carries a fenced metadata block (see glbx's importer) delimited by exact
# full-line begin/end markers; between them are `key: value` lines recording the
# package identity and version. Prints the value for the given key, or nothing if
# the message is not an import commit or lacks the key. Mirrors glbx's own parser.
import_meta_get() {
	local key="$1"
	awk -v key="$key" '
		/^---BEGIN PKG IMPORT METADATA---$/ { inblock = 1; next }
		/^---END   PKG IMPORT METADATA---$/ { inblock = 0 }
		inblock && $0 ~ "^" key ":" {
			line = $0
			sub("^" key ":[ \t]*", "", line)
			print line
		}
	'
}

# branch_name prints the staging branch for an update:
#   update-staging/<target>/<pkg>-<refsafe(version)>
# The leading update-staging/ is the marker resolve-continue greps on.
branch_name() {
	local target="$1" pkg="$2" version="$3"
	printf 'update-staging/%s/%s-%s' "$target" "$pkg" "$(refsafe "$version")"
}

# state_block emits the update metadata as a visible fenced YAML block. It is
# both the human-readable record of the update and the machine-readable memo
# resolve-continue recovers the decision from: the first line inside the fence
# carries the glbf-update-state marker (a YAML comment) that state_get anchors
# on. All arguments are required.
state_block() {
	local pkg="$1" old="$2" new="$3" target="$4" tag="$5" repo="$6" dist="$7" update_lockfile="$8" import_commit="$9" auto_merge="${10}"
	cat <<EOF
\`\`\`yaml
# glbf-update-state
package: $pkg
old_version: $old
new_version: $new
target: $target
update_tag: $tag
repo: $repo
dist: $dist
update_lockfile: $update_lockfile
import_commit: $import_commit
auto_merge: $auto_merge
\`\`\`
EOF
}

# state_get reads one field from a PR body's state block on stdin. Usage:
#   echo "$body" | state_get package
# It scans the fenced yaml block introduced by the glbf-update-state marker and
# prints the value for the given key. Exits non-zero if the block or key is
# absent. The block ends at the closing fence.
state_get() {
	local key="$1"
	awk -v key="$key" '
		/^# glbf-update-state$/ { inblock = 1; next }
		inblock && /^```/        { inblock = 0 }
		inblock {
			if ($0 ~ "^" key ":") {
				line = $0
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

# clean_body prints the PR body for a clean (non-draft) update: a one-line
# summary and the metadata block. Whether it merged cleanly is evident from the
# GitHub UI, so it is not restated here. Args:
#   pkg old new target update_tag repo dist update_lockfile U auto_merge
clean_body() {
	local pkg="$1" old="$2" new="$3" target="$4" tag="$5" repo="$6" dist="$7" lockfile="$8" u="$9" auto_merge="${10}"
	cat <<EOF
Updates **$pkg** from \`$old\` to \`$new\`.

$(state_block "$pkg" "$old" "$new" "$target" "$tag" "$repo" "$dist" "$lockfile" "$u" "$auto_merge")
EOF
}

# conflict_body prints the draft PR body for a conflicting update: an alert with
# the manual-merge instructions, a caution against rebasing, and the metadata
# block. Args:
#   pkg old new target update_tag repo dist update_lockfile U branch pathlist auto_merge
conflict_body() {
	local pkg="$1" old="$2" new="$3" target="$4" tag="$5" repo="$6" dist="$7" lockfile="$8" u="$9" branch="${10}" pathlist="${11}" auto_merge="${12}"
	cat <<EOF
Updates **$pkg** from \`$old\` to \`$new\`.

> [!IMPORTANT]
> This update does not merge cleanly into \`$target\` and needs a manual merge.
> Check out the branch, merge the target in, resolve the conflicts, and push:
>
> \`\`\`
> git fetch origin
> git checkout $branch
> git merge origin/$target
> # resolve conflicts, stage, commit
> git push
> \`\`\`
>
> Then comment \`/continue-update\` on this PR; automation re-checks
> mergeability, bumps the lockfile if requested, and marks it ready for review.

> [!CAUTION]
> Resolve with \`git merge\` only — never \`git rebase\`. The import keeps its own
> upstream lineage, and the merge commit is what lets later updates apply cleanly.
> Rebasing rewrites that history and breaks future updates.

Conflicting paths:

$pathlist

$(state_block "$pkg" "$old" "$new" "$target" "$tag" "$repo" "$dist" "$lockfile" "$u" "$auto_merge")
EOF
}