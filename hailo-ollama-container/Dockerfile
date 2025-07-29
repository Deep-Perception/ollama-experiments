# Use Ubuntu 22.04 as base image
FROM ubuntu:22.04

# Set environment variables to prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Update package lists and install dependencies
RUN apt-get update && \
    apt-get install -y \
    wget \
    curl \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    systemd \
    && rm -rf /var/lib/apt/lists/*

# Create a directory for the Hailo package
WORKDIR /tmp

# Download the Hailo packages directly from the URLs
RUN wget -O /tmp/hailort_5.0.0_amd64.deb \
    "https://storage.googleapis.com/deepperception_public/hailo/h10/hailort_5.0.0_amd64.deb" && \
    wget -O /tmp/hailo_gen_ai_model_zoo_5.0.0_amd64.deb \
    "https://storage.googleapis.com/deepperception_public/hailo/h10/hailo_gen_ai_model_zoo_5.0.0_amd64.deb"

# Install the Hailo packages (install HailoRT first as it's likely a dependency)
# Handle systemd service issues by creating mock services
RUN mkdir -p /etc/systemd/system && \
    echo '#!/bin/bash\nexit 0' > /usr/bin/systemctl && \
    chmod +x /usr/bin/systemctl && \
    echo '#!/bin/bash\nexit 0' > /usr/bin/service && \
    chmod +x /usr/bin/service && \
    dpkg -i /tmp/hailort_5.0.0_amd64.deb || true && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -f -y --no-install-recommends || true && \
    dpkg --configure -a || true && \
    dpkg -i /tmp/hailo_gen_ai_model_zoo_5.0.0_amd64.deb || true && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -f -y --no-install-recommends || true && \
    dpkg --configure -a || true && \
    rm -rf /var/lib/apt/lists/* /tmp/hailort_5.0.0_amd64.deb /tmp/hailo_gen_ai_model_zoo_5.0.0_amd64.deb

# Debug: List installed files and check for hailo-ollama
RUN echo "=== Checking for hailo-ollama binary ===" && \
    find /usr -name "*hailo*" -type f 2>/dev/null || true && \
    ls -la /usr/bin/hailo* 2>/dev/null || echo "No hailo binaries found in /usr/bin/" && \
    dpkg -L hailo-gen-ai-model-zoo 2>/dev/null | grep -E "(bin|hailo)" || echo "Package contents check failed"

# Create a non-root user for security (optional but recommended)
RUN useradd -m -s /bin/bash hailo && \
    usermod -aG sudo hailo

# Set working directory
WORKDIR /home/hailo

# Expose port 8000 for hailo-ollama
EXPOSE 8000

# Note: Container requires access to /dev/hailo0 device
# Run with: docker run --device=/dev/hailo0 -p 8000:8000 hailo-ai

# Ensure the hailo-ollama binary is executable (if it exists)
RUN if [ -f /usr/bin/hailo-ollama ]; then chmod +x /usr/bin/hailo-ollama; else echo "hailo-ollama not found at /usr/bin/hailo-ollama"; fi

# Switch to non-root user (optional)
# USER hailo

# Set the default command - use bash for debugging if hailo-ollama not found
CMD ["/bin/bash", "-c", "if [ -f /usr/bin/hailo-ollama ]; then echo 'Starting hailo-ollama...' && /usr/bin/hailo-ollama; else echo 'hailo-ollama not found! Available hailo binaries:' && find /usr -name '*hailo*' -type f 2>/dev/null && echo 'Keeping container alive for debugging...' && tail -f /dev/null; fi"]

# Health check (optional)
# HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
#   CMD curl -f http://localhost:8000/api/health || exit 1
