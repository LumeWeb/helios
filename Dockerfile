# syntax=docker/dockerfile:1
#
# Helios Ethereum light client.
#
# Build:  docker build -t ghcr.io/lumeweb/helios:local .
# Run:    docker run -v helios-data:/data \
#           -e EXECUTION_RPC=https://... \
#           -e CONSENSUS_RPC=https://... \
#           -e RPC_BIND_IP=0.0.0.0 \
#           -p 8545:8545 \
#           ghcr.io/lumeweb/helios

########################
# Chef: dependency layers
########################
FROM lukemathwalker/cargo-chef:latest-rust-1 AS chef
WORKDIR /app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

########################
# Build: cache deps, then build CLI
########################
FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json
COPY . .
RUN cargo build --release --package helios-cli && \
    strip /app/target/release/helios

########################
# Runtime
########################
FROM debian:bookworm-slim AS runtime

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      tini \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --system --no-create-home --uid 1000 helios \
    && mkdir -p /data \
    && chown helios:helios /data
VOLUME ["/data"]

COPY --from=builder /app/target/release/helios /usr/local/bin/helios

USER helios
EXPOSE 8545

# State dir: CLI flags are env-backed (clap `env`), so DATA_DIR points the
# file database at the mounted volume; helios stores per-network state
# under $DATA_DIR/<network>.
ENV DATA_DIR=/data \
    RPC_BIND_IP=0.0.0.0 \
    RPC_PORT=8545 \
    RUST_LOG=info

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/helios"]
CMD ["ethereum"]
