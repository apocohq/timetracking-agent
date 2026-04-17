ARG BASE_IMAGE=ghcr.io/kagenti/humr/humr-base:main
FROM ${BASE_IMAGE}

RUN mkdir -p /app/working-dir/work

COPY CLAUDE.md /app/working-dir/work/CLAUDE.md
COPY .claude /app/working-dir/work/.claude