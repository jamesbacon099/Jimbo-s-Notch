#!/bin/bash
set -euo pipefail

project="$(cd "$(dirname "$0")" && pwd)"
exec "$project/Jimbo Studio/build-app.sh" "${1:-$project/.build}"
