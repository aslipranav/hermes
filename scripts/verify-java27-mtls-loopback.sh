#!/usr/bin/env bash
set -euo pipefail

# Two independent Hermes identities are required to prove mTLS and signed ebMS.
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
database_image=${HERMES_E2E_DB_IMAGE:-mysql:8.4}
prefix="hermes-java27-mtls-$$"
network="${prefix}-network"
database="${prefix}-db"
partner_c="${prefix}-c"
partner_d="${prefix}-d"
port_c=${HERMES_MTLS_C_PORT:-18481}
port_d=${HERMES_MTLS_D_PORT:-18483}
tls_port_c=${HERMES_MTLS_C_TLS_PORT:-18443}
tls_port_d=${HERMES_MTLS_D_TLS_PORT:-18444}
# Docker Desktop can mount the checked-out workspace but not macOS app-sandbox temp paths.
temp_dir=$(mktemp -d "$repo_root/.hermes-java27-mtls.XXXXXX")
keystore_password=password

cleanup() {
  docker rm -f "$partner_c" "$partner_d" "$database" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  find "$temp_dir" -depth -delete
}
trap cleanup EXIT

wait_for_database() {
  for _ in {1..30}; do
    if docker exec "$database" mysql -uroot -phermes-test-root -e 'SELECT 1' >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done
  docker logs "$database"
  return 1
}

wait_for_gateway() {
  local port=$1
  for _ in {1..30}; do
    if [ "$(/usr/bin/curl --silent --max-time 2 -u apiuser:corvus -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/corvus/api/status")" = 200 ]; then
      return
    fi
    sleep 1
  done
  return 1
}

configure_partner() {
  local application=$1
  local identity=$2
  local schema_suffix=$3
  local tls_port=$4
  local keystore="/tmp/${identity}.p12"
  local core_module=/usr/local/tomcat/webapps/corvus/WEB-INF/classes/hk/hku/cecid/piazza/corvus/core/conf/corvus.module.xml
  local ebms_module=/hermes_home/plugins/corvus-ebms/conf/hk/hku/cecid/ebms/spa/conf/ebms.module.xml

  docker cp "$temp_dir/${identity}.p12" "$application:${keystore}"
  docker exec "$application" sh -c "cp '${keystore}' /hermes_home/plugins/corvus-ebms/security/corvus.p12"
  docker exec "$application" sh -c "sed -i 's#jdbc:mysql://db/ebms#jdbc:mysql://db/ebms_${schema_suffix}#' '${ebms_module}'"
  docker exec "$application" sh -c "sed -i 's#<parameter name=\"key-alias\" value=\"corvus\" />#<parameter name=\"key-alias\" value=\"partner-${identity}\" />#g' '${ebms_module}'"
  docker exec "$application" perl -0pi -e 's{<!-- Set up a SSL Trust Manager for SSL connection\s*(<component id="ssl-trust-manager".*?</component>)\s*-->}{$1}s; s{<!-- Set up a SSL Key Manager for SSL connection, it is configured in application server most case \(e\.g\. Tomcat server\.xml\)\s*(<component id="ssl-key-manager".*?</component>)\s*-->}{$1}s' "$core_module"
  docker exec "$application" sh -c "sed -i -e 's#/j2sdk1.4.2_04/jre/lib/security/cacerts#${keystore}#' -e 's#hk/hku/cecid/piazza/corvus/core/certs/cert.p12#${keystore}#' -e 's#value=\"changeit\"#value=\"${keystore_password}\"#' -e 's#value=\"mykey\"#value=\"partner-${identity}\"#' '${core_module}'"
  docker exec "$application" perl -0pi -e "s{</Service>}{  <Connector port=\"${tls_port}\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\" SSLEnabled=\"true\"><SSLHostConfig certificateVerification=\"required\" truststoreFile=\"${keystore}\" truststorePassword=\"${keystore_password}\" truststoreType=\"PKCS12\"><Certificate certificateKeystoreFile=\"${keystore}\" certificateKeystorePassword=\"${keystore_password}\" certificateKeystoreType=\"PKCS12\" certificateKeyAlias=\"partner-${identity}\" type=\"RSA\" /></SSLHostConfig></Connector>\n  </Service>}" /usr/local/tomcat/conf/server.xml
  docker restart "$application" >/dev/null
}

