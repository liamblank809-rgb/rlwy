# Founder Edition — complete single-service Railway image
FROM node:24-bookworm

ARG PAPERCLIP_VERSION=latest
ARG HERMES_BRANCH=main

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/data \
    HERMES_HOME=/data/hermes \
    PAPERCLIP_HOME=/data/paperclip \
    PAPERCLIP_INSTANCE_ID=default \
    NODE_ENV=production \
    PATH=/data/hermes/.local/bin:/root/.local/bin:${PATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq ripgrep python3 tini \
    && rm -rf /var/lib/apt/lists/*

RUN if [ "$PAPERCLIP_VERSION" = "latest" ]; then \
      npm install -g paperclipai; \
    else \
      npm install -g "paperclipai@${PAPERCLIP_VERSION}"; \
    fi

# Hermes official source installer. Browser tooling remains enabled because
# the Founder role includes research/browser workflows.
RUN mkdir -p /data/hermes /data/paperclip \
 && curl -fsSL https://hermes-agent.nousresearch.com/install.sh \
      | bash -s -- \
        --branch "${HERMES_BRANCH}" \
        --hermes-home /data/hermes \
        --non-interactive

COPY founder /opt/founder
COPY skills /opt/founder-skills
COPY scripts /opt/founder-scripts
COPY entrypoint.sh /usr/local/bin/founder-entrypoint
COPY health-server.py /usr/local/bin/founder-health

RUN chmod +x /usr/local/bin/founder-entrypoint \
             /usr/local/bin/founder-health \
             /opt/founder-scripts/*.sh \
 && mkdir -p /data/hermes/company /data/hermes/workspace \
             /data/hermes/logs /data/paperclip

EXPOSE 3100

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/founder-entrypoint"]
