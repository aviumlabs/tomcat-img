# syntax=docker/dockerfile:1
FROM alpine:3.24

ENV INSTANCE_NAME="tc1"
ENV BACKUP_HOME=/opt/backup
ENV SECRETS_HOME=/opt/secrets
ENV CATALINA_BASE="/opt/tomcat/instances/${INSTANCE_NAME}"
ENV CATALINA_HOME=/usr/local/tomcat
ENV PATH=$CATALINA_HOME/bin:$PATH
ENV JAVA_HOME=/usr/lib/jvm/default-jvm
ENV WORKDIR=/opt/tomcat
ENV TOMCAT_NATIVE_LIBDIR=$CATALINA_HOME/native-jni-lib
ENV LD_LIBRARY_PATH=/usr/lib:/usr/local/lib:${TOMCAT_NATIVE_LIBDIR}
ENV MGR_PASS_FILE=
ENV RPAUSER_PASS_FILE=
ENV JMXUSER_PASS_FILE=
ENV TC_SECURE_PORT=8443


RUN mkdir -p "${CATALINA_HOME}"

RUN set -eux; \
   addgroup -g 935 -S tomcat; \
   adduser -u 935 -S -D -G tomcat -H -h /opt/tomcat -s /bin/ash tomcat; \
   install --verbose --directory --owner tomcat --group tomcat --mode 1755 /opt/tomcat
   
RUN apk add --no-cache \
   openjdk21-jdk \
   openssl \
   python3 \
   py3-rich \
   py3-requests \
   pwgen \
   jsvc \
   curl

ENV TOMCAT_VERSION="9.0.121" \
    TOMCAT_NATIVE_VERSION="2.0.15" 
	#COMMONS_DAEMON_VERSION="1.5.1"

