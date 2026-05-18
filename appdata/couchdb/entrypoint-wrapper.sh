#!/bin/sh
if [ -f /run/secrets/couchdb_password ]; then
  export COUCHDB_PASSWORD=$(cat /run/secrets/couchdb_password)
fi
exec /docker-entrypoint.sh "$@"
