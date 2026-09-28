FROM maven:3.9-eclipse-temurin-25 AS maven

FROM amazoncorretto:27 AS build

COPY --from=maven /usr/share/maven /usr/share/maven
ENV MAVEN_HOME=/usr/share/maven
ENV PATH=${MAVEN_HOME}/bin:${PATH}

RUN \
    cp -a "$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")" /opt/corretto

WORKDIR /build
COPY . .
# The legacy POM installs this bundled dependency only during pre-clean; a
# container build starts with an empty Maven repository, so install it first.
RUN mvn -B -ntp org.apache.maven.plugins:maven-install-plugin:3.1.3:install-file \
      -Dfile=/build/corvus-wsclient/lib/tidy-1.0.jar \
      -DgroupId=tidy \
      -DartifactId=tidy \
      -Dversion=1.0 \
      -Dpackaging=jar && \
    mvn -B -ntp package -Dmaven.test.skip=true && \
    mvn -B -ntp org.apache.maven.plugins:maven-dependency-plugin:3.8.1:copy \
      -Dartifact=com.mysql:mysql-connector-j:26.7.0 \
      -DoutputDirectory=/build/target

FROM tomcat:9.0-jre25-temurin

RUN apt-get update && apt-get install -y --no-install-recommends perl-base unzip && rm -rf /var/lib/apt/lists/*

# Tomcat 9 preserves the javax.servlet API Hermes requires; Corretto supplies
# the current JDK because no Tomcat 9 JDK 27 image is published yet.
COPY --from=build /opt/corretto /opt/java/corretto
ENV JAVA_HOME=/opt/java/corretto
ENV PATH=${JAVA_HOME}/bin:${PATH}

COPY deploy/app_server/tomcat-users.xml $CATALINA_HOME/conf/tomcat-users.xml
COPY --from=build /build/target/hermes2_bin.zip /tmp/hermes2_bin.zip
COPY --from=build /build/target/mysql-connector-j-26.7.0.jar /tmp/mysql.jar

RUN mkdir -p /hermes_home/logs /tmp/h && \
    unzip /tmp/hermes2_bin.zip -d /tmp/h && \
    rm -rf /tmp/h/plugins/corvus-sfrm \
      /tmp/h/plugins/corvus-sfrm-admin \
      /tmp/h/plugins/corvus-as2plus \
      /tmp/h/plugins/corvus-as2plus-admin && \
    find /tmp/h -name '*.xml' -exec sed -i \
      -e 's/@h2\.home@/\/hermes_home/g' \
      -e 's/@as2PageletAdaptor@/hk\.hku\.cecid\.edi\.as2\.admin\.listener\.MessageHistoryPageletAdaptor/g' \
      -e 's/@as2DriverClass@/com\.mysql\.cj\.jdbc\.Driver/g' \
      -e 's/@as2ConnStr@/jdbc:mysql:\/\/db\/as2/g' \
      -e 's/@as2user@/corvus/g' \
      -e 's/@as2pw@/corvus/g' \
      -e 's/@as2ValidationQuery@/SELECT now\(\)/g' \
      -e 's/@as2DAOFile@/hk\/hku\/cecid\/edi\/as2\/conf\/as2.dao.xml/g' \
      -e 's/@ebmsPageletAdaptor@/hk\.hku\.cecid\.ebms\.admin\.listener\.MessageHistoryPageletAdaptor/g' \
      -e 's/@ebmsDriverClass@/com\.mysql\.cj\.jdbc\.Driver/g' \
      -e 's/@ebmsConnStr@/jdbc:mysql:\/\/db\/ebms/g' \
      -e 's/@ebmsuser@/corvus/g' \
      -e 's/@ebmspw@/corvus/g' \
      -e 's/@ebmsValidationQuery@/SELECT now\(\)/g' \
      -e 's/@ebmsDAOFile@/hk\/hku\/cecid\/ebms\/spa\/conf\/ebms.mysql.dao.xml/g' {} + && \
    mv /tmp/h/plugins /hermes_home && \
    mv /tmp/h/sample /hermes_home && \
    mv /tmp/h/sql /hermes_home && \
    cp /tmp/mysql.jar /tmp/h/webapps/corvus/WEB-INF/lib/ && \
    mv /tmp/h/webapps/corvus $CATALINA_HOME/webapps/corvus && \
    rm -rf /tmp/h /tmp/hermes2_bin.zip /tmp/mysql.jar

EXPOSE 8080
