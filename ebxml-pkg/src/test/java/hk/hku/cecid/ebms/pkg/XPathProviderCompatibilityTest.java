package hk.hku.cecid.ebms.pkg;

import hk.hku.cecid.piazza.commons.xpath.XPathExecutor;
import javax.xml.xpath.XPathFactory;
import org.junit.Assert;
import org.junit.Test;

public class XPathProviderCompatibilityTest {
    @Test
    public void evaluatesWithTheBundledLegacyProviderOnTheClasspath() throws Exception {
        String property = "javax.xml.xpath.XPathFactory:" + XPathFactory.DEFAULT_OBJECT_MODEL_URI;
        String original = System.getProperty(property);
        try {
            System.setProperty(property, "org.apache.xpath.jaxp.XPathFactoryImpl");
            Assert.assertEquals("org.apache.xpath.jaxp.XPathFactoryImpl",
                    XPathFactory.newInstance().getClass().getName());
            Assert.assertEquals(2.0d, ((Number) new XPathExecutor().eval("1+1")).doubleValue(), 0.0d);
        } finally {
            if (original == null) System.clearProperty(property);
            else System.setProperty(property, original);
        }
    }
}
