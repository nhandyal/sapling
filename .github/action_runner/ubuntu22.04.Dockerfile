# Dockerfile that configures a GitHub Actions runner on an Ubuntu 22.04

FROM sapling_ubuntu22.04:latest

ARG GROUP_NAME=sapling
ARG GROUP_ID=408
ARG USER_NAME=sapling
ARG USER_ID=650

# Set the environment variables for rustup and cargo paths
ENV CARGO_HOME=/root/.cargo
ENV PATH=$CARGO_HOME/bin:$PATH

# https://serverfault.com/a/1016972 to ensure installing tzdata does not
# result in a prompt that hangs forever.
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update -y && apt-get install -y \
    sudo vim

# Create a new group and user with the specified IDs and names
RUN if ! getent group $GROUP_NAME; then \
    groupadd -g $GROUP_ID $GROUP_NAME; \
    fi

RUN if ! getent passwd $USER_NAME; then \
    useradd -ms /bin/bash -g $GROUP_NAME -u $USER_ID $USER_NAME; \
    fi

# Download and install the GitHub Actions runner
RUN mkdir -p /home/$USER_NAME && cd /home/$USER_NAME && \
    mkdir actions-runner && cd actions-runner && \
    curl -o actions-runner-linux-arm64-2.319.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.319.0/actions-runner-linux-arm64-2.319.0.tar.gz && \
    echo "524e75dc384ba8289fcea4914eb210f10c8c4e143213cef7d28f0c84dd2d017c  actions-runner-linux-arm64-2.319.0.tar.gz" | shasum -a 256 -c && \
    tar xzf ./actions-runner-linux-arm64-2.319.0.tar.gz

# Create the wrapper script
ARG CONFIG_SCRIPT_PATH=/home/$USER_NAME/actions-runner/config.sh
RUN mv $CONFIG_SCRIPT_PATH /home/$USER_NAME/actions-runner/_config.sh && \
    echo '#!/usr/bin/env bash' > $CONFIG_SCRIPT_PATH && \
    echo 'set -xe\n' >> $CONFIG_SCRIPT_PATH && \
    echo 'read -p "Enter GH action runner token: " token' >> $CONFIG_SCRIPT_PATH && \
    echo './_config.sh --url https://github.com/nhandyal/sapling --token "$token" --unattended --labels self-hosted,ubuntu-22.04,arm64 --no-default-labels --replace'  >> $CONFIG_SCRIPT_PATH && \
    chmod +x $CONFIG_SCRIPT_PATH
    
# Configure the user
RUN echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    echo 'export PATH=/root/.cargo/bin:$PATH' >> /home/$USER_NAME/.bashrc && \
    chown -R $USER_NAME:$GROUP_NAME /root && \
    chown -R $USER_NAME:$GROUP_NAME /home/$USER_NAME

WORKDIR /home/$USER_NAME/actions-runner
USER $USER_NAME
CMD ["tail", "-f", "/dev/null"]
