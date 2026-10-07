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
