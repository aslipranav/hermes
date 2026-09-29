package hk.hku.cecid.piazza.commons.security;

import java.security.KeyStore;
import java.security.KeyStoreException;
import java.security.GeneralSecurityException;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.util.Enumeration;

import javax.net.ssl.X509TrustManager;
import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;

/**
 * This class implements the javax.net.ssl.X509TrustManager, which trusts a
 * certificate chain only after PKIX validation against the stored trust anchors.
 *
 * @author Bob P. Y. Koon
 */
public class KeyStoreTrustManager extends KeyStoreComponent implements X509TrustManager {

    /**
     * Creates a new instance of KeyStoreTrustManger.
     */
    public KeyStoreTrustManager() {
    }

    /**
     * Creates a new instance of KeyStoreTrustManger.
     * 
     * @param keyman the trusted key store manager.
     * @throws KeyStoreManagementException if the specified key store manager is null.
     */
    public KeyStoreTrustManager(KeyStoreManager keyman) throws KeyStoreManagementException {
        if (keyman==null) {
            throw new KeyStoreManagementException("KeyStoreManager is null");
        }
        super.init(keyman.keyStore, null, null);
    }

    /**
     * Creates a new instance of KeyStoreTrustManger.
     * 
     * @param keyStore the initialized trusted key store.
     * @throws KeyStoreManagementException if the specified key store is null.
     */
    public KeyStoreTrustManager(KeyStore keyStore) throws KeyStoreManagementException {
        if (keyStore==null) {
            throw new KeyStoreManagementException("KeyStore is null");
        }
        super.init(keyStore, null, null);
    }
    
    /**
     * Creates a PKIX validator using the currently configured trust store.
     */
    private X509TrustManager getTrustManager() throws CertificateException {
        try {
            TrustManagerFactory factory = TrustManagerFactory.getInstance("PKIX");
            factory.init(keyStore);
            for (TrustManager manager : factory.getTrustManagers()) {
                if (manager instanceof X509TrustManager) {
                    return (X509TrustManager) manager;
                }
            }
        } catch (GeneralSecurityException e) {
            throw new CertificateException("Cannot initialize PKIX trust manager", e);
        }
        throw new CertificateException("No X509 trust manager is available");
    }

    /**
     * Checks the supplied chain and validity periods before PKIX validation.
     * 
     * @param chain the certificate chain.
     * @throws IllegalArgumentException if null or zero-length chain is passed in 
     *          for the chain parameter or if null or zero-length string is passed in 
     *          for the authType parameter. 
     * @throws CertificateException if the certificate chain is not trusted by this TrustManager.
     */
    private void checkTrusted(X509Certificate[] chain)
            throws CertificateException {
        if (chain == null || chain.length == 0) {
            throw new IllegalArgumentException("Null or zero length chain");
        }
        for (X509Certificate certificate : chain) {
            if (certificate == null) {
                throw new CertificateException("Null certificate in chain");
            }
            certificate.checkValidity();
        }
    }

    /**
     * Validates a client's certificate chain against the configured trust anchors.
     * 
     * @param chain the peer certificate chain.
     * @param authType the key exchange algorithm used.
     * @throws IllegalArgumentException if null or zero-length chain is passed in 
     *          for the chain parameter or if null or zero-length string is passed in 
     *          for the authType parameter. 
     * @throws CertificateException if the certificate chain is not trusted by this TrustManager.
     * @see javax.net.ssl.X509TrustManager#checkClientTrusted(java.security.cert.X509Certificate[], java.lang.String)
     */
    public void checkClientTrusted(X509Certificate[] chain, String authType)
            throws CertificateException {
        checkTrusted(chain);
        getTrustManager().checkClientTrusted(chain, authType);
    }
    
    /**
     * Validates a server's certificate chain against the configured trust anchors.
     * 
     * @param chain the peer certificate chain.
     * @param authType the key exchange algorithm used.
     * @throws IllegalArgumentException if null or zero-length chain is passed in 
     *          for the chain parameter or if null or zero-length string is passed in 
     *          for the authType parameter. 
     * @throws CertificateException if the certificate chain is not trusted by this TrustManager.
     * @see javax.net.ssl.X509TrustManager#checkServerTrusted(java.security.cert.X509Certificate[], java.lang.String)
     */
    public void checkServerTrusted(X509Certificate[] chain, String authType)
            throws CertificateException {
        checkTrusted(chain);
        getTrustManager().checkServerTrusted(chain, authType);
    }

    /**
     * Returns an array of certificate authority certificates 
     * which are stored in the embeded key store.
     * 
     * @return a non-null (possibly empty) array of acceptable CA issuer certificates.
     */
    public X509Certificate[] getAcceptedIssuers() {
        X509Certificate[] certs = new X509Certificate[0];
        try {
            // See how many certificates are in the keystore.
            int numberOfEntry = keyStore.size();
            // If there are any certificates in the keystore.
            if(numberOfEntry > 0) {
                // Create an array of X509Certificates
                certs = new X509Certificate[numberOfEntry];

                // Get all of the certificate alias out of the keystore.
                Enumeration aliases = keyStore.aliases();

                // Retrieve all of the certificates out of the keystore
                // via the alias name.
                int i = 0;
                while (aliases.hasMoreElements()) {
                    certs[i] = (X509Certificate) keyStore.getCertificate(
                            (String) aliases.nextElement());
                    i++;
                }
            }
        } catch(KeyStoreException e) {
            certs = new X509Certificate[0];
        }
        return certs;
    }
}
