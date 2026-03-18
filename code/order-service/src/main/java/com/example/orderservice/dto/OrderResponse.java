package com.example.orderservice.dto;

import com.example.orderservice.model.Order;

import java.time.Instant;

public record OrderResponse(
        String orderId,
        String productNumber,
        String productName,
        int quantity,
        String status,
        String message,
        String correlationId,
        Instant createdAt
) {
    public static OrderResponse from(Order order) {
        return new OrderResponse(
                order.getOrderId(),
                order.getProductNumber(),
                order.getProductName(),
                order.getQuantity(),
                order.getStatus().name(),
                order.getMessage(),
                order.getCorrelationId(),
                order.getCreatedAt()
        );
    }
}
