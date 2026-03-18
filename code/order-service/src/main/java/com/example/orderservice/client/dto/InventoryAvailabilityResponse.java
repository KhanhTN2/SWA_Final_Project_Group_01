package com.example.orderservice.client.dto;

public record InventoryAvailabilityResponse(
        String productNumber,
        int availableQuantity,
        String message
) {
}
