FROM ubuntu:24.04

ARG CTNG_VERSION=1.26.0
ARG MS_CONFIG_URL=https://raw.githubusercontent.com/microsoft/vscode-linux-build-agent/main/x86_64-gcc-8.5.0-glibc-2.28.config

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    autoconf automake bison bzip2 ca-certificates file flex g++ gawk gcc git \
    gperf help2man libncurses5-dev libtool libtool-bin make meson ninja-build \
    patch python3-dev rsync texinfo unzip wget xz-utils && \
    rm -rf /var/lib/apt/lists/*

RUN wget -q "http://crosstool-ng.org/download/crosstool-ng/crosstool-ng-${CTNG_VERSION}.tar.bz2" && \
    tar -xjf "crosstool-ng-${CTNG_VERSION}.tar.bz2" && \
    cd "crosstool-ng-${CTNG_VERSION}" && \
    ./configure --prefix=/opt/ctng && \
    make -j"$(nproc)" && \
    make install && \
    rm -rf /crosstool-ng-* "/crosstool-ng-${CTNG_VERSION}.tar.bz2"

RUN useradd -m -u 1000 -s /bin/bash builder && \
    mkdir -p /work/src /work/build /work/tarballs /out && \
    chown -R builder:builder /work /out

ENV PATH=/opt/ctng/bin:${PATH}
ENV CT_PREFIX=/work/build
ENV CT_TARBALLS_DIR=/work/tarballs
ENV MS_CONFIG_URL=${MS_CONFIG_URL}

WORKDIR /work

COPY --chown=builder:builder scripts/build-inside-container.sh /usr/local/bin/build-inside-container.sh
RUN chmod +x /usr/local/bin/build-inside-container.sh

USER builder
ENTRYPOINT ["/usr/local/bin/build-inside-container.sh"]