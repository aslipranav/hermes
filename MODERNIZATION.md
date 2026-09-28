# Hermes Java 27 Rewrite

## Compatibility target

Hermes application code must run on Java 27 without JVM `--add-opens` or
`--add-exports` workarounds and preserve the existing external ebMS behavior.
Tomcat 9's own startup script currently adds its supported `--add-opens`
options; they are not Hermes application settings.

Java 27 is the latest feature release at this validation. Hermes builds with
Amazon Corretto 27 and runs it with Tomcat 9; this retains the required
`javax.servlet` boundary while avoiding an unsupported application runtime.

- SOAP 1.1 ebXML messages, including attachments, digital signatures,
  encryption, synchronous responses, and asynchronous empty-body responses.
- Inbound duplicate elimination, acknowledgements, time-to-live handling,
  status messages, partnership matching, retry behavior, and message history.
- HTTP paths below the existing `/corvus/httpd` mapping:
  `/ebms/inbound`, `/ebms/sender`, `/ebms/receiver_list`, `/ebms/receiver`,
  `/ebms/msg_history`, `/ebms/permitdl`, and `/ebms/status`.
- SOAP actions `ebmssend`, `ebmsreceivelist`, `Ebmsreceiverdownload`,
  `ebmsmsghistory`, `Ebmsresetrecv`, and `ebmsStatusQuery`.
- The existing `message`, `repository`, `outbox`, `inbox`, and `partnership`
  data model, including existing partner certificates and message records.

## Rewrite gates

1. Replace every JDK-internal API with supported Java or Jakarta APIs.
2. Keep the `javax.*` servlet compatibility boundary on Tomcat 9 while
   preserving the HTTP and WSDL contracts above; a Jakarta migration requires
   a separately verified cutover to Tomcat 10 or newer.
3. Replace obsolete SOAP, XML-security, logging, mail, pooling, JDBC, and
   cryptography dependencies where Java 27 requires it; no JDK-internal
   runtime is carried forward merely to make Java 27 start.
4. Prove compatibility with golden inbound/outbound ebMS exchanges, signed and
   encrypted message fixtures, duplicate and retry scenarios, and a database
   migration from the current schema.
5. Build, test, and run the complete gateway on Java 27 in a supported
   container before cutover.

## Current evidence

- The unmodified upstream baseline at `be1870e76e21fb1abca50f19964d1c20626c54d8`
  passes `mvn clean test` under Corretto 8, and the modernized working tree
  passes the same full 19-module command under Corretto 27. This establishes
  regression-suite parity across the runtime upgrade; it is not a substitute
  for the partner exchange gates below.
- A public/protected API comparison of the 20 modernized production classes
  preserves their supported entry points, including protected finalizer hooks
  for binary-compatible subclasses. Two legacy implementation-only contracts
  remain exceptions: `XPathExecutor.visit` was typed to a non-exported
  `com.sun.*` JDK class, and `SFRMTarUtils` extended an Ant `TarUtils` whose
  incompatible static return signature changed in supported Ant. Neither can
  run on Java 27 without retaining unsupported internals; migrate any such
  consumer before cutover.
- The Maven compiler target is Java 27. The shared XPath implementation no
  longer accesses `com.sun.*`, and its Java 27 regression test passes.
- SAAJ 1.3.25 was replaced with the Java 27-compatible `javax.xml.soap` API
  and SAAJ 1.5.3 implementation. SOAP adapter and client regression tests pass.
- The S/MIME provider is Bouncy Castle 1.86. Java 27 AS2 and SFRM encryption
  and decryption suites pass against it; ebMS uses the same provider for its
  mail-transport encryption path.
- `scripts/verify-java27-loopback.sh` builds the Java 27 image, initializes
  the existing schemas on MySQL 8.4 with Connector/J 26.7, sends standard AS2
  and SOAP 1.1 ebMS payloads through the deployed gateway, and proves duplicate
  rejection, expired-message rejection, and a
  `mshSignalsOnly` synchronous acknowledgement. It also proves a reliable
  delivery retries to its configured maximum before failing cleanly, then
  sends an encrypted eBMS message over SMTP and verifies its S/MIME enveloped
  payload in a disposable POP mailbox. The same runtime then collects,
  decrypts, and persists that eBMS message from POP.
