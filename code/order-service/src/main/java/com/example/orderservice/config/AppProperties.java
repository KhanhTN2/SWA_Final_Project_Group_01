package com.example.orderservice.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app")
public class AppProperties {

    private final Inventory inventory = new Inventory();
    private final Kafka kafka = new Kafka();
    private final Security security = new Security();
    private final Aws aws = new Aws();
    private final AppConfig appConfig = new AppConfig();

    public Inventory getInventory() {
        return inventory;
    }

    public Kafka getKafka() {
        return kafka;
    }

    public Security getSecurity() {
        return security;
    }

    public Aws getAws() {
        return aws;
    }

    public AppConfig getAppConfig() {
        return appConfig;
    }

    public static class Inventory {
        private String baseUrl = "http://inventory-service:8080";

        public String getBaseUrl() {
            return baseUrl;
        }

        public void setBaseUrl(String baseUrl) {
            this.baseUrl = baseUrl;
        }
    }

    public static class Kafka {
        private String orderCreatedTopic = "orders.created";

        public String getOrderCreatedTopic() {
            return orderCreatedTopic;
        }

        public void setOrderCreatedTopic(String orderCreatedTopic) {
            this.orderCreatedTopic = orderCreatedTopic;
        }
    }

    public static class Security {
        private boolean enabled;
        private String audience;
        private String readScope = "orders/read";
        private String writeScope = "orders/write";

        public boolean isEnabled() {
            return enabled;
        }

        public void setEnabled(boolean enabled) {
            this.enabled = enabled;
        }

        public String getAudience() {
            return audience;
        }

        public void setAudience(String audience) {
            this.audience = audience;
        }

        public String getReadScope() {
            return readScope;
        }

        public void setReadScope(String readScope) {
            this.readScope = readScope;
        }

        public String getWriteScope() {
            return writeScope;
        }

        public void setWriteScope(String writeScope) {
            this.writeScope = writeScope;
        }
    }

    public static class Aws {
        private String region = "us-east-1";

        public String getRegion() {
            return region;
        }

        public void setRegion(String region) {
            this.region = region;
        }
    }

    public static class AppConfig {
        private boolean enabled;
        private String baseUrl = "http://localhost:2772";
        private String resourcePath = "/applications/order-platform/environments/demo/configurations/runtime";

        public boolean isEnabled() {
            return enabled;
        }

        public void setEnabled(boolean enabled) {
            this.enabled = enabled;
        }

        public String getBaseUrl() {
            return baseUrl;
        }

        public void setBaseUrl(String baseUrl) {
            this.baseUrl = baseUrl;
        }

        public String getResourcePath() {
            return resourcePath;
        }

        public void setResourcePath(String resourcePath) {
            this.resourcePath = resourcePath;
        }
    }
}
