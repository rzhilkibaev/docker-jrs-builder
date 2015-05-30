# vim:set ft=dockerfile:
FROM traxair/oracle-java7

RUN apt-get update && apt-get install -y subversion ant ant-contrib

# maven
RUN wget -qO- http://mirrors.ibiblio.org/apache/maven/maven-3/3.2.5/binaries/apache-maven-3.2.5-bin.tar.gz \
    | tar xz -C /opt
ENV M2_HOME /opt/apache-maven-3.2.5
ENV PATH $M2_HOME/bin:$PATH

COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["help"]
