package com.example.orderservice.controller;

import com.example.orderservice.config.AppProperties;
import com.example.orderservice.config.CorrelationIdFilter;
import com.example.orderservice.config.SecurityConfig;
import com.example.orderservice.dto.OrderResponse;
import com.example.orderservice.dto.ProductViewResponse;
import com.example.orderservice.service.OrderWorkflowService;
import com.example.orderservice.service.ProductQueryService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(controllers = {OrderController.class, ProductController.class})
@Import({SecurityConfig.class, CorrelationIdFilter.class})
@EnableConfigurationProperties(AppProperties.class)
@TestPropertySource(properties = {
        "app.security.enabled=true",
        "app.security.read-scope=orders/read",
        "app.security.write-scope=orders/write"
})
class OrderControllerSecurityTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private JwtDecoder jwtDecoder;

    @MockBean
    private OrderWorkflowService orderWorkflowService;

    @MockBean
    private ProductQueryService productQueryService;

    @Test
    void postOrdersRequiresWriteScope() throws Exception {
        when(orderWorkflowService.createOrder(any(), any())).thenReturn(
                new OrderResponse("order-1", "PROD001", "Laptop", 1, "RESERVED", "ok", "corr-1", Instant.now())
        );

        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"productNumber\":\"PROD001\",\"quantity\":1}")
                        .with(jwt().authorities(() -> "SCOPE_orders/write")))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.status").value("RESERVED"));

        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"productNumber\":\"PROD001\",\"quantity\":1}")
                        .with(jwt().authorities(() -> "SCOPE_orders/read")))
                .andExpect(status().isForbidden());
    }

    @Test
    void getProductRequiresReadScope() throws Exception {
        when(productQueryService.getProduct(eq("PROD001")))
                .thenReturn(new ProductViewResponse("PROD001", "Laptop", 98, "Inventory available"));

        mockMvc.perform(get("/api/product/PROD001")
                        .with(SecurityMockMvcRequestPostProcessors.jwt().authorities(() -> "SCOPE_orders/read")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.productNumber").value("PROD001"));

        mockMvc.perform(get("/api/product/PROD001")
                        .with(SecurityMockMvcRequestPostProcessors.jwt().authorities(() -> "SCOPE_orders/write")))
                .andExpect(status().isForbidden());
    }
}