- A native two-gateway run on Corretto 27, Tomcat 9.0.122, and MySQL 8.4.11
  generated distinct cross-trusted Partner C/D identities, rejected a TLS
  client without a certificate, and delivered signed ebMS messages in both
  directions. Both originating outboxes reached `PS`, both receiving inboxes
  contained one message, and both receiver logs recorded signature verification
  success. Each signed acknowledgement was also persisted, verified, and linked
  to its originating reliable message.
- `scripts/verify-java27-mtls-loopback.sh` now checks that both reciprocal
  acknowledgements are persisted as processed messages linked to their source
  message, in addition to delivery, `PS` status, and receiver signature logs.
- The same verifier accepts schema-scoped `HERMES_EBMS_DUMP` and
  `HERMES_AS2_DUMP` inputs, restores them only into its disposable MySQL 8.4
  instance, and runs the compatibility checks with isolated partnership IDs.
- Existing ebMS examples are in `loopback/src/main/data/ebms.xml` and the
  `corvus-ebms` test resources. They are the starting point for golden
  compatibility tests; partner-provided production exchanges are still needed
  before declaring the replacement fully compatible.
- The Docker image, compose database image, and interactive installer use
  MySQL Connector/J 26.7 and `com.mysql.cj.jdbc.Driver`; the deployed runtime
  check passes against MySQL 8.4.
- The JDK 27 runtime image preserves the legacy Docker deployment footprint:
  standard AS2 and AS2 Admin are installed, while AS2Plus and SFRM are not.
  AS2 and AS2Plus are mutually exclusive in the original installer because
  both register the same HTTP endpoints; their source and interactive
  installer options remain available for installations that selected them.
- The deployed image uses Reload4j 1.2.26 and the compatible SLF4J 1.7.36
  binding in place of end-of-life Log4j 1.2.17; the Java 27 test reactor and
  deployed loopback check both pass with the replacement.
- Commons FileUpload 1.6.0 and Commons IO 2.14.0 replace every deployed
  vulnerable FileUpload copy. The admin-partnership multipart upload path is
  exercised by the deployed verifier.
- Apache XML Security 2.2.6, Xalan 2.7.3 with its matching serializer, and
  Ant 1.10.11 replace the remaining high-severity runtime findings. The
  verifier now includes a signed ebMS delivery and asserts receiver-side
  signature verification succeeds.
- Dom4j 2.2.0 replaces Dom4j 1.6.1, removing the previously reported
  critical and high-severity XML parsing findings; the complete Java 27 test
  reactor and deployed loopback check pass with the upgrade.
- SFRM now uses Ant 1.10.11. Its TAR support uses Ant's supported UTF-8 stream
  APIs; the focused 93-test SFRM suite covers archive extraction, long names,
  Unicode filenames, and rejection of path-traversal archive entries.
- The web-service client uses WSO2's source-compatible patched Commons
  HttpClient 3.1 fork. It preserves the legacy client package/API and adds
  default HTTPS certificate hostname verification for `CVE-2012-5783`; HTTP
  client unit tests continue to cover request, multipart, and Basic-auth flows.
- Hermes no longer relies on finalization or `sun.net.client` timeout
  properties. Compatibility-only protected finalizer hooks remain for legacy
  subclasses, while SFRM applies its existing 60-second timeout directly to
  its outbound HTTP connection and the file logger supports deterministic
  `close()` with a Java `Cleaner` fallback.
- A Java 27 `jdeps --jdk-internals` scan of all 19 Hermes module JARs has no
  JDK-internal dependency. `jdeprscan --for-removal` reports only those known
  protected finalizer hooks; Tomcat and EJB APIs are supplied by the target
  runtime and are outside the packaged application classpath used by the scan.
- A fresh 95-component runtime SBOM generated from the Maven reactor reports
  zero vulnerabilities when scanned by Trivy 0.74.0 with its vulnerability and
  Java databases updated on 2026-09-28. Trivy warns that third-party SBOM input
  can under-detect dependencies, so this supplements rather than replaces the
  deployed-image scan below.
- Fresh source dependency and Java 27 image scans report no vulnerabilities
  with an available fixed version. The remaining Ubuntu 24.04 base-image
  findings are unpatched upstream CVEs; rebuild when the upstream base supplies
  fixes.

## Remaining cutover evidence

- Run encrypted ebMS mail scenarios against preserved partner golden exchanges.
- Exercise an upgrade and rollback using a copy of an existing Hermes database
  on the target MySQL 8.4 production topology.
- Compare partner-provided production exchanges and operational workflows
  before declaring one-hundred-percent compatibility.
