# ![Hermes 2+](http://hermes.cecid.org/en/latest/_static/hermes-2-plus-logo.png)

Hermes Business Messaging Gateway is a proven open-source solution for
enterprises to automate business transactions with business partners through
secure and reliable exchange of electronic documents (e.g., purchase
orders). Hermes is secure; it allows you to encrypt and digitally sign the
documents for transmission. Hermes is reliable; the sender can automatically
retransmit a message when it is dropped in the network while the receiver can
guarantee every message is delivered once and only once, and in the right order.

## Java 27 Rebuild
This repository is the Hermes project rebuilt to compile and run on Java 27
while preserving the existing Hermes AS2, ebMS, SFRM, installer, and database
compatibility contracts. See [MODERNIZATION.md](MODERNIZATION.md) for the
verified upgrade scope, compatibility checks, and remaining external
acceptance evidence.
The [Java 27 review and fix report](JAVA27-REVIEW.md) records security and
compatibility findings, their fixes, and regression coverage.

## Table of Contents
**[Documentations](#documentations)**<br/>
**[Quick Start](#quick-start)**<br/>
**[Development](#development)**

## Documentation
Full documentation is available at [hermes.cecid.org](http://hermes.cecid.org/).

## Quick Start
### Install Hermes with Docker
1. Install Docker with the Compose plugin.
2. From this checkout, build and start the Java 27 application and MySQL 8.4 database:<br/>
`docker compose -f deploy/docker-compose.yml up --build -d`
3. Log in to the Hermes administration console at
`http://localhost:18080/corvus/admin/home` (username:`corvus`, password:`corvus`)
to check if Hermes is up and running.

This is a local development setup, bound to loopback only. The historical
`cecid/hermes_app:2.2` image does **not** contain this Java 27 rebuild.
Before exposing a deployment, replace the sample account passwords and signing
keys, configure database secrets, and terminate HTTPS. Do not expose the sample
credentials over plain HTTP.

Business SOAP services (sender, receiver, receiver list, history, configuration,
and redownload) require Basic authentication with a `user`, `api`, `admin`, or
`corvus` role. Partner inbound/MDN routes retain their protocol authentication.
For bundled command-line SOAP clients, set `HERMES_WS_USERNAME` and
`HERMES_WS_PASSWORD`; Java callers can use `setBasicAuthentication` on each client.
Credentials are scoped to that client, not a JVM-wide authenticator.

## Development
### Compile
1. Install Java 27 and [Apache Maven](http://maven.apache.org/install.html).
   Hermes is compiled with `--release 27`; Java 25 or older is not supported.
2. Run the full regression suite.<br/>
`mvn clean test`
3. Build the distributable installer and ZIP packages.<br/>
`mvn package -Dmaven.test.skip=true`
4. Locate `hermes2_installer.jar` under the `target/` directory. Install Hermes 
following the [installation guide](http://hermes.cecid.org/en/latest/installation.html).

### Java 27 Loopback Check
Run `scripts/verify-java27-loopback.sh` to build the Java 27 image against
MySQL 8.4 and verify standard AS2 and ebMS payload loopbacks, duplicate and
expired-message rejection, and a
synchronous acknowledgement, retry exhaustion, and encrypted eBMS SMTP
delivery plus POP collection and decryption in disposable containers.

Run `scripts/verify-java27-mtls-loopback.sh` for the separate two-partner
certificate-required TLS and signed-ebMS check.

To validate a production database copy, pass schema-scoped MySQL dumps (made
without `--databases`) as `HERMES_EBMS_DUMP=/path/ebms.sql` and
`HERMES_AS2_DUMP=/path/as2.sql`. The script restores them only into a
disposable MySQL 8.4 container before running the same gateway checks.

### Java API Documentations
The Java API Documentations are available at
[javadocs.hermes.cecid.org](http://javadoc.hermes.cecid.org/)

## Digital Signature Setup
Please refer to [How to send messages using Self Signed Certificate](http://hermes.cecid.org/en/latest/message_signing.html#how-to-send-messages-using-self-signed-certificate).