add_partnership() {
  local port=$1
  local id=$2
  local cpa=$3
  local endpoint=$4
  local certificate=$5
  local output=$6

  /usr/bin/curl --fail --silent --show-error --max-time 20 -u corvus:corvus \
    -F request_action=add -F partnership_id="$id" -F cpa_id="$cpa" \
    -F service=http://localhost:8080/corvus/httpd/ebms/inbound \
    -F action_id=SignedTestMessage -F disabled=false -F sync_reply_mode=none \
    -F transport_endpoint="$endpoint" -F is_hostname_verified=true \
    -F ack_requested=always -F ack_sign_requested=always -F dup_elimination=always \
    -F message_order=NotGuaranteed -F retries=1 -F retry_interval=1000 \
    -F sign_requested=true -F encrypt_requested=false -F verify_cert="@${certificate}" \
    "http://127.0.0.1:${port}/corvus/admin/ebms/partnership" > "$output"
  grep -q 'Partnership added successfully' "$output"
}

send_message() {
  local application=$1
  local cpa=$2
  local output=$3

  docker exec "$application" sh -c "sed -e 's#<cpaId>cpaid</cpaId>#<cpaId>${cpa}</cpaId>#' -e 's#<action>action</action>#<action>SignedTestMessage</action>#' /hermes_home/sample/config/ebms-partnership.xml > /tmp/mtls-partnership.xml && java -cp '/hermes_home/sample/lib/*' hk.hku.cecid.corvus.ws.EBMSMessageSender /tmp/mtls-partnership.xml /hermes_home/sample/config/ebms-send/ebms-request.xml /tmp/mtls-send.log /hermes_home/sample/config/ebms-send/testpayload" > "$output"
  sed -n 's/^New message id: //p' "$output"
}

cd "$repo_root"
if [ "${HERMES_E2E_SKIP_BUILD:-false}" != true ]; then
  docker build -q -f deploy/app_server/Dockerfile -t hermes-java27:local . >/dev/null
fi

for identity in c d; do
  docker run --rm -v "$temp_dir:/certs" --entrypoint keytool hermes-java27:local \
    -genkeypair -noprompt -alias "partner-${identity}" -keyalg RSA -keysize 2048 \
    -sigalg SHA256withRSA -validity 30 \
    -dname "CN=Partner ${identity},OU=Hermes Java 27 Test,O=Local Test,L=London,ST=London,C=GB" \
    -ext "SAN=dns:${identity},ip:127.0.0.1" -ext 'KU=digitalSignature,keyEncipherment' \
    -ext 'EKU=serverAuth,clientAuth' -storetype PKCS12 \
    -keystore "/certs/${identity}.p12" -storepass "$keystore_password" -keypass "$keystore_password"
  docker run --rm -v "$temp_dir:/certs" --entrypoint keytool hermes-java27:local \
    -exportcert -rfc -alias "partner-${identity}" -keystore "/certs/${identity}.p12" \
    -storetype PKCS12 -storepass "$keystore_password" -file "/certs/${identity}.pem"
done
docker run --rm -v "$temp_dir:/certs" --entrypoint keytool hermes-java27:local \
  -importcert -noprompt -alias partner-d-peer -file /certs/d.pem -storetype PKCS12 \
  -keystore /certs/c.p12 -storepass "$keystore_password"
docker run --rm -v "$temp_dir:/certs" --entrypoint keytool hermes-java27:local \
  -importcert -noprompt -alias partner-c-peer -file /certs/c.pem -storetype PKCS12 \
  -keystore /certs/d.p12 -storepass "$keystore_password"

docker network create "$network" >/dev/null
docker run -d --name "$database" --network "$network" --network-alias db \
  --tmpfs /var/lib/mysql:rw,size=512m -e MYSQL_ROOT_PASSWORD=hermes-test-root \
  "$database_image" >/dev/null
wait_for_database
docker exec "$database" mysql -uroot -phermes-test-root -e "CREATE DATABASE ebms_c; CREATE DATABASE ebms_d; CREATE DATABASE as2_c; CREATE DATABASE as2_d; CREATE USER 'corvus'@'%' IDENTIFIED BY 'corvus'; GRANT ALL PRIVILEGES ON *.* TO 'corvus'@'%'; FLUSH PRIVILEGES;"
for schema in ebms_c ebms_d; do docker exec -i "$database" mysql -uroot -phermes-test-root "$schema" < h2o-installer/sql/mysql_ebms.sql; done
for schema in as2_c as2_d; do docker exec -i "$database" mysql -uroot -phermes-test-root "$schema" < h2o-installer/sql/mysql_as2.sql; done

docker run -d --name "$partner_c" --network "$network" --network-alias c -p "${port_c}:8080" -p "${tls_port_c}:8443" hermes-java27:local >/dev/null
docker run -d --name "$partner_d" --network "$network" --network-alias d -p "${port_d}:8080" -p "${tls_port_d}:8443" hermes-java27:local >/dev/null
wait_for_gateway "$port_c"
wait_for_gateway "$port_d"
configure_partner "$partner_c" c c 8443
configure_partner "$partner_d" d d 8443
wait_for_gateway "$port_c"
wait_for_gateway "$port_d"

