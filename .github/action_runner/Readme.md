# Directions to build an ARM 64 deb distribution of sapling on Ubuntu20.04
1. Execute `run-ubuntu20.04.sh` -- this builds the required containers and launches the runner container
2. Execute `./config.sh` -- Add the GA token from [here](https://github.com/nhandyal/sapling/settings/actions/runners/new?arch=arm64&os=linux)
3. Execute `./run.sh`

# Directions to build an ARM 64 deb distribution of sapling on Ubuntu22.04
Same as above, but use the appropriate run script