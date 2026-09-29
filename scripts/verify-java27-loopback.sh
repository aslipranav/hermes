#!/usr/bin/env bash
set -euo pipefail

# This is a disposable runtime check against the supported MySQL 8.4 image.
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
port=${HERMES_E2E_PORT:-18080}
mail_pop_port=${HERMES_E2E_MAIL_POP_PORT:-18110}
database_image=${HERMES_E2E_DB_IMAGE:-hermes-java27-db:local}
ebms_dump=${HERMES_EBMS_DUMP:-}
as2_dump=${HERMES_AS2_DUMP:-}
prefix="hermes-java27-e2e-$$"
network="${prefix}-network"
database="${prefix}-db"
application="${prefix}-app"
mail_server="${prefix}-mail"
temp_dir=$(mktemp -d "$repo_root/.hermes-java27-loopback.XXXXXX")
mail_username=recipient
mail_password=hermes-test-mail-password
loopback_cpa_id="cpaid-${prefix}"
loopback_action="action-${prefix}"
as2_partnership_id="as2-${prefix}"
as2_identity="as2loopback$$"

if [ -n "$ebms_dump" ] || [ -n "$as2_dump" ]; then
  [ -n "$ebms_dump" ] && [ -n "$as2_dump" ]
  [ -f "$ebms_dump" ] && [ -f "$as2_dump" ]
  use_legacy_dumps=true
else
  use_legacy_dumps=false
fi

cleanup() {
  docker rm -f "$application" "$mail_server" "$database" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  find "$temp_dir" -depth -delete
}
trap cleanup EXIT

wait_for_database() {
  for _ in {1..30}; do
    if docker exec "$database" mysql --protocol=TCP -h127.0.0.1 -uroot -phermes-test-root -e 'SELECT 1' >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done
  docker logs "$database"
  return 1
}

wait_for_gateway() {
  for _ in {1..30}; do
    if [ "$(/usr/bin/curl --silent --max-time 2 -u apiuser:corvus -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/corvus/api/status")" = "200" ]; then
      return
    fi
    sleep 1
  done
  docker logs "$application"
  return 1
}

wait_for_mail_server() {
  for _ in {1..30}; do
    if nc -z 127.0.0.1 "$mail_pop_port" >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done
  docker logs "$mail_server"
  return 1
}

cd "$repo_root"
if [ -z "${HERMES_E2E_DB_IMAGE:-}" ]; then
  docker build -q -f deploy/db/Dockerfile -t "$database_image" . >/dev/null
fi
if [ "${HERMES_E2E_SKIP_BUILD:-false}" != true ]; then
  docker build -q -f deploy/app_server/Dockerfile -t hermes-java27:local . >/dev/null
fi
cp corvus-ebms/src/main/spa/conf/hk/hku/cecid/ebms/spa/conf/ebms.properties.xml "$temp_dir/ebms.properties.xml"
sed -i.bak \
  -e '/<smtp>/,/<\/smtp>/ s#<enable>false</enable>#<enable>true</enable>#' \
  -e '/<smtp>/,/<\/smtp>/ s#<host>[^<]*</host>#<host>mail</host>#' \
  -e '/<smtp>/,/<\/smtp>/ s#<port>[^<]*</port>#<port>3025</port>#' \
  -e '/<smtp>/,/<\/smtp>/ s#<from_mail_address>[^<]*</from_mail_address>#<from_mail_address>sender@localhost</from_mail_address>#' \
  -e "/<smtp>/,/<\\/smtp>/ s#<username>[^<]*</username>#<username>${mail_username}</username>#" \
  -e "/<smtp>/,/<\\/smtp>/ s#<password>[^<]*</password>#<password>${mail_password}</password>#" \
  "$temp_dir/ebms.properties.xml"
rm "$temp_dir/ebms.properties.xml.bak"
sed -i.bak \
  -e '/<pop>/,/<\/pop>/ s#<enable>false</enable>#<enable>true</enable>#' \
  -e '/<pop>/,/<\/pop>/ s#<host>[^<]*</host>#<host>mail</host>#' \
  -e '/<pop>/,/<\/pop>/ s#<port>[^<]*</port>#<port>3110</port>#' \
  -e "/<pop>/,/<\\/pop>/ s#<username>[^<]*</username>#<username>${mail_username}</username>#" \
  -e "/<pop>/,/<\\/pop>/ s#<password>[^<]*</password>#<password>${mail_password}</password>#" \
  "$temp_dir/ebms.properties.xml"
