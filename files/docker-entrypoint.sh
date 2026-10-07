#!/bin/sh

set -e

REQBIN_DATABASE="${REQBIN_DATABASE:-data.db}"

# Create database (if necessary) and migrate to the latest version
dbmate --url "sqlite:$REQBIN_DATABASE" --no-dump-schema up

# Start up caddy in background to provide HTTP service
caddy run --config "/etc/caddy/Caddyfile" --adapter caddyfile &

# Run the app
reqbin "$@"
