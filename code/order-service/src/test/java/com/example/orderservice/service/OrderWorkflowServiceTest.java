package com.example.orderservice.service;

import com.example.orderservice.dto.CreateOrderRequest;
import com.example.orderservice.dto.OrderResponse;
import org.springframework.context.ApplicationEventPublisher;
import com.example.orderservice.model.Order;
import com.example.orderservice.model.OrderStatus;
import com.example.orderservice.model.Product;
import com.example.orderservice.repository.OrderRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class OrderWorkflowServiceTest {

    @Mock
    private ProductCatalogService productCatalogService;

    @Mock
    private InventoryReservationService inventoryReservationService;

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private ApplicationEventPublisher applicationEventPublisher;

    @InjectMocks
    private OrderWorkflowService orderWorkflowService;

    @Test
    void createOrderMarksOrderAsReservedWhenInventorySucceeds() {
        Product product = new Product("PROD001", "Laptop", 0);
        when(productCatalogService.getRequiredProduct("PROD001")).thenReturn(product);
        when(inventoryReservationService.reserve("PROD001", 2))
                .thenReturn(new InventoryReservationService.InventoryDecision(OrderStatus.RESERVED, "Inventory reserved successfully"));
        when(orderRepository.save(any(Order.class))).thenAnswer(invocation -> invocation.getArgument(0));

        OrderResponse response = orderWorkflowService.createOrder(new CreateOrderRequest("PROD001", 2), "corr-123");

        assertThat(response.productNumber()).isEqualTo("PROD001");
        assertThat(response.status()).isEqualTo("RESERVED");
        assertThat(response.message()).isEqualTo("Inventory reserved successfully");
        verify(applicationEventPublisher).publishEvent(any());
    }

    @Test
    void createOrderKeepsPendingStatusWhenInventoryFallsBack() {
        Product product = new Product("PROD002", "Mouse", 0);
        when(productCatalogService.getRequiredProduct("PROD002")).thenReturn(product);
        when(inventoryReservationService.reserve("PROD002", 1))
                .thenReturn(new InventoryReservationService.InventoryDecision(
                        OrderStatus.PENDING_INVENTORY,
                        "Inventory service is currently unavailable. Fallback order created."
                ));
        when(orderRepository.save(any(Order.class))).thenAnswer(invocation -> invocation.getArgument(0));

        orderWorkflowService.createOrder(new CreateOrderRequest("PROD002", 1), "corr-456");

        ArgumentCaptor<Order> orderCaptor = ArgumentCaptor.forClass(Order.class);
        verify(orderRepository).save(orderCaptor.capture());
        assertThat(orderCaptor.getValue().getStatus()).isEqualTo(OrderStatus.PENDING_INVENTORY);
        assertThat(orderCaptor.getValue().getCorrelationId()).isEqualTo("corr-456");
        verify(applicationEventPublisher).publishEvent(any());
    }
}