rm "$temp_dir/ebms.properties.xml.bak"
sed -e 's/execution-interval" value="300000"/execution-interval" value="1000"/' \
  -e '/group-execution/d' \
  corvus-ebms/src/main/spa/conf/hk/hku/cecid/ebms/spa/conf/mail-collector.module.xml \
  > "$temp_dir/mail-collector.module.xml"
docker network create "$network" >/dev/null
docker run -d --name "$database" --network "$network" --network-alias db \
  --tmpfs /var/lib/mysql:rw,size=512m \
  -e MYSQL_ROOT_PASSWORD=hermes-test-root ${database_image} >/dev/null
wait_for_database

if [ -n "${HERMES_E2E_DB_IMAGE:-}" ]; then
  docker exec "$database" mysql -uroot -phermes-test-root -e "CREATE DATABASE ebms; CREATE DATABASE as2; CREATE USER 'corvus'@'%' IDENTIFIED BY 'corvus'; GRANT ALL PRIVILEGES ON ebms.* TO 'corvus'@'%'; GRANT ALL PRIVILEGES ON as2.* TO 'corvus'@'%';"
fi
if [ "$use_legacy_dumps" = true ]; then
  docker exec "$database" mysql -uroot -phermes-test-root -e "DROP DATABASE ebms; DROP DATABASE as2; CREATE DATABASE ebms; CREATE DATABASE as2;"
  docker exec -i "$database" mysql -uroot -phermes-test-root ebms < "$ebms_dump"
  docker exec -i "$database" mysql -uroot -phermes-test-root as2 < "$as2_dump"
elif [ -n "${HERMES_E2E_DB_IMAGE:-}" ]; then
  docker exec -i "$database" mysql -uroot -phermes-test-root ebms < h2o-installer/sql/mysql_ebms.sql
  docker exec -i "$database" mysql -uroot -phermes-test-root as2 < h2o-installer/sql/mysql_as2.sql
fi

docker run -d --name "$mail_server" --network "$network" --network-alias mail -p "${mail_pop_port}:3110" \
  -e "GREENMAIL_OPTS=-Dgreenmail.setup.test.all -Dgreenmail.hostname=0.0.0.0 -Dgreenmail.users=${mail_username}:${mail_password}@localhost" \
  greenmail/standalone:2.1.13 >/dev/null
wait_for_mail_server

docker run -d --name "$application" --network "$network" -p "127.0.0.1:${port}:8080" \
  -e HERMES_WS_USERNAME=apiuser -e HERMES_WS_PASSWORD=corvus hermes-java27:local >/dev/null
wait_for_gateway
for protocol in ebms as2; do
  for service in sender receiver receiver_list msg_history permitdl config; do
    for suffix in '' '/'; do
      status=$(/usr/bin/curl --silent --show-error --max-time 5 -o /dev/null -w '%{http_code}' \
        "http://127.0.0.1:${port}/corvus/httpd/${protocol}/${service}${suffix}")
      [ "$status" = 401 ]
    done
  done
done
for plugin in corvus-as2 corvus-as2-admin; do
  docker exec "$application" test -f "/hermes_home/plugins/${plugin}/plugin.xml"
done
for plugin in corvus-as2plus corvus-as2plus-admin corvus-sfrm corvus-sfrm-admin; do
  ! docker exec "$application" test -e "/hermes_home/plugins/${plugin}"
done
docker cp "$temp_dir/ebms.properties.xml" "$application:/hermes_home/plugins/corvus-ebms/conf/hk/hku/cecid/ebms/spa/conf/ebms.properties.xml"
docker restart "$application" >/dev/null
wait_for_gateway

sed \
  -e "s#<id>as2-loopback</id>#<id>${as2_partnership_id}</id>#" \
  -e "s#as2loopback#${as2_identity}#g" \
  corvus-wsclient/src/main/config/as2-partnership.xml > "$temp_dir/as2-partnership.xml"
