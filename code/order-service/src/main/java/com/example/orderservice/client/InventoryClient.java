package com.example.orderservice.client;

import com.example.orderservice.client.dto.InventoryAvailabilityResponse;
import com.example.orderservice.client.dto.InventoryReservationRequest;
import com.example.orderservice.client.dto.InventoryReservationResponse;
import com.example.orderservice.service.AppConfigOverrideService;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.Objects;

@Component
public class InventoryClient {

    private final RestClient.Builder restClientBuilder;
    private final AppConfigOverrideService appConfigOverrideService;

    public InventoryClient(RestClient.Builder restClientBuilder,
                           AppConfigOverrideService appConfigOverrideService) {
        this.restClientBuilder = restClientBuilder;
        this.appConfigOverrideService = appConfigOverrideService;
    }

    public InventoryAvailabilityResponse getInventory(String productNumber) {
        return Objects.requireNonNull(currentClient().get()
                .uri("/internal/inventory/{productNumber}", productNumber)
                .retrieve()
                .body(InventoryAvailabilityResponse.class));
    }

    public InventoryReservationResponse reserveInventory(InventoryReservationRequest request) {
        return Objects.requireNonNull(currentClient().post()
                .uri("/internal/inventory/reservations")
                .contentType(MediaType.APPLICATION_JSON)
                .body(request)
                .retrieve()
                .body(InventoryReservationResponse.class));
    }

    private RestClient currentClient() {
        return restClientBuilder.baseUrl(appConfigOverrideService.resolveInventoryBaseUrl()).build();
    }
}
