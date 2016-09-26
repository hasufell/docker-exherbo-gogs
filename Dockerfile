FROM       hasufell/exherbo:latest
MAINTAINER Julian Ospald <hasufell@posteo.de>


COPY ./config/paludis /etc/paludis
COPY ./config/repositories /var/db/paludis/repositories


##### PACKAGE INSTALLATION #####

RUN chgrp paludisbuild /dev/tty && \
	eclectic env update && \
	source /etc/profile && \
	cave sync && \
	cave resolve -z -1 repository/CleverCloud -x && \
	cave resolve -z -1 repository/hasufell -x && \
	cave resolve -z -1 repository/python -x && \
	cave resolve -z -1 dev-lang/go -x && \
	rm /etc/paludis/options.conf.d/bootstrap.conf && \
	cave resolve -c world -x && \
	cave resolve -c gogs -x && \
	cave resolve -c tools -x && \
	cave purge -x && \
	cave fix-linkage -x && \
	rm -rf /var/cache/paludis/distfiles/* \
		/var/tmp/paludis/build/*

RUN eclectic config accept-all


################################


ENV GOPATH /gopath
ENV PATH $PATH:$GOROOT/bin:$GOPATH/bin

WORKDIR /gopath/src/github.com/gogits/gogs/
RUN git clone --depth=1 https://github.com/gogits/gogs.git \
	/gopath/src/github.com/gogits/gogs

# Build binary and clean up useless files
RUN go get -v -tags "sqlite redis memcache cert pam" && \
	go build -tags "sqlite redis memcache cert pam" && \
	mkdir /app/ && \
	mv /gopath/src/github.com/gogits/gogs/ /app/gogs/ && \
	rm -r "$GOPATH"


WORKDIR /app/gogs/

RUN useradd --shell /bin/bash --system --comment gogits git

# SSH login fix, otherwise user is kicked off after login
RUN echo "export VISIBLE=now" >> /etc/profile && \
	echo "PermitUserEnvironment yes" >> /etc/ssh/sshd_config

# Setup server keys on startup
RUN echo "HostKey /data/ssh/ssh_host_rsa_key" >> /etc/ssh/sshd_config && \
	echo "HostKey /data/ssh/ssh_host_dsa_key" >> /etc/ssh/sshd_config && \
	echo "HostKey /data/ssh/ssh_host_ed25519_key" >> /etc/ssh/sshd_config

# Prepare data
ENV GOGS_CUSTOM /data/gogs
RUN echo "export GOGS_CUSTOM=/data/gogs" >> /etc/profile

# set up redis
RUN mkdir /var/log/redis && \
	chown -R redis /var/log/redis && \
	chown -R redis /var/db/redis/ && \
	sed -i \
		-e 's#^logfile .*#logfile "/var/log/redis/redis-server.log"#' \
		-e 's#^dir .*#dir /var/db/redis/#' \
		/etc/redis.conf

COPY setup.sh /setup.sh
RUN chmod +x /setup.sh
COPY config/supervisord.conf /etc/supervisord.conf

EXPOSE 3000

CMD /setup.sh && exec /usr/bin/supervisord -n -c /etc/supervisord.conf