docker cp "$temp_dir/as2-partnership.xml" "$application:/tmp/as2-partnership.xml"
docker exec "$application" sh -c "cd /hermes_home/sample && mkdir -p logs && ./as2-partnership.sh /tmp/as2-partnership.xml ./config/as2-partnership/as2-request.xml /tmp/as2-partnership.log && ./as2-send.sh /tmp/as2-partnership.xml ./config/as2-send/as2-request.xml /tmp/as2-send.log ./config/as2-send/testpayload" > "$temp_dir/as2-send.out"
as2_message_id=$(sed -n 's/^New message id: //p' "$temp_dir/as2-send.out")
[ -n "$as2_message_id" ]

for _ in {1..30}; do
  as2_message_rows=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus as2 -e "SELECT COUNT(*) FROM message WHERE message_id = '${as2_message_id}'")
  [ "$as2_message_rows" = "2" ] && break
  sleep 1
done
[ "$as2_message_rows" = "2" ]

/usr/bin/curl --fail --silent --show-error --max-time 20 -u corvus:corvus \
  -F request_action=add \
  -F partnership_id="${prefix}-loopback" \
  -F cpa_id="$loopback_cpa_id" \
  -F service=http://localhost:8080/corvus/httpd/ebms/inbound \
  -F action_id="$loopback_action" \
  -F disabled=false \
  -F sync_reply_mode=none \
  -F transport_endpoint=http://localhost:8080/corvus/httpd/ebms/inbound \
  -F is_hostname_verified=false \
  -F ack_requested=never \
  -F ack_sign_requested=never \
  -F dup_elimination=always \
  -F message_order=NotGuaranteed \
  -F retries=1 \
  -F retry_interval=30000 \
  -F sign_requested=false \
  -F encrypt_requested=false \
  "http://127.0.0.1:${port}/corvus/admin/ebms/partnership" > "$temp_dir/partnership.html"
grep -q 'Partnership added successfully' "$temp_dir/partnership.html"

docker exec "$application" sh -c "sed -e 's#<cpaId>cpaid</cpaId>#<cpaId>${loopback_cpa_id}</cpaId>#' -e 's#<action>action</action>#<action>${loopback_action}</action>#' /hermes_home/sample/config/ebms-partnership.xml > /tmp/ebms-loopback-partnership.xml && java -cp '/hermes_home/sample/lib/*' hk.hku.cecid.corvus.ws.EBMSMessageSender /tmp/ebms-loopback-partnership.xml /hermes_home/sample/config/ebms-send/ebms-request.xml /tmp/ebms-loopback.log /hermes_home/sample/config/ebms-send/testpayload" > "$temp_dir/send.out"
message_id=$(sed -n 's/^New message id: //p' "$temp_dir/send.out")
[ -n "$message_id" ]
sleep 1

inbox_rows=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms -e "SELECT COUNT(*) FROM inbox WHERE message_id = '${message_id}'")
[ "$inbox_rows" = "1" ]

docker exec "$database" sh -c "rm -f /var/lib/mysql-files/loopback.bin && mysql -uroot -phermes-test-root ebms -e \"SELECT content INTO DUMPFILE '/var/lib/mysql-files/loopback.bin' FROM repository WHERE message_id = '${message_id}' AND message_box = 'outbox'\""
docker cp "$database":/var/lib/mysql-files/loopback.bin "$temp_dir/loopback.bin"
content_type=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms -e "SELECT content_type FROM repository WHERE message_id = '${message_id}' AND message_box = 'outbox'")
replay_status=$(/usr/bin/curl --silent --show-error --max-time 20 --output "$temp_dir/replay.out" --write-out '%{http_code}' -H "Content-Type: ${content_type}" -H 'SOAPAction: ""' --data-binary @"$temp_dir/loopback.bin" "http://127.0.0.1:${port}/corvus/httpd/ebms/inbound")
[ "$replay_status" = "204" ]

inbox_rows=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms -e "SELECT COUNT(*) FROM inbox WHERE message_id = '${message_id}'")
[ "$inbox_rows" = "1" ]
docker exec "$application" grep -q "Duplicate message received, and ignored: ${message_id}" /hermes_home/logs/ebms.log

