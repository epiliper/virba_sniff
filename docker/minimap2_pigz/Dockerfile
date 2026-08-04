# syntax=docker/dockerfile:1

# minimap2's SIMD (SSE/NEON) code assumes little-endian, so we pin the
# platform explicitly rather than let it float to whatever the build host is.
# amd64 and arm64 are both little-endian and both have prebuilt minimap2
# releases; this avoids ever landing on a big-endian arch like s390x.
# Passed as an ARG (rather than a literal in FROM) so it can still be
# overridden at build time, e.g. --build-arg BASE_PLATFORM=linux/arm64
ARG BASE_PLATFORM=linux/amd64
FROM --platform=${BASE_PLATFORM} debian:bookworm-slim

ARG MINIMAP2_VERSION=2.31

# Nextflow requires bash to be present in any container it uses, plus
# ps/procps if you want accurate process metrics (cpu/mem) in reports.
# bzip2 is needed to unpack minimap2's .tar.bz2 release archive.
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        procps \
        pigz \
        bzip2 \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Install minimap2 from the official prebuilt little-endian x86_64 release
RUN curl -L "https://github.com/lh3/minimap2/releases/download/v${MINIMAP2_VERSION}/minimap2-${MINIMAP2_VERSION}_x64-linux.tar.bz2" \
        -o /tmp/minimap2.tar.bz2 \
    && tar -xjf /tmp/minimap2.tar.bz2 -C /tmp \
    && mv /tmp/minimap2-${MINIMAP2_VERSION}_x64-linux/minimap2 /usr/local/bin/minimap2 \
    && mv /tmp/minimap2-${MINIMAP2_VERSION}_x64-linux/k8 /usr/local/bin/k8 \
    && mv /tmp/minimap2-${MINIMAP2_VERSION}_x64-linux/paftools.js /usr/local/bin/paftools.js \
    && chmod +x /usr/local/bin/minimap2 /usr/local/bin/k8 /usr/local/bin/paftools.js \
    && rm -rf /tmp/minimap2*

# Sanity check at build time so a bad release/arch mismatch fails fast
RUN minimap2 --version && pigz --version

ENTRYPOINT []
CMD ["bash"]
