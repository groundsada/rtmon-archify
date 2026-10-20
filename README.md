# rtmon-archify

The render/serve sidecar for the Archify topology panel in
[ESnet sense-rtmon](https://github.com/esnet/sense-rtmon).

RTMon builds an Archify architecture IR (the SENSE path model, in
`RTMonLibs/ArchifyIR.py`) and POSTs it here. This validates it with
Archify's own validator, renders the self-contained topology HTML, appends
the MIT/OFL attribution, and serves the gzipped artifact to the dashboard
iframe. It exists as a **separate repository** so that Archify's third-party
code and artwork never enter the ESnet repo or image.

## API

```
GET    /healthz                       -> {ok, version, schemaVersion}
POST   /v1/render                     {uid, ir, [quality]}      (auth)
GET    /diagrams/<uid>.html           gzipped artifact, public
GET    /api/v1/artifacts              [uid, ...]                (auth)
POST   /api/v1/sweep                  {keep: [uid, ...]}        (auth)
DELETE /api/v1/artifacts/<uid>                                 (auth)
```

- The GET path is what the browser iframe fetches: public, uid-shaped only,
  uniform 404s, gzip on the wire.
- Everything that writes needs `Authorization: Bearer <token>`.
- If no token is configured, writes answer **503** rather than running open -
  an anonymous render endpoint on the application pod would be an
  arbitrary-code-execution surface. The operator warning goes to stderr.

## Run

```sh
ARCHIFY_TOKEN=<shared-secret> node server.mjs
# or
docker run -d -p 8081:8081 \
  -e ARCHIFY_TOKEN=<shared-secret> \
  -v rtmon-diagrams:/srv/diagrams \
  groundsada/rtmon-archify:latest
```

Environment:
`ARCHIFY_PORT` (8081), `ARCHIFY_BIND` (0.0.0.0), `ARCHIFY_TOKEN` (unset =
write endpoints closed), `ARCHIFY_DIAGRAM_DIR` (/srv/diagrams),
`ARCHIFY_CLI` (archify-entry.mjs), `ARCHIFY_QUALITY` (standard),
`ARCHIFY_CHROME` (hidden).

## Diagram chrome

A rendered artifact arrives with sixteen controls: four in the toolbar
(theme, preset, present, export), four guided-view buttons, and eight on the
diagram nav (path, map, lens, zoom). In a Grafana panel that reads as a tool
with a diagram in it rather than a diagram, so the sidecar folds them behind a
single **Controls** button and puts everything one click away.

`ARCHIFY_CHROME`:

| | |
|---|---|
| `hidden` (default) | collapsed on arrival, one toggle in the toolbar |
| `shown` | toggle present, everything expanded on arrival |
| `off` | inject nothing; the artifact is exactly what the renderer produced |

This is appended after `</html>`, like the attribution and for the same
reason: `archify-cli/` is vendored upstream code and is not edited here. The
collapse is driven by one `data-rtmon-chrome` attribute on `<html>` rather
than by setting `display` on the controls, so once they are visible the
diagram's own logic still owns them. The licence notice stays last in the
file.

**8081, not 8080.** RTMon's own results API (`RTMon-Http`, `http_api_port`)
defaults to 8080, and a sidecar shares the pod's network namespace with it, so
the two cannot both have that port. Moving this needs `archify.sidecar_url` in
`rtmon.yaml` moved with it.

## RTMon side

In `rtmon.yaml`:

```yaml
archify:
  sidecar_url: http://127.0.0.1:8081   # rtmon -> sidecar, same pod
  token: <shared-secret>
  diagram_url_base: https://rtmon.example/diagrams   # browser -> sidecar
```

Two containers, one pod, no shared volume: RTMon POSTs, the sidecar writes
and serves from its own volume. The payload and its licence posture are
entirely this repo's; RTMon ships no Archify code and no Node.

## Vendoring archify-cli

Upstream Archify renders five diagram types behind fifteen subcommands. RTMon
emits one type and the sidecar calls two subcommands, so what is vendored here
is a **subset**, not the whole tool: the rest was code this deployment could
not reach, and unreachable code is still code someone has to read, license and
patch.

Two rules keep that honest:

- **`archify-cli/` holds unmodified upstream files.** The subset is chosen by
  which files get copied, never by editing them. They must not be edited,
  linted or reformatted; fixes go upstream and come back as a re-vendor plus a
  `VERSION` bump.
- **`archify-entry.mjs` is ours.** Upstream's entry point was
  `bin/archify.mjs`; this is that file reduced to `render` and `validate` over
  `architecture`, which is a local edit and so lives outside the vendored tree
  rather than pretending to be upstream.

```sh
SRC=<checkout of archify>
rm -rf archify-cli
mkdir -p archify-cli/{renderers/architecture,renderers/shared,schemas,assets,scripts}

# Architecture renderer and the shared modules it reaches.
cp "$SRC"/renderers/architecture/{render-architecture,grid}.mjs archify-cli/renderers/architecture/
cp "$SRC"/renderers/shared/*.mjs archify-cli/renderers/shared/
# Only the architecture schema and the common definitions it $refs.
cp "$SRC"/schemas/{architecture,common}.schema.json "$SRC"/schemas/README.md archify-cli/schemas/
cp "$SRC"/assets/{template.html,JetBrainsMono-OFL.txt} archify-cli/assets/
# validate spawns the artifact checker, so it is on the render path.
cp "$SRC"/scripts/check-render-output.mjs archify-cli/scripts/
cp "$SRC"/{LICENSE,THIRD_PARTY_NOTICES.md} archify-cli/
printf '%s\n' <new version> > archify-cli/VERSION

# Re-empty the brand catalogue; see THIRD_PARTY_NOTICES.md.
git checkout HEAD -- archify-cli/renderers/shared/generated-brand-marks.mjs
# Not re-vendored, because they are ours or unreachable: archify-entry.mjs,
# bin/{preview,visual-check,open-artifact}.mjs, delta/, the workflow,
# sequence, dataflow and lifecycle renderers and their schemas.
```

`archify-cli/schemas/README.md` is vendored too, so it still documents all
five upstream diagram types and every subcommand. That is left alone on
purpose - it is upstream's description of upstream. Only `architecture` and
`common` ship here, and only `render` and `validate` exist to call them.

An upstream bump can add a shared module the architecture renderer now
imports. `node --check archify-entry.mjs` will not catch that, but the test
suite will: it renders real fixture IR through the vendored tree, so a missing
module fails the render rather than surfacing later as a blank panel.

Then re-run `npm test`.

## Test

```sh
npm test
```

Runs the real renderer (no mocks): a committed fixture IR is validated,
rendered, gzipped, served, listed, swept and removed over an actual HTTP
server on an ephemeral port.