RUN set -xe \
	&& TOMCAT_DOWNLOAD_URL="https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz" \
	&& TOMCAT_DOWNLOAD_SHA512="16494dd4745f808d3c506807b5275521fd71044d976f441d18eeeab0f5a38bc1b5344ca395292f6f26eb7612cd8c8e746d01ccdfb29893d394052d9f4b1f4c11" \
	&& TOMCAT_NATIVE_DOWNLOAD_URL="https://archive.apache.org/dist/tomcat/tomcat-connectors/native/${TOMCAT_NATIVE_VERSION}/source/tomcat-native-${TOMCAT_NATIVE_VERSION}-src.tar.gz" \
	&& TOMCAT_NATIVE_DOWNLOAD_SHA512="a0b53890c36c3409e764895cfc521cdbbc49af4d03968f5d3ed72ba686524a05bd15c3f7ab8259fbab091547ecbc2fb7aae8f47d8bc38027db0f6a5dbda65004" \
	&& COMMONS_DAEMON_DOWNLOAD_URL="https://github.com/apache/commons-daemon/archive/refs/tags/commons-daemon-${COMMONS_DAEMON_VERSION}.tar.gz" \
	&& apk add --no-cache --virtual .fetch-deps \
		curl \
		ca-certificates \
    && curl -fSL -o tomcat.tar.gz "$TOMCAT_DOWNLOAD_URL" \
    && echo "$TOMCAT_DOWNLOAD_SHA512  tomcat.tar.gz" | sha512sum -c - \
    && tar -xzf tomcat.tar.gz -C $CATALINA_HOME --strip-components=1 \
    && rm tomcat.tar.gz \
	&& mkdir -p $BACKUP_HOME \
	&& mkdir -p $CATALINA_BASE \
	&& mkdir -p $SECRETS_HOME \
	&& chown -R tomcat:tomcat $CATALINA_BASE \
    && chown -R tomcat:tomcat $CATALINA_HOME \
	&& chown -R tomcat:tomcat $BACKUP_HOME \
	&& chown -R tomcat:tomcat $SECRETS_HOME \
	# Backup default webapps 
	&& tar -czf $BACKUP_HOME/default-webapps-${TOMCAT_VERSION}.tar.gz -C $CATALINA_HOME/webapps . \
	# Remove default webapps 
	&& rm -rf $CATALINA_HOME/webapps/docs \
	&& rm -rf $CATALINA_HOME/webapps/examples \
	&& rm -rf $CATALINA_HOME/webapps/ROOT \
    && chmod +x $CATALINA_HOME/bin/*.sh \
	# Compile and install Tomcat Native and Commons Daemon (jsvc) 
	&& curl -fSL -o tnative-src.tar.gz "$TOMCAT_NATIVE_DOWNLOAD_URL" \
	&& echo "$TOMCAT_NATIVE_DOWNLOAD_SHA512  tnative-src.tar.gz" | sha512sum -c - \
	&& apk add --no-cache --virtual .build-deps \
		dpkg-dev dpkg \
		gcc \
        g++ \
		make \
        autoconf \
		automake \
        apr \
		apr-dev \
		libcap-dev \
		openssl-dev \
		tar \
	&& export TN_TOP="/usr/src/tnative_src_${TOMCAT_NATIVE_VERSION%%@*}" \
	&& mkdir -vp $TN_TOP \
	&& tar -xzf tnative-src.tar.gz -C $TN_TOP --strip-components=1 \
	&& rm tnative-src.tar.gz \
	&& ( cd $TN_TOP/native \
	  && gnuArch="$(dpkg-architecture --query DEB_HOST_GNU_TYPE)" \
      && aprConfig="$(command -v apr-1-config)" \
	  && ./configure --build="$gnuArch" \
			--libdir="$TOMCAT_NATIVE_LIBDIR" \
			--prefix="$CATALINA_HOME" \
			--with-apr="$aprConfig" \
			--with-java-home="$JAVA_HOME" \
			--with-ssl=/usr \
	  && make -j$(getconf _NPROCESSORS_ONLN) \
	  && make install ) \
	&& rm -rf $TN_TOP \
	&& find /usr/local -regex '/usr/local/tomcat/native-jni-lib).*/\(man\|doc\|obj\|c_src\|emacs\|info\|examples\)' | xargs rm -rf \
	&& scanelf --nobanner -E ET_EXEC -BF '%F' --recursive /usr/local | xargs -r strip --strip-all \
	&& scanelf --nobanner -E ET_DYN -BF '%F' --recursive /usr/local | xargs -r strip --strip-unneeded \
	&& runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/tomcat/native-jni-lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)" \
	# Compiling Commons Daemon (jsvc) fails on GCC 15 due to true/false keyword conflict
	#&& curl -fSL -o commons-daemon.tar.gz "$COMMONS_DAEMON_DOWNLOAD_URL" \
	#&& export JSVC_TOP="/usr/src/common_daemons_src" \
	#&& mkdir -vp $JSVC_TOP \
	#&& tar -xzf commons-daemon.tar.gz -C $JSVC_TOP --strip-components=1 \
	# /usr/src/common_daemons_src/src/native/unix/native/jsvc.h
	#&& ( cd $JSVC_TOP/src/native/unix \
	#  && sh support/buildconf.sh \
	#  && gnuArch="$(dpkg-architecture --query DEB_HOST_GNU_TYPE)" \
	#  && ./configure --build="$gnuArch" \
	#  && make \
	#  && cp jsvc "$CATALINA_HOME/bin/" ) \
	#&& rm -rf $JSVC_TOP \
	&& apk add --virtual .tomcat-rundeps \
		$runDeps \
        apr \
	&& apk del .fetch-deps .build-deps \
	&& mkdir ${CATALINA_BASE}/bin \
	&& mkdir ${CATALINA_BASE}/conf \
	&& mkdir ${CATALINA_BASE}/lib \
	&& mkdir ${CATALINA_BASE}/logs \
	&& ln -s ${CATALINA_BASE}/logs ${CATALINA_BASE}/temp \
	&& mkdir ${CATALINA_BASE}/webapps \
	&& mkdir ${CATALINA_BASE}/work \
	# copy Tomcat files to CATALINA_BASE
	&& cp "$CATALINA_HOME/bin/tomcat-juli.jar" "$CATALINA_BASE/bin/" \
    && cp "$CATALINA_HOME/conf/server.xml" "$CATALINA_BASE/conf/" \
    && cp "$CATALINA_HOME/conf/web.xml" "$CATALINA_BASE/conf/" \
    && cp "$CATALINA_HOME/conf/tomcat-users.xml" "$CATALINA_BASE/conf/" \
    && cp "$CATALINA_HOME/conf/logging.properties" "$CATALINA_BASE/conf/" \
	&& chown -R tomcat:tomcat $CATALINA_BASE

COPY tomcat.config "$SECRETS_HOME/"
RUN chown tomcat:tomcat "$SECRETS_HOME/tomcat.config"

COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT [ "entrypoint.sh" ]

USER tomcat

# verify Tomcat Native is working properly
RUN set -eux \
	&& nativeLines="$(catalina.sh configtest 2>&1)" \
	&& nativeLines="$(echo "$nativeLines" | grep 'Apache Tomcat Native')" \
	&& nativeLines="$(echo "$nativeLines" | sort -u)" \
	&& if ! echo "$nativeLines" | grep -E 'INFO: Loaded( APR based)? Apache Tomcat Native library' >&2; then \
		echo >&2 "$nativeLines"; \
		exit 1; \
	fi

EXPOSE 8080
EXPOSE 8443

CMD [ "catalina.sh", "run" ]