ARG BASE_STAGE

# ============================================================================
# Base stages for different distributions
# ============================================================================

FROM fedora:42 AS fedora-base
RUN dnf install -y \
    git \
    make \
    cmake \
    gcc \
    gcc-c++ \
    kernel-devel \
    libtool \
    autoconf \
    automake \
    wget \
    curl \
    nano \
    vim \
    sudo \
    openssl-devel \
    zlib-devel \
    ninja-build \
    boost-devel \
    gcc-14 \
    patch \
    expat-devel \
    gawk \
    unzip \
    zip \
    && dnf clean all

FROM ubuntu:24.04 AS ubuntu-base
RUN apt-get update && apt-get install -y \
    git \
    make \
    cmake \
    gcc \
    g++ \
    linux-headers-generic \
    libtool \
    autoconf \
    automake \
    wget \
    curl \
    nano \
    vim \
    sudo \
    libssl-dev \
    zlib1g-dev \
    ninja-build \
    libboost-all-dev \
    patch \
    libexpat1-dev \
    pkg-config \
    gawk \
    unzip \
    zip \
    bash \
    && rm -rf /var/lib/apt/lists/*

FROM alpine:latest AS alpine-base
RUN apk add --no-cache \
    git \
    make \
    cmake \
    gcc \
    g++ \
    linux-headers \
    libtool \
    autoconf \
    automake \
    wget \
    curl \
    nano \
    vim \
    sudo \
    openssl-dev \
    zlib-dev \
    samurai \
    boost-dev \
    patch \
    expat-dev \
    gawk \
    unzip \
    zip \
    bash

RUN wget -O /etc/apk/keys/adoptium.rsa.pub https://packages.adoptium.net/artifactory/api/security/keypair/public/repositories/apk && \
    echo 'https://packages.adoptium.net/artifactory/apk/alpine/main' >> /etc/apk/repositories && \
    apk add --no-cache \
    temurin-8-jre \
    temurin-8-jdk

# ============================================================================
# Common build stage (distro-agnostic)
# ============================================================================

FROM ${BASE_STAGE} AS common-build

# Create a non-root user with sudo access
RUN useradd -m devuser 2>/dev/null || adduser -D devuser 2>/dev/null || true && \
    echo "devuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Set up working directory
WORKDIR /home/devuser

# Copy patches
COPY fix_cstdint_includes.patch .
COPY fix_string_include.patch .
COPY fix_musl_support.patch .

# Build vsomeip
RUN --mount=type=cache,target=/var/cache/builds \
    git clone https://github.com/COVESA/vsomeip.git && \
    cd vsomeip && git checkout 3.5.5 && \
    git apply ../fix_cstdint_includes.patch && \
    git apply ../fix_musl_support.patch && \
    git submodule update --init --recursive && \
    mkdir build && cd build && \
    cmake -E env CXXFLAGS="-Wno-error=stringop-overflow" \
    cmake .. -G Ninja -DBoost_INCLUDE_DIR=/usr/include/boost -DENABLE_SIGNAL_HANDLING=1 && \
    ninja && ninja install

# Build capicxx-core-runtime
RUN --mount=type=cache,target=/var/cache/builds \
    git clone https://github.com/COVESA/capicxx-core-runtime.git && \
    cd capicxx-core-runtime && \
    git checkout 3.2.4 && \
    git apply ../fix_string_include.patch && \
    mkdir build && cd build && \
    cmake -G Ninja -DCMAKE_BUILD_TYPE=Release .. && \
    ninja && ninja install

# Build capicxx-someip-runtime
RUN --mount=type=cache,target=/var/cache/builds \
    git clone https://github.com/COVESA/capicxx-someip-runtime.git && \
    cd capicxx-someip-runtime && \
    git checkout 3.2.4 && \
    mkdir build && cd build && \
    cmake -G Ninja -DCMAKE_BUILD_TYPE=Release .. && \
    ninja && ninja install

# Build capicxx-dbus-runtime and dbus
RUN --mount=type=cache,target=/var/cache/builds \
    git clone https://github.com/COVESA/capicxx-dbus-runtime.git && \
    cd capicxx-dbus-runtime && \
    git checkout 3.2.3-r1 && \
    wget -N https://dbus.freedesktop.org/releases/dbus/dbus-1.12.16.tar.gz && \
    tar -xf dbus-1.12.16.tar.gz && \
    rm dbus-1.12.16.tar.gz && \
    for patch in src/dbus-patches/*.patch; do patch -d dbus-1.12.16/ -p1 <"$patch"; done && \
    cd dbus-1.12.16 && ./configure --prefix=/usr/local && \
    cd .. && \
    make -C dbus-1.12.16 -j$(nproc) && \
    make -C dbus-1.12.16 install && \
    mkdir build && cd build && \
    cmake -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=ON \
      -DUSE_INSTALLED_DBUS=ON \
      -DCMAKE_PREFIX_PATH=/usr/local \
      .. && \
    ninja && ninja install

# Install SDKMAN and Java/Maven
ENV JAVA_HOME="$SDKMAN_DIR/candidates/java/current"
ENV MAVEN_HOME="$SDKMAN_DIR/candidates/maven/current"
ENV PATH="$JAVA_HOME/bin:$MAVEN_HOME/bin:$PATH"

RUN bash -c "curl -s 'https://get.sdkman.io' | bash && \
    source \$HOME/.sdkman/bin/sdkman-init.sh && \
    sdk install java 8.0.442-tem && \
    sdk install maven"

# Build capicxx tools
RUN bash -c "git clone https://github.com/COVESA/capicxx-core-tools.git && \
    cd capicxx-core-tools/org.genivi.commonapi.core.releng && \
    source "$HOME/.sdkman/bin/sdkman-init.sh" && \
    mvn -Dtarget.id=org.genivi.commonapi.core.target clean verify"

RUN bash -c "git clone https://github.com/COVESA/capicxx-someip-tools.git && \
    cd capicxx-someip-tools/org.genivi.commonapi.someip.releng && \
    source "$HOME/.sdkman/bin/sdkman-init.sh" && \
    mvn -DCOREPATH=../../capicxx-core-tools -Dtarget.id=org.genivi.commonapi.someip.target clean verify"

RUN bash -c "git clone https://github.com/COVESA/capicxx-dbus-tools.git && \
    cd capicxx-dbus-tools/org.genivi.commonapi.dbus.releng && \
    source "$HOME/.sdkman/bin/sdkman-init.sh" && \
    mvn -DCOREPATH=../../capicxx-core-tools -Dtarget.id=org.genivi.commonapi.dbus.target clean verify"

# Install generators
RUN unzip capicxx-core-tools/org.genivi.commonapi.core.cli.product/target/products/commonapi_core_generator.zip \
    -d /usr/local/bin && \
    unzip -o capicxx-someip-tools/org.genivi.commonapi.someip.cli.product/target/products/commonapi_someip_generator.zip \
    -d /usr/local/bin && \
    unzip -o capicxx-dbus-tools/org.genivi.commonapi.dbus.cli.product/target/products/commonapi_dbus_generator.zip \
    -d /usr/local/bin

# Fix ownership and switch to devuser
# RUN chown -R devuser:devuser /home/devuser
# USER devuser

CMD ["/bin/bash"]

# ============================================================================
# Final distro-specific images
# ============================================================================

FROM common-build AS fedora-final

FROM common-build AS ubuntu-final

FROM common-build AS alpine-final