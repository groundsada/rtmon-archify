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
docker run -d -p 8080:8080 \
  -e ARCHIFY_TOKEN=<shared-secret> \
  -v rtmon-diagrams:/srv/diagrams \
  groundsada/rtmon-archify:latest
```

Environment:
`ARCHIFY_PORT` (8080), `ARCHIFY_BIND` (0.0.0.0), `ARCHIFY_TOKEN` (unset =
write endpoints closed), `ARCHIFY_DIAGRAM_DIR` (/srv/diagrams),
`ARCHIFY_CLI` (archify-cli/bin/archify.mjs), `ARCHIFY_QUALITY` (standard).

## RTMon side

In `rtmon.yaml`:

```yaml
archify:
  sidecar_url: http://127.0.0.1:8080   # rtmon -> sidecar, same pod
  token: <shared-secret>
  diagram_url_base: https://rtmon.example/diagrams   # browser -> sidecar
```

Two containers, one pod, no shared volume: RTMon POSTs, the sidecar writes
and serves from its own volume. The payload and its licence posture are
entirely this repo's; RTMon ships no Archify code and no Node.

## Vendoring archify-cli

`archify-cli/` is copied verbatim from upstream. It must not be edited,
linted or reformatted; fixes go upstream and come back as a re-vendor plus a
`VERSION` bump.

```sh
SRC=<checkout of archify>
rm -rf archify-cli
mkdir -p archify-cli/scripts
cp -R "$SRC"/{bin,renderers,schemas,assets,delta} archify-cli/
cp "$SRC"/{LICENSE,THIRD_PARTY_NOTICES.md} archify-cli/
cp "$SRC"/scripts/check-render-output.mjs archify-cli/scripts/
printf '%s\n' <new version> > archify-cli/VERSION
# Re-empty the brand catalogue; see THIRD_PARTY_NOTICES.md.
git checkout HEAD -- archify-cli/renderers/shared/generated-brand-marks.mjs
```

Then re-run `npm test`, which renders the committed fixture IR through the
vendored CLI and would catch a broken validate/render path immediately.

## Test

```sh
npm test
```

Runs the real renderer (no mocks): a committed fixture IR is validated,
rendered, gzipped, served, listed, swept and removed over an actual HTTP
server on an ephemeral port.
