package com.example.orderservice.messaging;

import com.example.orderservice.event.OrderCreatedEvent;
import com.example.orderservice.service.AppConfigOverrideService;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

@Component
public class OrderEventPublisher {

    private static final Logger LOGGER = LoggerFactory.getLogger(OrderEventPublisher.class);

    private final KafkaTemplate<String, OrderCreatedEvent> kafkaTemplate;
    private final AppConfigOverrideService appConfigOverrideService;

    public OrderEventPublisher(KafkaTemplate<String, OrderCreatedEvent> kafkaTemplate,
                               AppConfigOverrideService appConfigOverrideService) {
        this.kafkaTemplate = kafkaTemplate;
        this.appConfigOverrideService = appConfigOverrideService;
    }

    public void publish(OrderCreatedEvent event) {
        ProducerRecord<String, OrderCreatedEvent> record =
                new ProducerRecord<>(appConfigOverrideService.resolveOrderCreatedTopic(), event.orderId(), event);

        if (event.correlationId() != null) {
            record.headers().add("X-Correlation-Id", event.correlationId().getBytes(StandardCharsets.UTF_8));
        }

        try {
            kafkaTemplate.send(record).get(10, TimeUnit.SECONDS);
            LOGGER.info("Published order-created event for orderId={}", event.orderId());
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to publish order-created event for orderId=" + event.orderId(), exception);
        }
    }
}
