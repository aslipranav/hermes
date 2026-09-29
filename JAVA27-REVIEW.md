# Java 27 code review and fixes

Reviewed baseline: `346290999309d7f1fbdc33229a23b4b58d2cd22e`.
Review and remediation date: 2026-09-29.

This review covers the modernization diff and security/compatibility-sensitive
paths across the gateway, protocol modules, shared libraries, clients, installer,
and deployment configuration. Findings include inherited defects as well as
migration regressions. This is not a claim that every possible defect has been
eliminated or that production compatibility is certified.

Priorities: P1 = urgent release blocker; P2 = significant defect; P3 = lifecycle
or maintenance defect; P4 = minor correctness/documentation defect.

## Findings and remediation

### P1-1: Anonymous access to business-message services

**Inherited.** `web.xml` protected `/httpd/auth/*`, but the AS2 and ebMS sender,
receiver, receiver-list, history, and redownload services were registered outside
that namespace. An HTTP caller could submit messages or retrieve payloads without
logging in; receiver operations also consume messages from the inbox.

**Fixed:** container-managed authentication covers the business-service paths,
including trailing slashes. Protocol ingress/MDN routes remain separate. Bundled
SOAP clients support per-client credentials without installing a JVM-wide
authenticator. The runtime check asserts HTTP 401 for anonymous business-service
requests and verifies successful authenticated message submission.

Locations: `corvus-webapp/src/main/webapp/WEB-INF/web.xml`,
`corvus-wsclient/src/main/java/hk/hku/cecid/corvus/ws/SOAPSender.java`.

### P1-2: Signed acknowledgements could be downgraded to unsigned receipts

**Inherited.** An absent signature passed `checkSignature`; acknowledgement
processing then marked the referenced outbox message processed and cleared its
delivery state, even when the original message requested a signed receipt.
Header and acknowledgement references were not required to identify the same
message.

**Fixed:** validate the original outbox record, CPA, and reference consistency,
and require a signature when that original message requested one. Cryptographic
verification still follows for signed receipts. Tests cover optional unsigned
receipts, required signatures, mismatched references/CPA, and a deployed signed
receipt replay with its signature removed, which must become `ProcessedError`.

Location: `corvus-ebms/src/main/java/hk/hku/cecid/ebms/spa/handler/InboundMessageProcessor.java`.

### P1-3: Custom TLS trust manager did not validate certificate chains

**Inherited; applies when this optional trust manager is configured.** A chain
was accepted if any certificate appeared in the trust store. A Java 27 reproducer
accepted an unrelated self-signed leaf followed by a copied trusted certificate;
the standard PKIX manager rejected the same chain.

**Fixed:** delegate client/server chain verification to PKIX and check certificate
validity dates, including pinned leaves. Regression tests reject forged chains
and expired certificates while accepting trusted peers. The two-gateway mTLS test
exercises the configured custom manager with valid reciprocal identities.

Location: `piazza-commons/src/main/java/hk/hku/cecid/piazza/commons/security/KeyStoreTrustManager.java`.

### P1-4: The shipped MySQL 8.4 image failed on first startup

**Migration regression.** The upgraded database image still used
`GRANT ... IDENTIFIED BY`. A clean initialization exited with MySQL error 1064 at
line 2 before creating the application schemas. The old loopback verifier bypassed
this script by creating its own users and databases.

**Fixed:** create the account separately from its grants. The default runtime
verifier now builds and uses the shipped database image, including its actual
initialization script. Readiness uses TCP so the temporary initialization server
cannot produce a false ready signal.

Locations: `deploy/db/load.sql`, `scripts/verify-java27-loopback.sh`.

### P2-1: XML external entities were enabled

**Inherited.** The SFRM acknowledgement parser and shared property-tree readers
used unrestricted SAX readers. A Java 27 reproducer expanded a local sentinel
file into an acknowledgement document. These readers also serve uploaded CPA
and configuration inputs.

**Fixed:** use dom4j's hardened reader defaults in the shared property reader;
SFRM acknowledgements additionally reject DTDs. Regression tests reject an SFRM
external-entity document and verify that property trees cannot import a local
file's content. Existing normal configuration and acknowledgement tests remain.

Locations: `corvus-sfrm/src/main/java/hk/hku/cecid/edi/sfrm/pkg/SFRMAcknowledgementParser.java`,
`piazza-commons/src/main/java/hk/hku/cecid/piazza/commons/util/PropertyTree.java`.

