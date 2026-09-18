FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:0.6.9 /uv /uvx /usr/local/bin/

WORKDIR /app

COPY pyproject.toml uv.lock README.md ./
COPY src ./src

# cpu (default) or gpu — selects which torch build the lockfile installs.
# See the dependency-groups note in pyproject.toml. The gpu variant must
# be built for linux/amd64 to run on the EKS nodes.
ARG TORCH_VARIANT=cpu
RUN uv sync --frozen --no-default-groups --group "$TORCH_VARIANT"

ENTRYPOINT ["/app/.venv/bin/train"]
