#!/bin/sh
set -eu

: "${HUGO_BASEURL:?HUGO_BASEURL is required}"

build_site() {
  find /public -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  hugo \
    --source /src \
    --destination /public \
    --baseURL "$HUGO_BASEURL" \
    --minify \
    --cleanDestinationDir \
    --noBuildLock
}

build_site

while true; do
  inotifywait -r -e close_write,create,delete,move /src
  sleep 0.2
  build_site
done
