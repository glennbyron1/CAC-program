# =============================================================================
# scap-summary — DISA SCAP XCCDF Results Parser
# Author: Glenn Byron
# Base: python:3.12-slim (minimal attack surface — no build tools, no shell utilities)
# Scanned by: Trivy (GitHub Actions) on every push
# Purpose: Demonstrates container security hygiene for a DevSecOps portfolio
# =============================================================================

# ---- Stage 1: dependency installer (separate stage reduces final image size) ----
FROM python:3.12-slim AS builder

WORKDIR /install

# Copy only requirements first — Docker layer cache means pip only re-runs
# when requirements.txt changes, not on every code change
COPY requirements.txt .

# Install to a non-system prefix so we can copy cleanly to the final image
RUN pip install --no-cache-dir --prefix=/install/deps -r requirements.txt


# ---- Stage 2: runtime image ----
FROM python:3.12-slim AS runtime

# Container security hygiene — required by DISA container STIG:
#   - Run as non-root user (STIG V-233112)
#   - No unnecessary packages
#   - No shell (reduces attack surface)
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --no-create-home --shell /sbin/nologin appuser

WORKDIR /app

# Copy installed packages from builder stage
COPY --from=builder /install/deps /usr/local

# Copy application code
COPY scap_summary.py .

# Drop to non-root before the final layer
USER appuser

# Document what the container expects
# Mount an XCCDF results file at /data/results.xml
VOLUME ["/data"]

ENTRYPOINT ["python", "scap_summary.py"]
CMD ["--help"]

# Labels for image metadata (good practice; required by some DoD registries)
LABEL org.opencontainers.image.title="scap-summary" \
      org.opencontainers.image.description="DISA SCAP XCCDF results parser — CAT I/II/III summary" \
      org.opencontainers.image.authors="Glenn Byron" \
      org.opencontainers.image.source="https://github.com/labuser/CAC-program" \
      org.opencontainers.image.licenses="MIT"
