package com.example.orderservice.service;

import com.example.orderservice.dto.CreateOrderRequest;
import com.example.orderservice.dto.OrderResponse;
import com.example.orderservice.event.OrderCreatedEvent;
import com.example.orderservice.model.Order;
import com.example.orderservice.model.Product;
import com.example.orderservice.repository.OrderRepository;
import jakarta.transaction.Transactional;
import org.springframework.http.HttpStatus;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
public class OrderWorkflowService {

    private final ProductCatalogService productCatalogService;
    private final InventoryReservationService inventoryReservationService;
    private final OrderRepository orderRepository;
    private final ApplicationEventPublisher applicationEventPublisher;

    public OrderWorkflowService(ProductCatalogService productCatalogService,
                                InventoryReservationService inventoryReservationService,
                                OrderRepository orderRepository,
                                ApplicationEventPublisher applicationEventPublisher) {
        this.productCatalogService = productCatalogService;
        this.inventoryReservationService = inventoryReservationService;
        this.orderRepository = orderRepository;
        this.applicationEventPublisher = applicationEventPublisher;
    }

    @Transactional
    public OrderResponse createOrder(CreateOrderRequest request, String correlationId) {
        Product product = productCatalogService.getRequiredProduct(request.productNumber());
        InventoryReservationService.InventoryDecision decision =
                inventoryReservationService.reserve(product.getProductNumber(), request.quantity());

        Order order = new Order();
        order.setProductNumber(product.getProductNumber());
        order.setProductName(product.getName());
        order.setQuantity(request.quantity());
        order.setStatus(decision.status());
        order.setMessage(decision.message());
        order.setCorrelationId(correlationId);

        Order savedOrder = orderRepository.save(order);
        applicationEventPublisher.publishEvent(new OrderCreatedEvent(
                savedOrder.getOrderId(),
                savedOrder.getProductNumber(),
                savedOrder.getProductName(),
                savedOrder.getQuantity(),
                savedOrder.getStatus().name(),
                savedOrder.getCorrelationId(),
                savedOrder.getCreatedAt()
        ));
        return OrderResponse.from(savedOrder);
    }

    public OrderResponse getOrder(String orderId) {
        return orderRepository.findById(orderId)
                .map(OrderResponse::from)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND,
                        "Order not found: " + orderId
                ));
    }
}
