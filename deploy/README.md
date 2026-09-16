# Dev/demo deployment

The dev stack is two containers on one compose network: RTMon
(`ghcr.io/groundsada/sense-rtmon:archify-dev`, built from the
`groundsada/sense-rtmon` `archify-sidecar` branch) and this sidecar
(`ghcr.io/groundsada/rtmon-archify:archify-dev`, multi-arch).

## Images

Pushed to ghcr already. Rebuild per branch change with the workflows:

- RTMon image: `"RTMon dev image"` in `groundsada/sense-rtmon` (buildtag
  `archify-dev`). The workflow builds from the branch that ran it
  (`RTMON_REF`) - so create the branch, push it, then dispatch. Dockerfile
  defaults remain `esnet/sense-rtmon@master` for upstream/production.
- Sidecar image: `"rtmon-archify image"` in this repo (buildtag `archify-dev`).

> Note: `workflow_dispatch` can only be triggered for workflows that exist on
> the default branch. Until the branch/PR is merged, build locally with
> `docker buildx build --platform linux/amd64 --push ...` (sidecar) or `docker
> build --build-arg RTMON_REPO=...` (RTMon) instead.

## Run (from this repo root)

```sh
cp deploy/.env.example .env             # set ARCHIFY_TOKEN
cp deploy/rtmon.dev.yaml rtmon.yaml     # fill in Grafana/SENSE facts
mkdir -p deploy/templates
# put dev sense-o-auth.yaml + hostcert/hostkey.pem in deploy/, and copy the
# dashboard templates RTMon ships (src/templates/*) into deploy/templates/
docker compose -f deploy/compose.dev.yaml up -d
docker compose -f deploy/compose.dev.yaml logs -f rtmon
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

## Auth files

`sense-o-auth.yaml`, `sense-o-auth-prod.yaml`, `hostcert.pem`, `hostkey.pem`
and `templates/` are **not committed** (they hold credentials/api keys and the
templates ship in the RTMon image; only mount `templates/` if you need to
override). Copy your copies into `deploy/` before `up`.

## What a "run" produces

- RTMon daemon: `http://localhost:8000` - SENSE-O polling + Grafana API.
- Sidecar: `http://localhost:8080` - serves artifacts at
  `/diagrams/<uid>.html`; `curl http://localhost:8080/healthz` should return
  `{"ok":true,...}`.
- Grafana: a dashboard with the Archify panel. No Grafana container here -
  point an existing dev Grafana at `http://localhost:8080` via
  `diagram_url_base` if you use one.
