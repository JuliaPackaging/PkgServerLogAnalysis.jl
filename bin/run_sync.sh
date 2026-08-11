#!/usr/bin/env bash
# Run the log sync pipeline (bin/s3_sync_job.jl) locally.
#
# Requirements:
#  - AWS credentials in the environment (e.g. AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY
#    or AWS_PROFILE) with access to the buckets below
#  - an ssh-agent with a key that can reach the pkg servers (for rsync)
#  - HLL_KEY set to the path of the HLL keyfile
set -euo pipefail

cd "$(dirname "$0")/.."

export SERVERS=${SERVERS:-au,eu-central,eu-north,in,jp,kr,sa,sg,us-east,us-west}
export EPHEMERAL_BUCKET=${EPHEMERAL_BUCKET:-julialang-pkgserver-logs}
export PERSISTENT_BUCKET=${PERSISTENT_BUCKET:-julialang-pkgserver-logs-sanitized}
: "${HLL_KEY:?set HLL_KEY to the path of the HLL keyfile}"

exec julia --threads=auto --project bin/s3_sync_job.jl
