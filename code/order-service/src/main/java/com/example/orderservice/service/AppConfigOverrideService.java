package com.example.orderservice.service;

import com.example.orderservice.config.AppProperties;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClient;

@Service
public class AppConfigOverrideService {

    private static final Logger LOGGER = LoggerFactory.getLogger(AppConfigOverrideService.class);

    private final RestClient restClient;
    private final AppProperties properties;
    private final ObjectMapper objectMapper;

    private volatile RuntimeOverrides runtimeOverrides = RuntimeOverrides.empty();

    public AppConfigOverrideService(RestClient.Builder restClientBuilder,
                                    AppProperties properties,
                                    ObjectMapper objectMapper) {
        this.restClient = restClientBuilder.build();
        this.properties = properties;
        this.objectMapper = objectMapper;
    }

    @PostConstruct
    public void loadOverrides() {
        if (!properties.getAppConfig().isEnabled()) {
            return;
        }

        try {
            String payload = restClient.get()
                    .uri(properties.getAppConfig().getBaseUrl() + properties.getAppConfig().getResourcePath())
                    .retrieve()
                    .body(String.class);

            if (!StringUtils.hasText(payload)) {
                LOGGER.warn("AppConfig agent returned an empty payload. Falling back to local defaults.");
                return;
            }

            JsonNode root = objectMapper.readTree(payload);
            runtimeOverrides = new RuntimeOverrides(
                    text(root, "inventoryBaseUrl"),
                    text(root, "orderCreatedTopic")
            );
            LOGGER.info("Loaded runtime overrides from AppConfig agent");
        } catch (Exception exception) {
            LOGGER.warn("Unable to load AppConfig overrides. Falling back to local defaults.", exception);
        }
    }

    public String resolveInventoryBaseUrl() {
        if (StringUtils.hasText(runtimeOverrides.inventoryBaseUrl())) {
            return runtimeOverrides.inventoryBaseUrl();
        }
        return properties.getInventory().getBaseUrl();
    }

    public String resolveOrderCreatedTopic() {
        if (StringUtils.hasText(runtimeOverrides.orderCreatedTopic())) {
            return runtimeOverrides.orderCreatedTopic();
        }
        return properties.getKafka().getOrderCreatedTopic();
    }

    private String text(JsonNode root, String fieldName) {
        JsonNode node = root.get(fieldName);
        return node == null || node.isNull() ? null : node.asText();
    }

    private record RuntimeOverrides(String inventoryBaseUrl, String orderCreatedTopic) {
        static RuntimeOverrides empty() {
            return new RuntimeOverrides(null, null);
        }
    }
}
