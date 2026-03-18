package com.example.orderservice.service;

import com.example.orderservice.model.Product;
import com.example.orderservice.repository.ProductRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
public class ProductCatalogService {

    private final ProductRepository productRepository;

    public ProductCatalogService(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    public Product getRequiredProduct(String productNumber) {
        return productRepository.findById(productNumber)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND,
                        "Product not found: " + productNumber
                ));
    }
}
