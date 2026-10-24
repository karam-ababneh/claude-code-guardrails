# Runs the test suite in a clean Linux environment (the guard is developed on macOS).
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends bash jq ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY hooks/ hooks/
COPY tests/ tests/
CMD ["bash", "tests/bash-guard.test.sh"]
