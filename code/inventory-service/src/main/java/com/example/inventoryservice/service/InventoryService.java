package com.example.inventoryservice.service;

import com.example.inventoryservice.config.InventoryProperties;
import com.example.inventoryservice.dto.InventoryAvailabilityResponse;
import com.example.inventoryservice.dto.InventoryReservationRequest;
import com.example.inventoryservice.dto.InventoryReservationResponse;
import jakarta.annotation.PostConstruct;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class InventoryService {

    private final Map<String, Integer> inventory = new ConcurrentHashMap<>();
    private final InventoryProperties inventoryProperties;

    public InventoryService(InventoryProperties inventoryProperties) {
        this.inventoryProperties = inventoryProperties;
    }

    @PostConstruct
    public void seedInventory() {
        inventory.put("PROD001", 100);
        inventory.put("PROD002", 50);
        inventory.put("PROD003", 25);
        inventory.put("PROD004", 75);
        inventory.put("PROD005", 150);
    }

    public InventoryAvailabilityResponse getInventory(String productNumber) {
        ensureServiceAvailable();
        int availableQuantity = inventory.getOrDefault(productNumber, 0);
        return new InventoryAvailabilityResponse(
                productNumber,
                availableQuantity,
                availableQuantity > 0 ? "Inventory available" : "Product is not stocked"
        );
    }

    public synchronized InventoryReservationResponse reserveInventory(InventoryReservationRequest request) {
        ensureServiceAvailable();

        int availableQuantity = inventory.getOrDefault(request.productNumber(), 0);
        if (availableQuantity < request.quantity()) {
            return new InventoryReservationResponse(
                    request.productNumber(),
                    request.quantity(),
                    availableQuantity,
                    false,
                    "Insufficient inventory for reservation"
            );
        }

        int remainingQuantity = availableQuantity - request.quantity();
        inventory.put(request.productNumber(), remainingQuantity);

        return new InventoryReservationResponse(
                request.productNumber(),
                request.quantity(),
                remainingQuantity,
                true,
                "Inventory reserved successfully"
        );
    }

    private void ensureServiceAvailable() {
        if (inventoryProperties.isFailMode()) {
            throw new ResponseStatusException(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Inventory service fail-mode is enabled"
            );
        }
    }
}
