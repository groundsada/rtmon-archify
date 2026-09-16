# The RTMon Archify render/serve sidecar.
# Kept separate from the RTMon image on purpose: Archify's third-party brand
# artwork tree lives here, not in ESnet's image.
FROM node:22-alpine

WORKDIR /app
COPY package.json server.mjs ./
COPY archify-cli ./archify-cli

# Archify needs the version file relative to its own tree and nothing else;
# it has no npm dependencies.
ENV ARCHIFY_DIAGRAM_DIR=/srv/diagrams
RUN mkdir -p "$ARCHIFY_DIAGRAM_DIR"

EXPOSE 8080
USER node

# Gate on health rather than a pidfile: no PID 1 zombie handling needed, and
# node reaps its own children (the archify renderer is spawned and waited).
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1

CMD ["node", "server.mjs"]
