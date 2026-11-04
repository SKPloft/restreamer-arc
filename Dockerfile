# The three component images have no defaults on purpose: a bundle assembled from the upstream
# `latest` tags would be published under this repository's name. `make build` passes all three,
# and a bare `docker build .` fails on the blank base image instead.
ARG RESTREAMER_UI_IMAGE
ARG CORE_IMAGE
ARG FFMPEG_IMAGE

FROM $RESTREAMER_UI_IMAGE AS restreamer-ui
FROM $CORE_IMAGE AS core
FROM $FFMPEG_IMAGE

COPY --from=core /core /core
COPY --from=restreamer-ui /ui/build /core/ui

# Use the vendored changelog so the bundle build stays reproducible without fetching from GitHub.
COPY ./CHANGELOG.md /core/ui/CHANGELOG.md
COPY ./run.sh /core/bin/run.sh
COPY ./ui-root /core/ui-root

RUN ffmpeg -buildconf

ENV CORE_CONFIGFILE=/core/config/config.json
ENV CORE_DB_DIR=/core/config
ENV CORE_ROUTER_UI_PATH=/core/ui
ENV CORE_STORAGE_DISK_DIR=/core/data

EXPOSE 8080/tcp
EXPOSE 8181/tcp
EXPOSE 1935/tcp
EXPOSE 1936/tcp
EXPOSE 6000/udp

VOLUME ["/core/data", "/core/config"]
ENTRYPOINT ["/core/bin/run.sh"]
WORKDIR /core
