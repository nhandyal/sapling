#!/usr/bin/env bash
set -ex

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT="$(realpath $SCRIPT_DIR/../..)"

docker build -f "$PROJECT_ROOT/.github/workflows/sapling-cli-ubuntu-20.04.Dockerfile" \
    -t sapling_ubuntu20.04:latest \
    "$PROJECT_ROOT"

docker build -f "$PROJECT_ROOT/.github/action_runner/ubuntu20.04.Dockerfile" \
    -t sapling_ga_ubuntu20.04:latest \
    "$PROJECT_ROOT"

docker run -it sapling_ga_ubuntu20.04:latest /bin/bash