signed_cpa_id="cpaid-signed-${prefix}"
signed_action="signed-action-${prefix}"
/usr/bin/curl --fail --silent --show-error --max-time 20 -u corvus:corvus \
  -F request_action=add \
  -F partnership_id="${prefix}-signed" \
  -F cpa_id="$signed_cpa_id" \
  -F service=http://localhost:8080/corvus/httpd/ebms/inbound \
  -F action_id="$signed_action" \
  -F disabled=false \
  -F sync_reply_mode=none \
  -F transport_endpoint=http://localhost:8080/corvus/httpd/ebms/inbound \
  -F is_hostname_verified=false \
  -F ack_requested=never \
  -F ack_sign_requested=never \
  -F dup_elimination=never \
  -F message_order=NotGuaranteed \
  -F retries=1 \
  -F retry_interval=30000 \
  -F sign_requested=true \
  -F encrypt_requested=false \
  -F verify_cert=@corvus-ebms/src/main/spa/security/corvus.cer \
  "http://127.0.0.1:${port}/corvus/admin/ebms/partnership" > "$temp_dir/signed-partnership.html"
grep -q 'Partnership added successfully' "$temp_dir/signed-partnership.html"

docker exec "$application" sh -c "sed -e 's#<cpaId>cpaid</cpaId>#<cpaId>${signed_cpa_id}</cpaId>#' -e 's#<action>action</action>#<action>${signed_action}</action>#' /hermes_home/sample/config/ebms-partnership.xml > /tmp/ebms-signed-partnership.xml && java -cp '/hermes_home/sample/lib/*' hk.hku.cecid.corvus.ws.EBMSMessageSender /tmp/ebms-signed-partnership.xml /hermes_home/sample/config/ebms-send/ebms-request.xml /tmp/ebms-signed.log /hermes_home/sample/config/ebms-send/testpayload" > "$temp_dir/signed-send.out"
signed_message_id=$(sed -n 's/^New message id: //p' "$temp_dir/signed-send.out")
[ -n "$signed_message_id" ]

for _ in {1..30}; do
  signed_inbox_rows=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms -e "SELECT COUNT(*) FROM inbox WHERE message_id = '${signed_message_id}'")
  [ "$signed_inbox_rows" = "1" ] && break
  sleep 1
done
[ "$signed_inbox_rows" = "1" ]
docker exec "$application" grep -q "Signature verification success: ${signed_message_id}" /hermes_home/logs/ebms.log

expired_message_id="expired-${message_id}"
cp "$temp_dir/loopback.bin" "$temp_dir/expired.bin"
EXPIRED_MESSAGE_ID="$expired_message_id" perl -0pi -e '
  s{<eb:MessageId>[^<]+</eb:MessageId>}{"<eb:MessageId>$ENV{EXPIRED_MESSAGE_ID}</eb:MessageId>"}e;
  s{</eb:Timestamp>}{</eb:Timestamp><eb:TimeToLive>2000-01-01T00:00:00Z</eb:TimeToLive>} or die "missing Timestamp";
' "$temp_dir/expired.bin"
grep -q "<eb:MessageId>${expired_message_id}</eb:MessageId>" "$temp_dir/expired.bin"

expiry_status=$(/usr/bin/curl --silent --show-error --max-time 20 --output "$temp_dir/expiry.out" --write-out '%{http_code}' -H "Content-Type: ${content_type}" -H 'SOAPAction: ""' --data-binary @"$temp_dir/expired.bin" "http://127.0.0.1:${port}/corvus/httpd/ebms/inbound")
[ "$expiry_status" = "204" ]

expiry_record=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms -e "SELECT CONCAT(message_type, ':', status) FROM message WHERE message_id = '${expired_message_id}' AND message_box = 'inbox'")
[ "$expiry_record" = "ProcessedError:PD" ]
expired_inbox_rows=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms -e "SELECT COUNT(*) FROM inbox WHERE message_id = '${expired_message_id}'")
[ "$expired_inbox_rows" = "0" ]

