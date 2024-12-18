FROM alpine:3.12.5
LABEL maintainer="Ank"

# -----------------------------------------------------------------------------
# Permissions
# -----------------------------------------------------------------------------
# https://vsupalov.com/docker-shared-permissions/

ARG USER_ID
ARG GROUP_ID

RUN addgroup --gid $GROUP_ID intermine
RUN adduser -D -g '' -u $USER_ID -G intermine intermine

ENV JAVA_HOME="/usr/lib/jvm/default-jvm"

RUN apk add --no-cache openjdk8 openjdk8-jre && \
    ln -sf "${JAVA_HOME}/bin/"* "/usr/bin/"

RUN apk add --no-cache bash \
                       git \
                       maven \
                       postgresql-client \
                       perl \
                       perl-utils

RUN apk add --no-cache build-base
RUN apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing perl-moosex
RUN apk add --no-cache wget \
                        perl-module-build \
                        perl-module-build-tiny \
                        perl-package-stash \
                        perl-sub-identify \
                        perl-moose \
                        perl-datetime \
                        perl-html-parser \
                        perl-html-tree \
                        perl-io-gzip \
                        perl-list-moreutils-xs \
                        perl-text-csv_xs \
                        perl-xml-libxml \
                        perl-xml-parser

RUN perl -MCPAN -e \
'my $c = "CPAN::HandleConfig"; $c->load(doit => 1, autoconfig => 1); $c->edit(prerequisites_policy => "follow"); $c->edit(build_requires_install_policy => "yes"); $c->commit'

RUN cpan -i App::cpanminus

RUN cpanm --force Ouch \
                  LWP \
                  URI \
                  Module::Find \
                  Web::Scraper \
                  Number::Format \
                #   PerlIO::gzip \
                  Perl6::Junction \
                #   List::MoreUtils \
                  Module::Find \
                #   Moose \
                #   MooseX::Role::WithOverloading \
                  MooseX::Types \
                  MooseX::FollowPBP \
                  MooseX::ABC \
                  MooseX::FileAttribute \
                #   Text::CSV_XS \
                  Text::Glob \
                  XML::Parser::PerlSAX \
                  XML::DOM
                #  Getopt::Std \
                #  Digest::MD5 \
                #  Log::Handler

ENV MEM_OPTS="-Xmx1g -Xms500m"
ENV GRADLE_OPTS="-server ${MEM_OPTS} -XX:+UseParallelGC -XX:SoftRefLRUPolicyMSPerMB=1 -XX:MaxHeapFreeRatio=99 -Dorg.gradle.daemon=false -Duser.home=/home/intermine"
ENV HOME="/home/intermine"
ENV USER_HOME="/home/intermine"
ENV GRADLE_USER_HOME="/home/intermine/.gradle"
ENV PSQL_USER="postgres"
ENV PSQL_PWD="postgres"
ENV TOMCAT_USER="tomcat"
ENV TOMCAT_PWD="tomcat"
ENV TOMCAT_PORT=8080
ENV PGPORT=5432

RUN mkdir /home/intermine/intermine
COPY ./build.sh /home/intermine
RUN chown -R intermine:intermine /home/intermine
RUN chmod u+x /home/intermine/build.sh

COPY ./wait-for-it/wait-for-it.sh /usr/local/bin/wait-for-it
RUN chmod +x /usr/local/bin/wait-for-it

WORKDIR /home/intermine/intermine

USER intermine

CMD ["/bin/sh","/home/intermine/build.sh"]
