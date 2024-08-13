FROM quay.io/centos/centos:stream9

ENV BUNDLER_VERSION="2.2.25"

ARG DB=mysql

ENV PATH="./node_modules/.bin:$PATH" \
    DISPLAY=:99.0 \
    SKIP_ASSETS="1" \
    TZ=:/etc/localtime \
    LD_LIBRARY_PATH="/opt/oracle/instantclient/:$LD_LIBRARY_PATH" \
    ORACLE_HOME=/opt/oracle/instantclient/ \
    # This is to fix 'error:0308010C:digital envelope routines::unsupported' in Node 18
    # the proper fix should be upgrading webpack and babel-loader
    NODE_OPTIONS='--openssl-legacy-provider' \
    DB=$DB

USER root

RUN dnf -y module enable ruby:3.1 nodejs:18 \
    && dnf install -y --setopt=skip_missing_names_on_install=False,tsflags=nodocs --enablerepo=crb \
        ruby-devel rubygem-irb \
        nodejs \
        sudo which file shared-mime-info unzip jq git \
        postgresql libpq-devel mysql-devel zlib-devel gd-devel libxml2-devel libxslt-devel \
        make automake gcc gcc-c++ \
        # needed for PDF generation \
        liberation-sans-fonts \
        # needed for ruby-oci8 gem \
        libnsl libaio \
        # needed to download memkind/jemalloc sources \
        'dnf-command(download)' cpio \
    && echo --color > ~/.rspec \
    && gem install bundler --version ${BUNDLER_VERSION} --no-doc \
    && echo 'default        ALL=(ALL)       NOPASSWD: ALL' >> /etc/sudoers \
    && npm install -g yarn \
    && rm -rf ~/.npm ~/.config

# we can just install memkind package once it is fixed, see
# https://issues.redhat.com/browse/RHEL-14497
RUN mkdir /tmp/memkind \
    && cd /tmp/memkind \
    && dnf download --source memkind \
    && rpm2cpio memkind-*.src.rpm | cpio -idmv "memkind-*.tar.gz" \
    && tar xvfz memkind-*.tar.gz \
    && cd memkind-*/jemalloc/ \
    && ./autogen.sh && ./configure --libdir=/usr/local/lib64/ && make install \
    && echo /usr/local/lib64 > /etc/ld.so.conf.d/jemalloc.conf \
    && ldconfig && ldconfig -p | grep jemalloc \
    && cd && rm -rf /tmp/memkind

RUN dnf install -y --setopt=skip_missing_names_on_install=False,tsflags=nodocs firefox wget \
  && wget -N --progress=dot:giga -O /tmp/google-chrome-stable-126.rpm "https://dl.google.com/linux/chrome/rpm/stable/x86_64/google-chrome-stable-126.0.6478.126-1.x86_64.rpm" \
  && dnf install -y /tmp/google-chrome-stable-126.rpm \
  && CHROME_VERSION=$(google-chrome --version | sed -e "s|[^0-9]*\([0-9]\+\).*|\1|") \
  && wget -N --progress=dot:giga "https://storage.googleapis.com/chrome-for-testing-public/126.0.6478.126/linux64/chromedriver-linux64.zip" -O /tmp/chromedriver-linux64.zip \
  && unzip -j /tmp/chromedriver-linux64.zip -d /tmp \
  && rm /tmp/chromedriver-linux64.zip \
  && mv -f /tmp/chromedriver /usr/local/bin/chromedriver \
  && chown root:root /usr/local/bin/chromedriver \
  && chmod 0755 /usr/local/bin/chromedriver

# geckodriver
RUN geckodriver=$(curl -s https://api.github.com/repos/mozilla/geckodriver/releases/latest | jq -r '.assets[].browser_download_url | select(contains("linux64") and (endswith(".asc") | not))') \
  && curl -sL "$geckodriver" | tar -xzv -C /usr/local/bin/

# manticore search
RUN dnf install -y https://repo.manticoresearch.com/manticore-repo.noarch.rpm \
  && dnf install -y manticore-server

WORKDIR /opt/ci

RUN uuidgen | tee /etc/machine-id \
 && useradd -d /opt/ci -r default \
 && chown -R default /opt/ci \
 && chmod -R g+w /opt/ci \
 && dnf clean all -y

# TODO: circleci fails "Preparing environment variables" with these
# ENV LD_PRELOAD=libautohbw.so.0 \
#     AUTO_HBW_SIZE=10240G \
#     AUTO_HBW_LOG=-2 \
#     MEMKIND_HBW_NODES=0 \
#     MEMKIND_HEAP_MANAGER=JEMALLOC
# RUN ldd /bin/grep | grep libautohbw.so.0

USER default

ENTRYPOINT ["/bin/bash", "-c", "exec \"$@\"", "--"]
