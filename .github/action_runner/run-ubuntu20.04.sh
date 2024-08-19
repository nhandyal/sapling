#!/usr/bin/env bash
set -ex

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT="$(realpath $SCRIPT_DIR/../..)"

# Step 1: Build the Dockerfile at .github/workflows/sapling-cli-ubuntu-20.04.Dockerfile
docker build -f "$PROJECT_ROOT/.github/workflows/sapling-cli-ubuntu-20.04.Dockerfile" \
    -t sapling_ubuntu20.04:latest \
    "$PROJECT_ROOT"

# Step 2: Build the Dockerfile at github_actions_docker/Dockerfile
docker build -f "$PROJECT_ROOT/.github/action_runner/ubuntu20.04.Dockerfile" \
    -t sapling_ga_ubuntu20.04:latest \
    "$PROJECT_ROOT"

docker run -it sapling_ga_ubuntu20.04:latest /bin/bash
