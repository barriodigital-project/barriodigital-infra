package cl.brarriodigital.lambda;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.logging.Logger;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;

public class RequestEventHandler implements RequestHandler<SQSEvent, SQSBatchResponse> {

    private static final Logger LOGGER = Logger.getLogger(RequestEventHandler.class.getName());
    private static final String REPORT_PATH = "/api/v1/internal/request-events";

    private final String reportUrl;
    private final HttpClient httpClient;
    private final Duration requestTimeout;

    public RequestEventHandler() {
        this(
            requiredEnvironment("REPORT_API_URL"),
            newHttpClient(),
            Duration.ofSeconds(environmentSeconds("REPORT_API_TIMEOUT_SECONDS", 10))
        );
    }

    RequestEventHandler(String reportApiUrl, HttpClient httpClient, Duration requestTimeout) {
        this.reportUrl = normalizeBaseUrl(reportApiUrl) + REPORT_PATH;
        this.httpClient = httpClient;
        this.requestTimeout = requestTimeout;
    }

    @Override
    public SQSBatchResponse handleRequest(SQSEvent event, Context context) {
        if (event == null || event.getRecords() == null) {
            throw new IllegalArgumentException("SQS event must contain records");
        }

        List<SQSBatchResponse.BatchItemFailure> failures = new ArrayList<>();
        for (int index = 0; index < event.getRecords().size(); index++) {
            SQSEvent.SQSMessage message = event.getRecords().get(index);
            if (message.getMessageId() == null || message.getBody() == null) {
                throw new IllegalArgumentException("SQS records require message IDs and bodies");
            }

            try {
                HttpRequest request = HttpRequest.newBuilder(URI.create(reportUrl))
                    .timeout(requestTimeout)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(message.getBody()))
                    .build();
                HttpResponse<Void> response = httpClient.send(request, HttpResponse.BodyHandlers.discarding());
                if (response.statusCode() < 200 || response.statusCode() >= 300) {
                    LOGGER.warning("Report returned HTTP " + response.statusCode()
                        + " for SQS message " + message.getMessageId());
                    failures.add(new SQSBatchResponse.BatchItemFailure(message.getMessageId()));
                }
            } catch (IOException exception) {
                LOGGER.warning("Report request failed for SQS message " + message.getMessageId());
                failures.add(new SQSBatchResponse.BatchItemFailure(message.getMessageId()));
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                for (int remaining = index; remaining < event.getRecords().size(); remaining++) {
                    failures.add(new SQSBatchResponse.BatchItemFailure(
                        event.getRecords().get(remaining).getMessageId()
                    ));
                }
                break;
            }
        }
        return new SQSBatchResponse(failures);
    }

    private static String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(name + " must be configured");
        }
        return value;
    }

    private static HttpClient newHttpClient() {
        return HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(environmentSeconds("REPORT_API_CONNECT_TIMEOUT_SECONDS", 3)))
            .build();
    }

    private static long environmentSeconds(String name, long defaultValue) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        try {
            long seconds = Long.parseLong(value);
            if (seconds < 1) {
                throw new IllegalArgumentException(name + " must be a positive number of seconds");
            }
            return seconds;
        } catch (NumberFormatException exception) {
            throw new IllegalArgumentException(name + " must be a positive number of seconds", exception);
        }
    }

    private static String normalizeBaseUrl(String value) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("Report API URL is required");
        }
        return value.endsWith("/") ? value.substring(0, value.length() - 1) : value;
    }
}
