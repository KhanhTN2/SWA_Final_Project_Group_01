package com.example.notificationservice.event;

import java.time.Instant;

public record OrderCreatedEvent(
        String orderId,
        String productNumber,
        String productName,
        int quantity,
        String status,
        String correlationId,
        Instant createdAt
) {
}
