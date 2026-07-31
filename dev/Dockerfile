ARG SYNCTHING_VERSION=2.1.2
FROM syncthing/syncthing:${SYNCTHING_VERSION}

LABEL org.opencontainers.image.source="https://github.com/zlwu/syncthing4swarm"
LABEL org.opencontainers.image.description="Syncthing wrapper for trusted Docker Swarm manager nodes"
LABEL org.opencontainers.image.licenses="Apache-2.0"

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0555 /entrypoint.sh

EXPOSE 8384 22000/tcp 22000/udp 21027/udp

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
CMD ["/bin/syncthing", "serve"]
