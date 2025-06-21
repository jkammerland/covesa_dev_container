FROM fedora:42

# Install essential development tools
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

# Create a non-root user with sudo access
RUN useradd -m devuser && \
    echo "devuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Set GCC 14 as the default compiler
RUN alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 60 \
    && alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 60 \
    && alternatives --set gcc /usr/bin/gcc-14 \
    && alternatives --set g++ /usr/bin/g++-14

# Set up working directory
WORKDIR /home/devuser

COPY fix_cstdint_includes.patch .

RUN \
    --mount=type=cache,target=/var/cache/builds \
    git clone https://github.com/COVESA/vsomeip.git && \
    cd vsomeip && git checkout 3.5.5 && \
    git apply ../fix_cstdint_includes.patch && \ 
    git submodule update --init --recursive && \
    mkdir build && cd build && \
    cmake -E env CXXFLAGS="-Wno-error=stringop-overflow" \ 
    # -DENABLE_SIGNAL_HANDLING=1  so that CTRL+C works, without any problems
    # (otherwise it might be that the shared memory segment /dev/shm/vsomeip is not be correctly removed when you stop the application with Ctrl-C).
    cmake .. -DBoost_INCLUDE_DIR=/usr/include/boost -DENABLE_SIGNAL_HANDLING=1 && \
    make -j && make install

COPY fix_string_include.patch .

RUN \
   --mount=type=cache,target=/var/cache/builds \
   git clone https://github.com/COVESA/capicxx-core-runtime.git \
   && cd capicxx-core-runtime \
   && git checkout 3.2.4 \
   && git apply ../fix_string_include.patch \
   && mkdir build \
   && cd build \
   && cmake -G Ninja -DCMAKE_BUILD_TYPE=Release .. \
   && ninja \
   && ninja install

RUN \
   --mount=type=cache,target=/var/cache/builds \
   git clone https://github.com/COVESA/capicxx-someip-runtime.git \
   && cd capicxx-someip-runtime \
   && git checkout 3.2.4 \
   && mkdir build \
   && cd build \
   && cmake -G Ninja -DCMAKE_BUILD_TYPE=Release .. \
   && ninja \
   && ninja install

RUN \
   --mount=type=cache,target=/var/cache/builds \
   git clone https://github.com/COVESA/capicxx-dbus-runtime.git \
   && cd capicxx-dbus-runtime \
   && git checkout 3.2.3-r1 \
   && wget -N https://dbus.freedesktop.org/releases/dbus/dbus-1.12.16.tar.gz \
   && tar -xf dbus-1.12.16.tar.gz \
   && rm dbus-1.12.16.tar.gz \
   && for patch in src/dbus-patches/*.patch; do patch -d dbus-1.12.16/ -p1 <"$patch"; done \
   && env -C dbus-1.12.16 ./configure --prefix=/usr/local \
   && make -C dbus-1.12.16 \
   && make -C dbus-1.12.16 install

RUN \
   cd capicxx-dbus-runtime \
   && mkdir build \
   && cd build \
   && cmake -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=ON \
      -DUSE_INSTALLED_DBUS=ON \
      -DCMAKE_PREFIX_PATH=/usr/local \
      .. \
   && ninja \
   && ninja install

# Required for Java and Maven installation in the container with sdkman
ENV JAVA_HOME="$SDKMAN_DIR/candidates/java/current"
ENV MAVEN_HOME="$SDKMAN_DIR/candidates/maven/current"
ENV PATH="$JAVA_HOME/bin:$MAVEN_HOME/bin:$PATH"

RUN \
  curl -s "https://get.sdkman.io" | bash && \
  source "$HOME/.sdkman/bin/sdkman-init.sh" && \
  sdk install java 8.0.442-tem && sdk install maven

RUN git clone https://github.com/COVESA/capicxx-core-tools.git && \
 cd capicxx-core-tools/org.genivi.commonapi.core.releng && \
#  git checkout add-aarch64-support && \
 source "$HOME/.sdkman/bin/sdkman-init.sh" && \
 mvn -Dtarget.id=org.genivi.commonapi.core.target clean verify

RUN git clone https://github.com/COVESA/capicxx-someip-tools.git && \
 cd capicxx-someip-tools/org.genivi.commonapi.someip.releng && \
 source "$HOME/.sdkman/bin/sdkman-init.sh" && \
 mvn -DCOREPATH=../../capicxx-core-tools -Dtarget.id=org.genivi.commonapi.someip.target clean verify

RUN git clone https://github.com/COVESA/capicxx-dbus-tools.git && \
 cd capicxx-dbus-tools/org.genivi.commonapi.dbus.releng && \
 source "$HOME/.sdkman/bin/sdkman-init.sh" && \
 mvn -DCOREPATH=../../capicxx-core-tools -Dtarget.id=org.genivi.commonapi.dbus.target clean verify

RUN \
    unzip capicxx-core-tools/org.genivi.commonapi.core.cli.product/target/products/commonapi_core_generator.zip \
    -d /usr/local/bin && \
    unzip -o capicxx-someip-tools/org.genivi.commonapi.someip.cli.product/target/products/commonapi_someip_generator.zip \
    -d /usr/local/bin && \
    unzip -o capicxx-dbus-tools/org.genivi.commonapi.dbus.cli.product/target/products/commonapi_dbus_generator.zip \
    -d /usr/local/bin 

# TODO: Move this before starting to install stuff
# RUN chown -R devuser:devuser /home/devuser
# USER devuser

# Default command
CMD ["/bin/bash"]