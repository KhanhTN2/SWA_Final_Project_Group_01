package com.example.orderservice.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;

public record CreateOrderRequest(
        @NotBlank String productNumber,
        @Min(1) int quantity
) {
}
