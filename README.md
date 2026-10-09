# glbf-staging

A proof-of-concept configuration repository glbx builds an image from. It holds a
small build recipe and the GitHub Actions pipeline that builds it, to exercise the
whole fan-out end to end. The real Garden Linux configuration will be far more
elaborate; this is a deliberately minimal stand-in.

## Layout

- `pkgs/<name>/` — one source package: `build.yml` (build options and runtime
  dependency declarations), `build-deps.yml` (the resolved build-tooling lock),
  `sources.yml` (the upstream source archives, by hash and URL), and `src/` (the
  imported, patched source tree).
- `rootfs.yml` — the image's shipped package set.
- `rootfs-deps.yml` — the resolved image-configuration-tooling lock.
- `.github/` — the build pipeline (see below).

Everything here is regenerable from glbx and the upstream archive via glbx's
staging-preparation step; nothing in it is authoritative, non-regenerable state.

## The build pipeline

`.github/workflows/build.yml` builds the whole artifact graph on GitHub-hosted
runners: **one graph node per job**. Each job builds exactly its one node with
recursion inhibited — every dependency must already be a cache hit — and then
publishes that node to `ghcr.io/<owner>/<repo>/objstore`, the shared
content-addressed cache that is the only channel between jobs. Graph edges become
job `needs:`.

The workflow is generated, not hand-written. The pipeline

    pkgs/ --(glbx graph)--> graph --(jq)--> build.yml

runs end to end in `.github/generate-workflow.sh` (requires `glbx`, its sandbox
stub, and `jq`): glbx reads the sources and emits the deterministic graph, jq
turns it into one job per node. Nothing in between is stored — `build.yml` is the
only committed derived artefact. Regenerate with:

    GLBX=path/to/glbx STUB=path/to/exec_env_stub .github/generate-workflow.sh

A run's first jobs build glbx from a chosen ref and then **gate** on the graph:
`check-graph` regenerates `build.yml` from the current sources and fails if it
differs from the committed copy. So a stale committed workflow can never silently
build the wrong thing — adding or removing a package means regenerating and
committing `build.yml`.

All build logic lives in hand-authored **reusable workflows**
(`.github/workflows/{build-glbx,check-graph,restore-inputs,plan,build-node}.yml`);
the generated `build.yml` is thin, one caller job per node that `uses:`
`build-node.yml` and carries only the node's `needs:` edges and the already-built
skip guard — the structural wiring `check-graph` validates. Editing the per-node
build logic is a one-file edit; regeneration only re-runs when the graph *shape*
changes.

## The update pipeline

`.github/workflows/update.yml` (manual dispatch; a daily cron is committed
commented-out) opens one pull request per package whose newest Debian version is
higher than the version currently pinned on its lineage. It builds glbx, runs
`glbx check-updates` once over the selected packages, and fans out one
`update-one-package.yml` call per updatable package.

Each package job imports the new version as a pristine commit (`glbx import
--no-merge`) and opens a staging branch `update-staging/<target>/<pkg>-<version>`:

- **clean** — the import three-way-merges into the target; the branch is that
  merge and the PR is a normal one.
- **conflict** — the branch is just the pristine import; the PR is a draft
  carrying the conflicting paths, resolution instructions, and a greppable state
  block. A maintainer merges the target in locally, pushes, and comments
  `/continue-update`; `resolve-continue.yml` re-checks mergeability, optionally
  bumps the lockfile, and marks the PR ready for review.

The target branch is passed as data, so the workflow can run from `main` while
opening PRs against another branch. A branch pushed by the automatic
`GITHUB_TOKEN` does not trigger the build pipeline, so CI runs once a maintainer
pushes to or approves the update PR.
