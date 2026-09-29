package hk.hku.cecid.ebms.spa.handler;

import hk.hku.cecid.ebms.pkg.EbxmlMessage;
import hk.hku.cecid.ebms.spa.dao.MessageDataSourceDVO;
import org.junit.Assert;
import org.junit.Test;

public class AcknowledgementSecurityTest {
    @Test
    public void requiresRequestedSignaturesAndConsistentMessageReferences() throws Exception {
        EbxmlMessage outgoing = new EbxmlMessage();
        outgoing.addMessageHeader("A", "B", "cpa", "conversation", "service", "action",
                "outgoing-id", "2026-09-29T00:00:00Z");
        outgoing.addAckRequested(true);
        EbxmlMessage ack = new EbxmlMessage();
        ack.addMessageHeader("B", "A", "cpa", "conversation", "service", "Acknowledgment",
                "ack-id", "2026-09-29T00:00:01Z");
        ack.addAcknowledgment("2026-09-29T00:00:01Z", outgoing);
        MessageDataSourceDVO original = new MessageDataSourceDVO();
        original.setMessageId("outgoing-id");
        original.setCpaId("cpa");
        original.setAckSignRequested("true");
        assertRejected(ack, original, false);
        InboundMessageProcessor.validateAcknowledgement(ack, original, true);
        original.setAckSignRequested("false");
        InboundMessageProcessor.validateAcknowledgement(ack, original, false);
        original.setCpaId("another-partner");
        assertRejected(ack, original, true);
        original.setCpaId("cpa");
        ack.getMessageHeader().setRefToMessageId("different-id");
        assertRejected(ack, original, true);
    }

    private void assertRejected(EbxmlMessage ack, MessageDataSourceDVO original, boolean signed) throws Exception {
        try {
            InboundMessageProcessor.validateAcknowledgement(ack, original, signed);
            Assert.fail("Unsafe acknowledgement was accepted");
        } catch (MessageServiceHandlerException expected) {
            // Validation must happen before marking the original delivered or clearing its outbox.
        }
    }
}
