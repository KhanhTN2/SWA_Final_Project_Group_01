package com.example.orderservice.service;

import com.example.orderservice.client.InventoryClient;
import com.example.orderservice.dto.ProductViewResponse;
import com.example.orderservice.model.Product;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import org.springframework.stereotype.Service;

@Service
public class ProductQueryService {

    private final ProductCatalogService productCatalogService;
    private final InventoryClient inventoryClient;

    public ProductQueryService(ProductCatalogService productCatalogService, InventoryClient inventoryClient) {
        this.productCatalogService = productCatalogService;
        this.inventoryClient = inventoryClient;
    }

    @CircuitBreaker(name = "inventoryService", fallbackMethod = "getProductFallback")
    public ProductViewResponse getProduct(String productNumber) {
        Product product = productCatalogService.getRequiredProduct(productNumber);
        var inventory = inventoryClient.getInventory(productNumber);
        return new ProductViewResponse(
                product.getProductNumber(),
                product.getName(),
                inventory.availableQuantity(),
                inventory.message()
        );
    }

    public ProductViewResponse getProductFallback(String productNumber, Throwable throwable) {
        Product product = productCatalogService.getRequiredProduct(productNumber);
        return new ProductViewResponse(
                product.getProductNumber(),
                product.getName(),
                0,
                "Inventory service is currently unavailable. Compatibility response returned."
        );
    }
}
