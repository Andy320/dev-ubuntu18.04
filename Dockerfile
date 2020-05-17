FROM ubuntu:18.04

ARG TOOLCHAIN=stable
ARG OPENSSL_VERSION=1.1.1g
ARG ZLIB=zlib-1.2.11
ARG POSTGRESQL=postgresql-11.7
ARG LLVM=clang+llvm-10.0.0-x86_64-linux-gnu-ubuntu-18.04
ARG HELM=helm-v3.2.0-linux-amd64
ARG GO=go1.14.2.linux-amd64
ARG JDK=jdk-8u231-linux-x64
ARG HOME=/root

ENV PATH=/usr/local/musl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ADD sources_ali.list /etc/apt/
RUN sh -c 'cat /etc/apt/sources_ali.list >> /etc/apt/sources.list' && \
    rm -rf /etc/apt/sources_ali.list

RUN apt-get update && \
    apt-get install -y \
        build-essential \
        cmake \
        curl \
        file \
        git \
        graphviz \
        musl-dev \
        musl-tools \
        libpq-dev \
        libsqlite-dev \
        libssl-dev \
        linux-libc-dev \
        pkgconf \
        sudo \
        xutils-dev \
        vim \
        openssh-client \
        mysql-client \
        gcc-multilib-arm-linux-gnueabihf \
        software-properties-common \
        && \
    add-apt-repository ppa:ubuntu-toolchain-r/test && \
    apt-get update && \
    apt-get install -y \
        gcc-9 \
        g++-9 \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 --slave /usr/bin/g++ g++ /usr/bin/g++-9 && \
    update-alternatives --config gcc

RUN ln -s "/usr/bin/g++" "/usr/bin/musl-g++"

# -----------------llvm----------------- #
ADD $LLVM.tar.xz /usr/local/
ENV PATH=/usr/local/$LLVM/bin:$PATH

# -----------------rust----------------- #
ENV PATH=$HOME/.cargo/bin:$PATH \
    RUSTUP_DIST_SERVER=https://mirrors.ustc.edu.cn/rust-static \
    RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rust-static/rustup
RUN curl https://sh.rustup.rs -sSf | \
    sh -s -- -y --default-toolchain $TOOLCHAIN && \
    rustup target add x86_64-unknown-linux-musl && \
    rustup target add armv7-unknown-linux-musleabihf
ADD cargo-config.toml $HOME/.cargo/config
RUN mkdir -p $HOME/rust/src $HOME/rust/libs

# -----------------golang----------------- #
ADD $GO.tar.gz /usr/local/
RUN mkdir -p $HOME/go/bin $HOME/go/src
ENV GOROOT=/usr/local/go \
    GOPATH=$HOME/go \
    GO111MODULE=on \
    GOPROXY=https://goproxy.cn \
    PATH=$GOROOT/bin:$PATH

# -----------------jdk8----------------- #
ADD $JDK.tar.gz /usr/local/
ENV JAVA_HOME=/usr/local/jdk1.8.0_231 \
    JRE_HOME=/usr/local/jdk1.8.0_231/jre \
    CLASSPATH=.:/usr/local/jdk1.8.0_231/lib:/usr/local/jdk1.8.0_231/jre/lib \
    PATH=/usr/local/jdk1.8.0_231/bin:$PATH

# -----------------kubectl----------------- #
ADD kubectl /usr/local/bin/
RUN mkdir -p $HOME/.kube && touch $HOME/.kube/config

# -----------------helm----------------- #
ADD $HELM.tar.gz /tmp/
RUN mv /tmp/linux-amd64/helm /usr/local/bin/helm && \
    rm -rf /tmp/*

RUN mkdir -p /usr/local/musl/include && \
    ln -s /usr/include/linux /usr/local/musl/include/linux && \
    ln -s /usr/include/x86_64-linux-gnu/asm /usr/local/musl/include/asm && \
    ln -s /usr/include/asm-generic /usr/local/musl/include/asm-generic && \
    cd /tmp && \
    short_version="$(echo "$OPENSSL_VERSION" | sed s'/[a-z]$//' )" && \
    curl -fLO "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" || \
        curl -fLO "https://www.openssl.org/source/old/$short_version/openssl-$OPENSSL_VERSION.tar.gz" && \
    tar xvzf "openssl-$OPENSSL_VERSION.tar.gz" && cd "openssl-$OPENSSL_VERSION" && \
    env CC=musl-gcc ./Configure no-shared no-zlib -fPIC --prefix=/usr/local/musl -DOPENSSL_NO_SECURE_MEMORY linux-x86_64 && \
    env C_INCLUDE_PATH=/usr/local/musl/include/ make depend && \
    env C_INCLUDE_PATH=/usr/local/musl/include/ make && \
    make install && \
    rm /usr/local/musl/include/linux /usr/local/musl/include/asm /usr/local/musl/include/asm-generic && \
    rm -r /tmp/*

ADD $ZLIB.tar.gz /tmp/
RUN cd /tmp/$ZLIB && \
    CC=musl-gcc ./configure --static --prefix=/usr/local/musl && \
    make && make install && \
    rm -r /tmp/*

ADD $POSTGRESQL.tar.gz /tmp/
RUN cd /tmp/$POSTGRESQL && \
    CC=musl-gcc CPPFLAGS=-I/usr/local/musl/include LDFLAGS=-L/usr/local/musl/lib ./configure --with-openssl --without-readline --prefix=/usr/local/musl && \
    cd src/interfaces/libpq && make all-static-lib && make install-lib-static && \
    cd ../../bin/pg_config && make && make install && \
    rm -r /tmp/*

ENV OPENSSL_DIR=/usr/local/musl/ \
    OPENSSL_INCLUDE_DIR=/usr/local/musl/include/ \
    DEP_OPENSSL_INCLUDE=/usr/local/musl/include/ \
    OPENSSL_LIB_DIR=/usr/local/musl/lib/ \
    OPENSSL_STATIC=1 \
    PQ_LIB_STATIC_X86_64_UNKNOWN_LINUX_MUSL=1 \
    PG_CONFIG_X86_64_UNKNOWN_LINUX_GNU=/usr/bin/pg_config \
    PKG_CONFIG_ALLOW_CROSS=true \
    PKG_CONFIG_ALL_STATIC=true \
    LIBZ_SYS_STATIC=1 \
    TARGET=musl


RUN cargo install -f cargo-audit && \
    rm -rf /home/rust/.cargo/registry/

WORKDIR $HOME/rust/src