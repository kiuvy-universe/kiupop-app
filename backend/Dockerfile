# syntax=docker/dockerfile:1
# Multi-stage build: static Go binary on distroless, non-root.
ARG GO_VERSION=1.26
FROM golang:${GO_VERSION}-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG APP_VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath \
      -ldflags="-s -w" -o /out/server ./cmd/server \
 && mkdir -p /out/uploads

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
# Upload dir owned by nonroot so a fresh named volume inherits writable ownership.
COPY --from=build --chown=nonroot:nonroot /out/uploads /data/uploads
USER nonroot:nonroot
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=5 \
  CMD ["/server", "healthcheck"]
ENTRYPOINT ["/server"]
