ARG BUILD_FROM
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG OOKLA_VERSION=1.2.0

RUN apk add --no-cache jq curl tzdata \
    && case "${BUILD_ARCH}" in \
         aarch64) OOKLA_ARCH=aarch64 ;; \
         amd64) OOKLA_ARCH=x86_64 ;; \
         *) echo "Niet ondersteunde architectuur: ${BUILD_ARCH}" && exit 1 ;; \
       esac \
    && curl -fsSL "https://install.speedtest.net/app/cli/ookla-speedtest-${OOKLA_VERSION}-linux-${OOKLA_ARCH}.tgz" \
       | tar -xz -C /usr/local/bin speedtest \
    && chmod +x /usr/local/bin/speedtest

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
