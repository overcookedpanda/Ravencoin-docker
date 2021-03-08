# Build stage for BerkeleyDB
FROM alpine as berkeleydb

RUN apk --no-cache add autoconf git automake build-base

ENV BERKELEYDB_VERSION=db-4.8.30.NC
ENV BERKELEYDB_PREFIX=/opt/${BERKELEYDB_VERSION}

RUN wget https://download.oracle.com/berkeley-db/${BERKELEYDB_VERSION}.tar.gz
RUN tar -xzf *.tar.gz
RUN sed s/__atomic_compare_exchange/__atomic_compare_exchange_db/g -i ${BERKELEYDB_VERSION}/dbinc/atomic.h
RUN mkdir -p ${BERKELEYDB_PREFIX}

WORKDIR /${BERKELEYDB_VERSION}/build_unix

RUN ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=${BERKELEYDB_PREFIX}
RUN make -j$(nproc)
RUN make install
RUN rm -rf ${BERKELEYDB_PREFIX}/docs

# Build stage for Raven Core
FROM alpine as raven-core

COPY --from=berkeleydb /opt /opt

RUN apk --no-cache add autoconf
RUN apk --no-cache add automake
RUN apk --no-cache add boost-dev
RUN apk --no-cache add build-base
RUN apk --no-cache add chrpath
RUN apk --no-cache add file
RUN apk --no-cache add gnupg
RUN apk --no-cache add libevent-dev
RUN apk --no-cache add libtool
RUN apk --no-cache add linux-headers
RUN apk --no-cache add protobuf-dev
RUN apk --no-cache add zeromq-dev
RUN apk --no-cache add cmake
RUN apk --no-cache add git
RUN apk --no-cache add openssl-dev

RUN set -ex \
  && for key in \
    90C8019E36C2E964 \
  ; do \
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" || \
    gpg --batch --keyserver pgp.mit.edu --recv-keys "$key" || \
    gpg --batch --keyserver keyserver.pgp.com --recv-keys "$key" || \
    gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$key" || \
    gpg --batch --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys "$key" ; \
  done

ENV RAVEN_PREFIX=/opt/raven

RUN git clone https://github.com/RavenProject/Ravencoin /raven

WORKDIR /raven

RUN ./autogen.sh
RUN ./configure LDFLAGS=-L`ls -d /opt/db-*`/lib/ CPPFLAGS=-I`ls -d /opt/db-*`/include/ \
    --disable-tests \
    --disable-bench \
    --disable-ccache \
    --disable-man \
    --without-gui \
    --with-libs=no \
    --with-daemon \
    --prefix=${RAVEN_PREFIX}

RUN make -j$(nproc) install

RUN strip ${RAVEN_PREFIX}/bin/raven-cli
RUN strip ${RAVEN_PREFIX}/bin/ravend

# Build stage for compiled artifacts
FROM alpine

RUN apk --no-cache add \
  boost \
  boost-program_options \
  libevent \
  libzmq \
  su-exec \
  git

ENV DATA_DIR=/home/raven/.raven
ENV RAVEN_PREFIX=/opt/raven
ENV PATH=${RAVEN_PREFIX}/bin:$PATH

COPY --from=raven-core /opt /opt

RUN mkdir -p ${DATA_DIR}
RUN set -x \
    && addgroup -g 1001 -S raven \
    && adduser -u 1001 -D -S -G raven raven
RUN chown -R 1001:1001 ${DATA_DIR}
USER raven
WORKDIR $DATA_DIR
