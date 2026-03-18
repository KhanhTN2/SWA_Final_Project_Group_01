package com.example.inventoryservice.service;

import com.example.inventoryservice.config.InventoryProperties;
import com.example.inventoryservice.dto.InventoryReservationRequest;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class InventoryServiceTest {

    @Test
    void reserveInventoryReducesAvailableQuantity() {
        InventoryProperties properties = new InventoryProperties();
        InventoryService inventoryService = new InventoryService(properties);
        inventoryService.seedInventory();

        var response = inventoryService.reserveInventory(new InventoryReservationRequest("PROD001", 5));

        assertThat(response.reserved()).isTrue();
        assertThat(response.availableQuantity()).isEqualTo(95);
    }

    @Test
    void failModeRaisesServiceUnavailable() {
        InventoryProperties properties = new InventoryProperties();
        properties.setFailMode(true);
        InventoryService inventoryService = new InventoryService(properties);
        inventoryService.seedInventory();

        assertThatThrownBy(() -> inventoryService.getInventory("PROD001"))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("Inventory service fail-mode is enabled");
    }
}
