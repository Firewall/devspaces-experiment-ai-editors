FROM registry.access.redhat.com/ubi9/nodejs-22 AS builder

USER 0

RUN dnf install -y git && dnf clean all

RUN tee /etc/yum.repos.d/google-cloud-sdk.repo << 'EOM'
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM

RUN CLOUDSDK_SKIP_PY_COMPILATION=1 dnf install -y google-cloud-cli \
    && dnf clean all

RUN npm install -g t3 @anthropic-ai/claude-code

COPY entrypoint.sh /t3code/entrypoint.sh
COPY entrypoint-init-container.sh /entrypoint-init-container.sh

RUN chgrp -R 0 /t3code /opt/app-root && \
    chmod -R g=u /t3code /opt/app-root && \
    chmod g=u /etc/passwd

USER 1001

CMD ["/t3code/entrypoint.sh"]
