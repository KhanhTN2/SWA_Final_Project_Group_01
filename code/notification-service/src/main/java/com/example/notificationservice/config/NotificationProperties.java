package com.example.notificationservice.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app.kafka")
public class NotificationProperties {

    private String orderCreatedTopic = "orders.created";

    public String getOrderCreatedTopic() {
        return orderCreatedTopic;
    }

    public void setOrderCreatedTopic(String orderCreatedTopic) {
        this.orderCreatedTopic = orderCreatedTopic;
    }
}
