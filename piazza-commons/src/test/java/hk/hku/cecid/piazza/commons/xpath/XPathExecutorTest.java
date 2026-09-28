package hk.hku.cecid.piazza.commons.xpath;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.Vector;

import javax.xml.parsers.DocumentBuilderFactory;

import org.junit.Assert;
import org.junit.Test;
import org.w3c.dom.Document;

public class XPathExecutorTest {

    @Test
    public void evaluatesNamespacedExpressionsAndCustomFunctions() throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        Document document = factory.newDocumentBuilder().parse(new ByteArrayInputStream(
                "<r:root xmlns:r=\"urn:root\" xmlns:ext=\"urn:extension\"><r:item>10</r:item></r:root>"
                        .getBytes(StandardCharsets.UTF_8)));
        XPathExecutor executor = new XPathExecutor(document);
        executor.registerFunction("urn:extension", "sum", new XPathFunction() {
            @Override
            public Object execute(Vector args) {
                return Double.valueOf(((Number) args.get(0)).doubleValue() + ((Number) args.get(1)).doubleValue());
            }
        });

        Assert.assertEquals(17.0d,
                ((Number) executor.eval("number(/r:root/r:item) + ext:sum(3, 4)")).doubleValue(), 0.0d);
        Assert.assertEquals(Boolean.TRUE, executor.eval("count(/r:root/r:item) = 1"));
    }
}