sync_cpa_id="cpaid-sync-${prefix}"
sync_action="sync-action-${prefix}"
/usr/bin/curl --fail --silent --show-error --max-time 20 -u corvus:corvus \
  -F request_action=add \
  -F partnership_id="${prefix}-sync" \
  -F cpa_id="$sync_cpa_id" \
  -F service=http://localhost:8080/corvus/httpd/ebms/inbound \
  -F action_id="$sync_action" \
  -F disabled=false \
  -F sync_reply_mode=mshSignalsOnly \
  -F transport_endpoint=http://localhost:8080/corvus/httpd/ebms/inbound \
  -F is_hostname_verified=false \
  -F ack_requested=always \
  -F ack_sign_requested=never \
  -F dup_elimination=never \
  -F message_order=NotGuaranteed \
  -F retries=1 \
  -F retry_interval=30000 \
  -F sign_requested=false \
  -F encrypt_requested=false \
  "http://127.0.0.1:${port}/corvus/admin/ebms/partnership" > "$temp_dir/sync-partnership.html"
grep -q 'Partnership added successfully' "$temp_dir/sync-partnership.html"

docker exec "$application" sh -c "sed -e 's#<cpaId>cpaid</cpaId>#<cpaId>${sync_cpa_id}</cpaId>#' -e 's#<action>action</action>#<action>${sync_action}</action>#' /hermes_home/sample/config/ebms-partnership.xml > /tmp/ebms-sync-partnership.xml && java -cp '/hermes_home/sample/lib/*' hk.hku.cecid.corvus.ws.EBMSMessageSender /tmp/ebms-sync-partnership.xml /hermes_home/sample/config/ebms-send/ebms-request.xml /tmp/ebms-sync.log /hermes_home/sample/config/ebms-send/testpayload" > "$temp_dir/sync-send.out"
sync_message_id=$(sed -n 's/^New message id: //p' "$temp_dir/sync-send.out")
[ -n "$sync_message_id" ]

for _ in {1..30}; do
  sync_status=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms -e "SELECT status FROM message WHERE message_id = '${sync_message_id}' AND message_box = 'outbox'")
  [ "$sync_status" = "PS" ] && break
  sleep 1
done
[ "$sync_status" = "PS" ]
sync_ack_rows=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms -e "SELECT COUNT(*) FROM message WHERE ref_to_message_id = '${sync_message_id}' AND message_box = 'inbox' AND message_type = 'Acknowledgement' AND status = 'PS'")
[ "$sync_ack_rows" = "1" ]

retry_cpa_id="cpaid-retry-${prefix}"
retry_action="retry-action-${prefix}"
/usr/bin/curl --fail --silent --show-error --max-time 20 -u corvus:corvus \
  -F request_action=add \
  -F partnership_id="${prefix}-retry" \
  -F cpa_id="$retry_cpa_id" \
  -F service=http://localhost:8080/corvus/httpd/ebms/inbound \
  -F action_id="$retry_action" \
  -F disabled=false \
  -F sync_reply_mode=none \
  -F transport_endpoint=http://127.0.0.1:9/corvus/httpd/ebms/inbound \
  -F is_hostname_verified=false \
  -F ack_requested=always \
  -F ack_sign_requested=never \
  -F dup_elimination=never \
  -F message_order=NotGuaranteed \
  -F retries=2 \
  -F retry_interval=100 \
  -F sign_requested=false \
  -F encrypt_requested=false \
  "http://127.0.0.1:${port}/corvus/admin/ebms/partnership" > "$temp_dir/retry-partnership.html"
grep -q 'Partnership added successfully' "$temp_dir/retry-partnership.html"

docker exec "$application" sh -c "sed -e 's#<cpaId>cpaid</cpaId>#<cpaId>${retry_cpa_id}</cpaId>#' -e 's#<action>action</action>#<action>${retry_action}</action>#' /hermes_home/sample/config/ebms-partnership.xml > /tmp/ebms-retry-partnership.xml && java -cp '/hermes_home/sample/lib/*' hk.hku.cecid.corvus.ws.EBMSMessageSender /tmp/ebms-retry-partnership.xml /hermes_home/sample/config/ebms-send/ebms-request.xml /tmp/ebms-retry.log /hermes_home/sample/config/ebms-send/testpayload" > "$temp_dir/retry-send.out"
retry_message_id=$(sed -n 's/^New message id: //p' "$temp_dir/retry-send.out")
[ -n "$retry_message_id" ]

for _ in {1..30}; do
  retry_status=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms -e "SELECT status FROM message WHERE message_id = '${retry_message_id}' AND message_box = 'outbox'")
  [ "$retry_status" = "DF" ] && break
  sleep 1
