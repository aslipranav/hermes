package hk.hku.cecid.piazza.commons.security;

import java.math.BigInteger;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.util.Date;
import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;
import org.junit.Assert;
import org.junit.Test;

public class KeyStoreTrustManagerTest {
    private X509Certificate selfSigned(String name, long notAfter) throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        KeyPair pair = generator.generateKeyPair();
        X500Name subject = new X500Name("CN=" + name);
        return new JcaX509CertificateConverter().getCertificate(
                new JcaX509v3CertificateBuilder(subject, BigInteger.ONE,
                        new Date(System.currentTimeMillis() - 120000), new Date(notAfter),
                        subject, pair.getPublic()).build(
                                new JcaContentSignerBuilder("SHA256withRSA").build(pair.getPrivate())));
    }

    @Test
    public void validatesChainsInsteadOfFindingAnyTrustedCertificate() throws Exception {
        X509Certificate trusted = selfSigned("trusted", System.currentTimeMillis() + 600000);
        X509Certificate attacker = selfSigned("attacker", System.currentTimeMillis() + 600000);
        KeyStore store = KeyStore.getInstance("PKCS12");
        store.load(null, null);
        store.setCertificateEntry("trusted", trusted);
        KeyStoreTrustManager manager = new KeyStoreTrustManager(store);
        manager.checkServerTrusted(new X509Certificate[] {trusted}, "RSA");
        manager.checkClientTrusted(new X509Certificate[] {trusted}, "RSA");
        for (boolean server : new boolean[] {true, false}) {
            try {
                X509Certificate[] forged = {attacker, trusted};
                if (server) manager.checkServerTrusted(forged, "RSA");
                else manager.checkClientTrusted(forged, "RSA");
                Assert.fail("Unrelated leaf must not inherit trust from an appended certificate");
            } catch (CertificateException expected) {
                // Expected: a matching anchor alone is not a valid certificate path.
            }
        }
        X509Certificate expired = selfSigned("expired", System.currentTimeMillis() - 60000);
        store.setCertificateEntry("expired", expired);
        try {
            manager.checkServerTrusted(new X509Certificate[] {expired}, "RSA");
            Assert.fail("Even a pinned leaf must be within its validity period");
        } catch (java.security.cert.CertificateExpiredException expected) {
            // Expected.
        }
    }
}
