FROM hugomods/hugo:exts

# hugomods 映像的 ca-certificates 與內建 Node 25 仍信任 emSign（CVE-2026-111943）：
# 升級系統信任庫，並讓 Node 改用系統信任庫
RUN apk add --no-cache inotify-tools \
    && apk upgrade --no-cache ca-certificates ca-certificates-bundle
ENV NODE_OPTIONS=--use-openssl-ca \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

COPY watch-build.sh /usr/local/bin/watch-build
RUN chmod +x /usr/local/bin/watch-build

ENTRYPOINT ["/usr/local/bin/watch-build"]
