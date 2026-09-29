package hk.hku.cecid.piazza.commons.util;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.Assert;
import org.junit.Test;

public class PropertyTreeSecurityTest {
    @Test
    public void doesNotExpandExternalEntities() throws Exception {
        Path sentinel = Files.createTempFile("hermes-xxe-test", ".txt");
        try {
            Files.writeString(sentinel, "external-secret");
            String xml = "<!DOCTYPE root [<!ENTITY x SYSTEM '" + sentinel.toUri()
                    + "'>]><root>&x;</root>";
            PropertyTree tree = new PropertyTree(new ByteArrayInputStream(xml.getBytes(StandardCharsets.UTF_8)));
            Assert.assertFalse(tree.getProperty("/root").contains("external-secret"));
        } finally {
            Files.delete(sentinel);
        }
    }
}
