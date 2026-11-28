package cl.brarriodigital.lambda;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.time.Duration;
import java.util.List;

import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class RequestEventHandlerTest {

    private HttpServer server;
    private RequestEventHandler handler;

    @BeforeEach
    void startServer() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/api/v1/internal/request-events", exchange -> {
            String body = new String(exchange.getRequestBody().readAllBytes());
            int status = body.contains("ADMITIDO") ? 503 : 204;
            exchange.sendResponseHeaders(status, -1);
            exchange.close();
        });
        server.start();
        String reportUrl = "http://127.0.0.1:" + server.getAddress().getPort();
        handler = new RequestEventHandler(reportUrl, java.net.http.HttpClient.newHttpClient(), Duration.ofSeconds(2));
    }

    @AfterEach
    void stopServer() {
        server.stop(0);
    }

    @Test
    void returnsOnlyFailedMessagesForRetry() {
        SQSEvent event = new SQSEvent();
        SQSEvent.SQSMessage accepted = message("accepted", "{\"status\":\"INGRESADO\"}");
        SQSEvent.SQSMessage failed = message("failed", "{\"status\":\"ADMITIDO\"}");
        event.setRecords(List.of(accepted, failed));

        var response = handler.handleRequest(event, null);

        assertEquals(1, response.getBatchItemFailures().size());
        assertEquals("failed", response.getBatchItemFailures().getFirst().getItemIdentifier());
    }

    private SQSEvent.SQSMessage message(String id, String body) {
        SQSEvent.SQSMessage message = new SQSEvent.SQSMessage();
        message.setMessageId(id);
        message.setBody(body);
        return message;
    }
}
