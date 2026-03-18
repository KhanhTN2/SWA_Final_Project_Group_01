package com.example.orderservice.controller;

import com.example.orderservice.dto.ProductViewResponse;
import com.example.orderservice.service.ProductQueryService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping({"/api/product", "/product"})
public class ProductController {

    private final ProductQueryService productQueryService;

    public ProductController(ProductQueryService productQueryService) {
        this.productQueryService = productQueryService;
    }

    @GetMapping("/{productNumber}")
    public ProductViewResponse getProduct(@PathVariable String productNumber) {
        return productQueryService.getProduct(productNumber);
    }
}