### P2-2: SFRM payload filenames could escape their delivery directory

**Inherited; SFRM installations.** A peer-provided filename was persisted and then
passed directly to `new File(directory, filename)` during payload completion.
Traversal names could place a received file outside the intended directory,
subject to filesystem permissions and the move operation's no-overwrite rule.

**Fixed:** require a single filename and verify the canonical destination's
parent before moving. Tests cover ordinary names, traversal, absolute paths,
Windows-style paths, and empty names.

Location: `corvus-sfrm/src/main/java/hk/hku/cecid/edi/sfrm/handler/IncomingMessageHandler.java`.

### P2-3: Modern XPath evaluation failed with bundled Xalan

**Migration regression.** `XPathFactory.newInstance()` can select the bundled
Xalan provider, which rejects the newer untyped `evaluateExpression` operation.
The Java 27 reproducer failed even for `1+1` with `UnSupported Return Type ... any`.
The original commons-only test classpath did not expose this conflict.

**Fixed:** select the JDK's standard XPath implementation explicitly. A regression
test in `ebxml-pkg` asserts that the actual Xalan provider is present and selected
by normal discovery, then verifies that the Hermes evaluator still works.

Location: `piazza-commons/src/main/java/hk/hku/cecid/piazza/commons/xpath/XPathExecutor.java`.

### P2-4: README quick start deployed the historical image

**Stale deployment instructions.** The Java 27 README still directed users to
`cecid/hermes_app:2.2`, which does not contain this rebuild.

**Fixed:** build from this checkout with Compose. The development port is bound
to loopback and the unnecessary privileged-container flag is removed. The README
explicitly describes authentication changes and the need to replace sample
credentials/keys and configure HTTPS before exposing a deployment.

Locations: `README.md`, `deploy/docker-compose.yml`.

### P3-1: JDBC cleanup called a method absent from Connector/J 26.7

**Migration regression.** The class name was modernized, but reflection still
looked for `shutdown()`. The shipped driver has `checkedShutdown()` instead.
The resulting exception was silently discarded, skipping explicit cleanup.

**Fixed:** invoke `checkedShutdown()` and report reflective failures. Absence of
the optional MySQL driver remains supported for other database installations.
The application is restarted during deployed regression checks.

Location: `piazza-commons/src/main/java/hk/hku/cecid/piazza/commons/servlet/http/HttpDispatcher.java`.

### P4-1: Administration message still referred to Java 25

**Migration documentation defect.** The finalization action described the wrong
Java version.

**Fixed:** use runtime-neutral wording for the unsupported explicit finalization
operation.

Location: `corvus-admin/src/main/java/hk/hku/cecid/piazza/corvus/admin/listener/AdminPageletAdaptor.java`.

## Verification

- Amazon Corretto 27: full 19-module `mvn clean test` reactor passed; 56 suites,
  263 tests reported, 257 passed, zero failures/errors, six pre-existing skips.
  The skipped cases are shutdown-email subject/body/stop tests, each parameterized
  twice; they were not changed or counted as passes.
- Rebuilt the application image from source; build context excludes old targets.
- `mvn package -Dmaven.test.skip=true` passed after the full test run, producing
  the refreshed installer, binary ZIP, and source ZIP.
- `scripts/verify-java27-loopback.sh`: shipped MySQL initialization, anonymous
  access rejection, authenticated AS2/ebMS delivery, signed ebMS, duplicate and
  expired-message handling, synchronous acknowledgements, retry exhaustion, and
  encrypted SMTP delivery followed by POP collection/decryption.
- `scripts/verify-java27-mtls-loopback.sh`: two independent identities, required
  client certificates, signed messages and acknowledgements in both directions,
  and rejection of a receipt with its required signature removed.
- Shell syntax and Git whitespace checks.

## Compatibility and remaining acceptance work

Business SOAP clients must now authenticate. DTD-bearing acknowledgements,
external XML entities, invalid/expired TLS certificate chains, unsafe payload
filenames, and unsigned receipts where signatures were requested are intentionally
rejected. Preserving those unsafe behaviors is not a compatibility objective.

Production partner golden exchanges and a real production database-copy upgrade
remain external acceptance requirements. SFRM and AS2Plus receive source/unit-test
coverage here, not a new deployed end-to-end certification; the standard Docker
image still intentionally excludes those optional modules. Sample deployment
credentials and signing keys remain development-only and must be replaced before
production exposure. This work does not claim a comprehensive penetration test
or that every dependency is vulnerability-free.
