package com.example.notificationservice.messaging;

import com.example.notificationservice.event.OrderCreatedEvent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Component;

@Component
public class NotificationListener {

    private static final Logger LOGGER = LoggerFactory.getLogger(NotificationListener.class);

    @KafkaListener(topics = "${app.kafka.order-created-topic}", groupId = "${spring.kafka.consumer.group-id}")
    public void onOrderCreated(@Payload OrderCreatedEvent event,
                               @Header(name = "X-Correlation-Id", required = false) String correlationIdHeader) {
        String correlationId = correlationIdHeader != null ? correlationIdHeader : event.correlationId();
        if (correlationId != null) {
            MDC.put("correlationId", correlationId);
        }

        try {
            LOGGER.info(
                    "Notification processed for orderId={} productNumber={} status={} quantity={}",
                    event.orderId(),
                    event.productNumber(),
                    event.status(),
                    event.quantity()
            );
        } finally {
            MDC.remove("correlationId");
        }
    }
}