done
[ "$retry_status" = "DF" ]
retry_outbox_rows=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms -e "SELECT COUNT(*) FROM outbox WHERE message_id = '${retry_message_id}'")
[ "$retry_outbox_rows" = "0" ]
docker exec "$application" grep -q "Reliable message (${retry_message_id}) - no acknowledgement received until maximum retries" /hermes_home/logs/ebms.log

mail_cpa_id="cpaid-mail-encryption-${prefix}"
mail_action="mail-encryption-action-${prefix}"
/usr/bin/curl --fail --silent --show-error --max-time 20 -u corvus:corvus \
  -F request_action=add \
  -F partnership_id="${prefix}-mail-encryption" \
  -F cpa_id="$mail_cpa_id" \
  -F service=http://localhost:8080/corvus/httpd/ebms/inbound \
  -F action_id="$mail_action" \
  -F disabled=false \
  -F sync_reply_mode=none \
  -F transport_endpoint=mailto:recipient@localhost \
  -F is_hostname_verified=false \
  -F ack_requested=never \
  -F ack_sign_requested=never \
  -F dup_elimination=never \
  -F message_order=NotGuaranteed \
  -F retries=1 \
  -F retry_interval=100 \
  -F sign_requested=false \
  -F encrypt_requested=true \
  -F encrypt_cert=@corvus-ebms/src/main/spa/security/corvus.cer \
  "http://127.0.0.1:${port}/corvus/admin/ebms/partnership" > "$temp_dir/mail-partnership.html"
grep -q 'Partnership added successfully' "$temp_dir/mail-partnership.html"

docker exec "$application" sh -c "sed -e 's#<cpaId>cpaid</cpaId>#<cpaId>${mail_cpa_id}</cpaId>#' -e 's#<action>action</action>#<action>${mail_action}</action>#' /hermes_home/sample/config/ebms-partnership.xml > /tmp/ebms-mail-partnership.xml && java -cp '/hermes_home/sample/lib/*' hk.hku.cecid.corvus.ws.EBMSMessageSender /tmp/ebms-mail-partnership.xml /hermes_home/sample/config/ebms-send/ebms-request.xml /tmp/ebms-mail.log /hermes_home/sample/config/ebms-send/testpayload" > "$temp_dir/mail-send.out"
mail_message_id=$(sed -n 's/^New message id: //p' "$temp_dir/mail-send.out")
[ -n "$mail_message_id" ]

for _ in {1..30}; do
  mail_status=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms -e "SELECT status FROM message WHERE message_id = '${mail_message_id}' AND message_box = 'outbox'")
  [ "$mail_status" = "DL" ] && break
  sleep 1
done
[ "$mail_status" = "DL" ]

for _ in {1..30}; do
  { printf 'USER %s\r\nPASS %s\r\nRETR 1\r\nQUIT\r\n' "$mail_username" "$mail_password"; sleep 1; } | nc 127.0.0.1 "$mail_pop_port" > "$temp_dir/mail-pop.out"
  grep -qi 'application/pkcs7-mime;.*smime-type=enveloped-data' "$temp_dir/mail-pop.out" && break
  sleep 1
done
grep -qi 'application/pkcs7-mime;.*smime-type=enveloped-data' "$temp_dir/mail-pop.out"

docker cp "$temp_dir/mail-collector.module.xml" "$application:/hermes_home/plugins/corvus-ebms/conf/hk/hku/cecid/ebms/spa/conf/mail-collector.module.xml"
docker restart "$application" >/dev/null
wait_for_gateway

for _ in {1..30}; do
  mail_inbox_rows=$(docker exec "$database" mysql -N -B -ucorvus -pcorvus ebms -e "SELECT COUNT(*) FROM message WHERE message_id = '${mail_message_id}' AND message_box = 'inbox' AND status = 'PS'")
  [ "$mail_inbox_rows" = "1" ] && break
  sleep 1
done
[ "$mail_inbox_rows" = "1" ]
docker exec "$application" grep -q 'Decrypt the message' /hermes_home/logs/ebms.log
docker exec "$application" grep -q 'Received an ebxml message from mail box' /hermes_home/logs/ebms.log

printf 'Java 27 ebMS loopback passed: %s\n' "$message_id"
