package com.example.inventoryservice.dto;

public record InventoryReservationResponse(
        String productNumber,
        int requestedQuantity,
        int availableQuantity,
        boolean reserved,
        String message
) {
}
