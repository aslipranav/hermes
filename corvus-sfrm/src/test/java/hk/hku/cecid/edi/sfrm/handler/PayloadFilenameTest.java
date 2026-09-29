package hk.hku.cecid.edi.sfrm.handler;

import java.io.File;
import java.io.IOException;
import org.junit.Assert;
import org.junit.Test;

public class PayloadFilenameTest {
    @Test
    public void confinesRemoteFilenamesToPayloadDirectory() throws Exception {
        File root = new File("target/payload-validation");
        Assert.assertEquals(new File(root, "invoice.xml").getCanonicalFile(),
                IncomingMessageHandler.resolvePayloadFile(root, "invoice.xml"));
        for (String filename : new String[] {null, "", ".", "..", "../outside.jsp", "/tmp/outside",
                "..\\outside.jsp", "C:outside.jsp", "folder/file.xml"}) {
            try {
                IncomingMessageHandler.resolvePayloadFile(root, filename);
                Assert.fail("Accepted unsafe filename: " + filename);
            } catch (IOException expected) {
                // Expected at the filesystem trust boundary.
            }
        }
    }
}
