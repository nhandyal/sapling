# Directions to build an ARM 64 deb distribution of sapling
1. Execute `run.sh` -- this will build the required containers
2. Start the container by running `docker run -it sapling_ga_ubuntu20.04:latest /bin/bash`
3. Follow the directions under [configure](https://github.com/nhandyal/sapling/settings/actions/runners/new?arch=arm64&os=linux) to create a new arm64 runner:
```
cd '/home/sapling/actions-runner'
./config.sh --url https://github.com/nhandyal/sapling --token <GA_TOKEN>

# after configuration
./run.sh
```
4. 