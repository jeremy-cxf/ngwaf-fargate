# Use build args for debian based distros
ARG IMAGE=nginx
ARG LABEL=1.25.4
FROM $IMAGE:$LABEL

# Get nginx/module args
ARG AGENT_VERSION="4.53.0"
ENV RUNLEVEL=1

# Set the working directory to /app
WORKDIR '/app'

# We want to minimise calling on binaries and installing extra packages.
# So we symlink bash to sh to source /etc/os-release to re-use.
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

# We set "noninteractive" here rather than use an ENV because apt becomes interactive if someone wants to shell in and install something.
RUN DEBIAN_FRONTEND=noninteractive apt-get -qq update && \
    DEBIAN_FRONTEND=noninteractive apt-get -qq install -y apt-utils && \
    DEBIAN_FRONTEND=noninteractive apt-get -qq install -y gnupg2 \
                wget \
                curl \
                apt-transport-https \
                vim \
                ca-certificates \
                psmisc

# Add SigSci
RUN source /etc/os-release && \
    wget -qO - https://apt.signalsciences.net/release/gpgkey | gpg --dearmor -o /usr/share/keyrings/sigsci.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/sigsci.gpg] https://apt.signalsciences.net/release/$ID/ $VERSION_CODENAME main" | tee /etc/apt/sources.list.d/sigsci-release.list && \
    apt-get -qq update -o Dir::Etc::sourcelist="sources.list.d/sigsci-release.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" && \
    DEBIAN_FRONTEND=noninteractive apt-get -qq -y install sigsci-agent=${AGENT_VERSION} \
    nginx-module-sigsci-nxo=$(apt-cache madison nginx-module-sigsci-nxo | grep $(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+') | awk -F'|' '{print $2}' | head -n 1 | xargs)

# Hack to the default config. Although it works for testing things out, if you're modifying the nginx config file yourself, I'd recommend using some form of configuration management for changes to nginx.conf given
# it is alot more idiomatic to do so.
RUN sed -i 's@^pid.*@&\nload_module /usr/lib/nginx/modules/ngx_http_sigsci_module.so;\n@' /etc/nginx/nginx.conf
RUN sed -i 's@default_type.*@&\n    sigsci_agent_host unix:/sigsci/tmp/sigsci.sock;\n@' /etc/nginx/nginx.conf 
    
EXPOSE 80
STOPSIGNAL SIGQUIT
