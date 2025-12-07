FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies: rsync, SSH client, jq for reading /data/options.json
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       rsync \
       openssh-client \
       jq \
       ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy entrypoint script
COPY run.sh /run.sh
RUN chmod +x /run.sh

# Home Assistant add-ons expect the main process to be PID 1; use a simple shell script here.
CMD ["/run.sh"]
