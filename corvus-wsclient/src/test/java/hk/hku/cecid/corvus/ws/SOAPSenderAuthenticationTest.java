package hk.hku.cecid.corvus.ws;

import java.net.Authenticator;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import com.sun.net.httpserver.HttpServer;
import org.junit.Assert;
import org.junit.Test;

public class SOAPSenderAuthenticationTest {
    @Test
    public void credentialsAreSentPerClientWithoutChangingGlobalAuthenticator() throws Exception {
        List<String> headers = new ArrayList<String>();
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/soap", exchange -> {
            headers.add(exchange.getRequestHeaders().getFirst("Authorization"));
            exchange.getRequestBody().readAllBytes();
            byte[] body = ("<s:Envelope xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'>"
                    + "<s:Body/></s:Envelope>").getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "text/xml");
            exchange.sendResponseHeaders(200, body.length);
            exchange.getResponseBody().write(body);
            exchange.close();
        });
        server.start();
        Authenticator original = Authenticator.getDefault();
        try {
            SOAPSender first = client(server);
            SOAPSender second = client(server);
            first.setBasicAuthentication("first", "password");
            second.setBasicAuthentication("second", "password");
            first.run();
            second.run();
            Assert.assertSame(original, Authenticator.getDefault());
            Assert.assertEquals(java.util.Arrays.asList("Basic Zmlyc3Q6cGFzc3dvcmQ=",
                    "Basic c2Vjb25kOnBhc3N3b3Jk"), headers);
        } finally {
            server.stop(0);
        }
    }

    private SOAPSender client(HttpServer server) {
        SOAPSender sender = new SOAPSender(null, null,
                "http://127.0.0.1:" + server.getAddress().getPort() + "/soap") {
            @Override public void onError(Throwable error) {
                throw new AssertionError(error);
            }
        };
        sender.setLoopTimes(1);
        return sender;
    }
}
