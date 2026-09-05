FROM rust:1-slim-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        perl \
        make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Cache dependency compilation by copying manifests first
COPY Cargo.toml Cargo.lock ./
COPY vendor/ vendor/
COPY crates/obscura-dom/Cargo.toml       crates/obscura-dom/Cargo.toml
COPY crates/obscura-net/Cargo.toml       crates/obscura-net/Cargo.toml
COPY crates/obscura-browser/Cargo.toml   crates/obscura-browser/Cargo.toml
COPY crates/obscura-cdp/Cargo.toml       crates/obscura-cdp/Cargo.toml
COPY crates/obscura-js/Cargo.toml        crates/obscura-js/Cargo.toml
COPY crates/obscura-mcp/Cargo.toml       crates/obscura-mcp/Cargo.toml
COPY crates/obscura-render/Cargo.toml    crates/obscura-render/Cargo.toml
COPY crates/obscura-cli/Cargo.toml       crates/obscura-cli/Cargo.toml
COPY crates/obscura/Cargo.toml           crates/obscura/Cargo.toml

# Create stub src files so cargo can resolve the dependency graph
RUN for crate in obscura-dom obscura-net obscura-browser obscura-cdp obscura-js obscura-mcp obscura-render obscura; do \
        mkdir -p crates/$crate/src && echo "// stub" > crates/$crate/src/lib.rs; \
    done && \
    mkdir -p crates/obscura-cli/src && \
    echo "fn main() {}" > crates/obscura-cli/src/main.rs && \
    echo "fn main() {}" > crates/obscura-cli/src/worker.rs

RUN cargo build --release --features render --bin obscura --bin obscura-worker 2>/dev/null || true

ARG OBSCURA_VERSION

# Copy real sources and build
COPY crates/ crates/
RUN echo "Building Obscura version ${OBSCURA_VERSION:-from Cargo.toml}" && \
    touch crates/*/src/*.rs && cargo build --release --features render --bin obscura --bin obscura-worker

# ---

# distroless/cc: glibc + libgcc + CA certs only — no shell, no package manager
FROM gcr.io/distroless/cc-debian12

COPY --from=builder /build/target/release/obscura /obscura
COPY --from=builder /build/target/release/obscura-worker /obscura-worker

EXPOSE 9222

# Bind to 0.0.0.0 so the port is reachable via `docker run -p 9222:9222` and so
# PaaS hosts (Railway, Render, Fly, Heroku) can route to it. The native binary
# still defaults to 127.0.0.1 (loopback only); this override is just for the
# container.
#
# The listen port is not pinned here: `obscura serve` reads the PORT env var
# (falling back to 9222) so hosts that inject a dynamic port work out of the box.
# The image is distroless with no shell, so $PORT cannot be expanded in an
# exec-form CMD, so the binary reads it directly.
ENTRYPOINT ["/obscura"]
CMD ["serve", "--host", "0.0.0.0"]
