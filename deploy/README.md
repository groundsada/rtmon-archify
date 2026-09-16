# Dev/demo deployment

The dev stack is two containers on one compose network: RTMon
(`ghcr.io/groundsada/sense-rtmon:archify-dev`, built from the
`groundsada/sense-rtmon` branch) and this sidecar
(`ghcr.io/groundsada/rtmon-archify:archify-dev`).

## Build the images (once per branch change)

Both are built by `workflow_dispatch` workflows, with the same rolling tag:

- RTMon image: push the branch to `groundsada/sense-rtmon`, then run the
  **"RTMon dev image"** workflow in that fork with `buildtag: archify-dev`.
  The workflow builds from that branch (`RTMON_REF`) and pushes
  `ghcr.io/groundsada/sense-rtmon:archify-dev`.
- Sidecar image: run the **"rtmon-archify image"** workflow in this repo with
  `buildtag: archify-dev`.

## Run

```sh
cp .env.example .env                     # set ARCHIFY_TOKEN
cp rtmon.dev.yaml rtmon.yaml             # fill in Grafana/SENSE facts
# put dev sense-o-auth.yaml + hostcert/hostkey.pem beside rtmon.yaml, or
# edit the mounts in compose.dev.yaml
docker compose -f compose.dev.yaml up -d
docker compose -f compose.dev.yaml logs -f rtmon
```

## Wiring

```
browser -> Grafana (text panel iframe)           browser -> :8080 (sidecar)
Grafana icon -> RTMon API :8000 (registry/API)
RTMon :8000 -> http://archify:8080 POST /v1/render (Bearer $ARCHIFY_TOKEN)
```

- `archify.sidecar_url` is container-internal (`http://archify:8080`).
- `archify.diagram_url_base` is what the **browser** reaches: `http://localhost:8080`
  for local demo, or a public route if Grafana is remote.
- Grafana must set `disable_sanitize_html = true` (or
  `GF_PANELS_DISABLE_SANITIZE_HTML=true`) or the iframe is stripped.

## Current gaps (not in the stack yet)

- No Grafana in this compose (mount a `grafana.ini`/env if the demo needs it).
- `rtmon.yaml` mounts assume the three auth/cred files sit next to the compose
  file; they are not committed to any repo on purpose.
