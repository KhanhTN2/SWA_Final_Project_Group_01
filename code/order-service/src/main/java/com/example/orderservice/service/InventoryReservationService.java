package com.example.orderservice.service;

import com.example.orderservice.client.InventoryClient;
import com.example.orderservice.client.dto.InventoryReservationRequest;
import com.example.orderservice.model.OrderStatus;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import org.springframework.stereotype.Service;

@Service
public class InventoryReservationService {

    private final InventoryClient inventoryClient;

    public InventoryReservationService(InventoryClient inventoryClient) {
        this.inventoryClient = inventoryClient;
    }

    @CircuitBreaker(name = "inventoryService", fallbackMethod = "reserveFallback")
    public InventoryDecision reserve(String productNumber, int quantity) {
        var response = inventoryClient.reserveInventory(new InventoryReservationRequest(productNumber, quantity));
        if (response.reserved()) {
            return new InventoryDecision(OrderStatus.RESERVED, response.message());
        }
        return new InventoryDecision(OrderStatus.PENDING_INVENTORY, response.message());
    }

    public InventoryDecision reserveFallback(String productNumber, int quantity, Throwable throwable) {
        return new InventoryDecision(
                OrderStatus.PENDING_INVENTORY,
                "Inventory service is currently unavailable. Fallback order created."
        );
    }

    public record InventoryDecision(OrderStatus status, String message) {
    }
}
