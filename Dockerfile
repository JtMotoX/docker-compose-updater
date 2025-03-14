FROM alpine:latest

# SET SO THAT SCRIPT KNOWS ITS RUNNING IN DOCKER
ENV is_docker=true

# INSTALL DEPENDENCIES
RUN apk add --no-cache bash curl jq libc6-compat coreutils

# INSTALL DOCKER
COPY --from=docker:dind /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:dind /usr/local/bin/docker-compose /usr/local/bin/docker-compose
COPY --from=docker:dind /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose

# INSTALL GUM
RUN tmpdir=$(mktemp -d) && \
    cd $tmpdir && \
    LATEST_VERSION=$(curl -s https://api.github.com/repos/charmbracelet/gum/releases/latest | jq -r .tag_name) && \
    curl -L "https://github.com/charmbracelet/gum/releases/download/$LATEST_VERSION/gum_${LATEST_VERSION#v}_Linux_x86_64.tar.gz" -o gum.tar.gz && \
    tar -xzf gum.tar.gz -C . --strip-components=1 && \
    mv gum /usr/local/bin/gum && \
    rm -rf $tmpdir && \
    gum --version

# INSTALL TINI TO SUPPORT CTRL+C
RUN apk add --no-cache tini

# INSTALL DOCKER-COMPOSE-UPDATER
COPY --chmod=755 ./docker-compose-updater.sh /usr/local/bin/docker-compose-updater

# ENTRYPOINT AND CMD
ENTRYPOINT ["tini", "-g", "--", "docker-compose-updater" ]
