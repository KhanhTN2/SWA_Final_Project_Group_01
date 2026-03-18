package com.example.inventoryservice.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;

public record InventoryReservationRequest(
        @NotBlank String productNumber,
        @Min(1) int quantity
) {
}
