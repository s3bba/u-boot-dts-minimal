FROM debian:trixie

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bc \
    bison \
    build-essential \
    ca-certificates \
    cpio \
    debootstrap \
    device-tree-compiler \
    dosfstools \
    e2fsprogs \
    flex \
    gdisk \
    git \
    kmod \
    libncurses-dev \
    libssl-dev \
    locales \
    parted \
    pkg-config \
    python3 \
    qemu-user-static \
    rsync \
    sudo \
    u-boot-tools \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
