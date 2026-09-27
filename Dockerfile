# Founder Hermes runtime
FROM nousresearch/hermes-agent:latest

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates git jq ripgrep \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/founder-entrypoint
COPY founder /opt/founder
RUN chmod +x /usr/local/bin/founder-entrypoint \
 && chmod +x /opt/founder/*.sh

ENV HERMES_HOME=/opt/data \
    API_SERVER_ENABLED=true \
    API_SERVER_HOST=127.0.0.1 \
    API_SERVER_PORT=8642 \
    PORT=8642

EXPOSE 8642
ENTRYPOINT ["/usr/local/bin/founder-entrypoint"]
