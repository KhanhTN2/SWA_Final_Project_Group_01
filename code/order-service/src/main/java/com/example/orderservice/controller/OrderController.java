package com.example.orderservice.controller;

import com.example.orderservice.config.CorrelationIdFilter;
import com.example.orderservice.dto.CreateOrderRequest;
import com.example.orderservice.dto.OrderResponse;
import com.example.orderservice.service.OrderWorkflowService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping({"/api/orders", "/orders"})
public class OrderController {

    private final OrderWorkflowService orderWorkflowService;

    public OrderController(OrderWorkflowService orderWorkflowService) {
        this.orderWorkflowService = orderWorkflowService;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public OrderResponse createOrder(@Valid @RequestBody CreateOrderRequest request, HttpServletRequest httpServletRequest) {
        return orderWorkflowService.createOrder(
                request,
                (String) httpServletRequest.getAttribute(CorrelationIdFilter.ATTRIBUTE_NAME)
        );
    }

    @GetMapping("/{orderId}")
    public OrderResponse getOrder(@PathVariable String orderId) {
        return orderWorkflowService.getOrder(orderId);
    }
}
