FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    libbz2-dev \
    libcurl4-openssl-dev \
    liblzma-dev \
    libncurses-dev \
    procps \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

RUN curl -L https://bitbucket.org/genomicepidemiology/kma/get/1.5.0.tar.gz -o kma.tar.gz \
    && mkdir kma \
    && tar -xzf kma.tar.gz --strip-components=1 -C kma \
    && make -C kma \
    && cp kma/kma kma/kma_index kma/kma_shm kma/kma_update /usr/local/bin/

RUN curl -L https://github.com/samtools/samtools/releases/download/1.22.1/samtools-1.22.1.tar.bz2 -o samtools.tar.bz2 \
    && mkdir samtools \
    && tar -xjf samtools.tar.bz2 --strip-components=1 -C samtools \
    && cd samtools \
    && ./configure \
    && make \
    && make install

RUN rm -rf /tmp/*

WORKDIR /

CMD ["/bin/bash"]