if /usr/bin/curl --silent --show-error --max-time 5 --cacert "$temp_dir/d.pem" -u apiuser:corvus "https://127.0.0.1:${tls_port_d}/corvus/api/status" >/dev/null 2>&1; then
  echo 'mTLS endpoint accepted a client without a certificate' >&2
  exit 1
fi
/usr/bin/curl --fail --silent --show-error --max-time 10 --cacert "$temp_dir/d.pem" \
  --cert "$temp_dir/c.p12:${keystore_password}" --cert-type P12 -u apiuser:corvus \
  "https://127.0.0.1:${tls_port_d}/corvus/api/status" | grep -q '"status":"healthy"'

add_partnership "$port_c" c-to-d urn:ebms:test:c-to-d https://d:8443/corvus/httpd/ebms/inbound "$temp_dir/d.pem" "$temp_dir/c-to-d.html"
add_partnership "$port_d" c-to-d urn:ebms:test:c-to-d https://c:8443/corvus/httpd/ebms/inbound "$temp_dir/c.pem" "$temp_dir/d-c-to-d.html"
add_partnership "$port_d" d-to-c urn:ebms:test:d-to-c https://c:8443/corvus/httpd/ebms/inbound "$temp_dir/c.pem" "$temp_dir/d-to-c.html"
add_partnership "$port_c" d-to-c urn:ebms:test:d-to-c https://d:8443/corvus/httpd/ebms/inbound "$temp_dir/d.pem" "$temp_dir/c-d-to-c.html"

c_message_id=$(send_message "$partner_c" urn:ebms:test:c-to-d "$temp_dir/c-send.out")
d_message_id=$(send_message "$partner_d" urn:ebms:test:d-to-c "$temp_dir/d-send.out")
[ -n "$c_message_id" ] && [ -n "$d_message_id" ]
for _ in {1..45}; do
  c_inbox=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms_d -e "SELECT COUNT(*) FROM inbox WHERE message_id = '${c_message_id}'")
  d_inbox=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms_c -e "SELECT COUNT(*) FROM inbox WHERE message_id = '${d_message_id}'")
  c_status=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms_c -e "SELECT status FROM message WHERE message_id = '${c_message_id}' AND message_box = 'outbox'")
  d_status=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms_d -e "SELECT status FROM message WHERE message_id = '${d_message_id}' AND message_box = 'outbox'")
  c_ack_rows=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms_c -e "SELECT COUNT(*) FROM message WHERE ref_to_message_id = '${c_message_id}' AND message_box = 'inbox' AND message_type = 'Acknowledgement' AND status = 'PS'")
  d_ack_rows=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms_d -e "SELECT COUNT(*) FROM message WHERE ref_to_message_id = '${d_message_id}' AND message_box = 'inbox' AND message_type = 'Acknowledgement' AND status = 'PS'")
  [ "$c_inbox/$d_inbox/$c_status/$d_status/$c_ack_rows/$d_ack_rows" = '1/1/PS/PS/1/1' ] && break
  sleep 1
done
[ "$c_inbox/$d_inbox/$c_status/$d_status/$c_ack_rows/$d_ack_rows" = '1/1/PS/PS/1/1' ]
c_ack_id=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms_c -e "SELECT message_id FROM message WHERE ref_to_message_id = '${c_message_id}' AND message_box = 'inbox' AND message_type = 'Acknowledgement' AND status = 'PS'")
d_ack_id=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms_d -e "SELECT message_id FROM message WHERE ref_to_message_id = '${d_message_id}' AND message_box = 'inbox' AND message_type = 'Acknowledgement' AND status = 'PS'")
[ -n "$c_ack_id" ] && [ -n "$d_ack_id" ]
docker exec "$partner_d" grep -q "Signature verification success: ${c_message_id}" /hermes_home/logs/ebms.log
docker exec "$partner_c" grep -q "Signature verification success: ${d_message_id}" /hermes_home/logs/ebms.log
docker exec "$partner_c" grep -q "Signature verification success: ${c_ack_id}" /hermes_home/logs/ebms.log
docker exec "$partner_d" grep -q "Signature verification success: ${d_ack_id}" /hermes_home/logs/ebms.log
docker exec "$partner_c" grep -q "Reliable message (${c_message_id}) - acknowledgement received" /hermes_home/logs/ebms.log
docker exec "$partner_d" grep -q "Reliable message (${d_message_id}) - acknowledgement received" /hermes_home/logs/ebms.log
printf 'Java 27 two-party mTLS signed ebMS passed: %s %s\n' "$c_message_id" "$d_message_id"
