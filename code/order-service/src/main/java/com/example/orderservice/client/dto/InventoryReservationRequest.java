package com.example.orderservice.client.dto;

public record InventoryReservationRequest(
        String productNumber,
        int quantity
) {
}
