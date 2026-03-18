package com.example.inventoryservice.controller;

import com.example.inventoryservice.dto.InventoryAvailabilityResponse;
import com.example.inventoryservice.dto.InventoryReservationRequest;
import com.example.inventoryservice.dto.InventoryReservationResponse;
import com.example.inventoryservice.service.InventoryService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/internal/inventory")
public class InventoryController {

    private final InventoryService inventoryService;

    public InventoryController(InventoryService inventoryService) {
        this.inventoryService = inventoryService;
    }

    @GetMapping("/{productNumber}")
    public InventoryAvailabilityResponse getInventory(@PathVariable String productNumber) {
        return inventoryService.getInventory(productNumber);
    }

    @PostMapping("/reservations")
    public InventoryReservationResponse reserveInventory(@Valid @RequestBody InventoryReservationRequest request) {
        return inventoryService.reserveInventory(request);
    }
}
