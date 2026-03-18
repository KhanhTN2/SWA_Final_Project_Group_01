package com.example.orderservice.dto;

public record ProductViewResponse(
        String productNumber,
        String name,
        int numberOnStock,
        String message
) {
}
