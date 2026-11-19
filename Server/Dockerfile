# Build
FROM swift:6.2-jammy AS build
WORKDIR /src
COPY Package.swift Package.resolved ./
RUN swift package resolve
COPY Sources ./Sources
COPY Tests ./Tests
RUN swift build -c release --product TodayFlowServer --static-swift-stdlib \
 && cp "$(swift build -c release --show-bin-path)/TodayFlowServer" /TodayFlowServer

# Run
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* && useradd --system --uid 10001 todayflow
COPY --from=build /TodayFlowServer /usr/local/bin/TodayFlowServer
USER todayflow
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD curl -fsS http://localhost:8787/health || exit 1
ENTRYPOINT ["/usr/local/bin/TodayFlowServer"]

# Just the binary, for copying to a host that cannot build images:
#   docker buildx build --platform linux/amd64 --target export --output type=local,dest=out .
FROM scratch AS export
COPY --from=build /TodayFlowServer /TodayFlowServer
