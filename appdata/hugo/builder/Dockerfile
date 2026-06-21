FROM hugomods/hugo:exts

RUN apk add --no-cache inotify-tools

COPY watch-build.sh /usr/local/bin/watch-build
RUN chmod +x /usr/local/bin/watch-build

ENTRYPOINT ["/usr/local/bin/watch-build"]
