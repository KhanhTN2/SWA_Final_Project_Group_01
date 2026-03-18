package com.example.inventoryservice.dto;

public record InventoryAvailabilityResponse(
        String productNumber,
        int availableQuantity,
        String message
) {
}
