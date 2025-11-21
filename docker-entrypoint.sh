#!/bin/sh

set -e

REQBIN_DATABASE="${REQBIN_DATABASE:-data.db}"

# Create database (if necessary) and migrate to the latest version
dbmate --url "sqlite:$REQBIN_DATABASE" --no-dump-schema up

# Run the app
exec reqbin "$@"
