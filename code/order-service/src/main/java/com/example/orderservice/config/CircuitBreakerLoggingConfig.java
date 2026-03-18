package com.example.orderservice.config;

import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Configuration;

@Configuration
public class CircuitBreakerLoggingConfig {

    private static final Logger LOGGER = LoggerFactory.getLogger(CircuitBreakerLoggingConfig.class);

    private final CircuitBreakerRegistry circuitBreakerRegistry;

    public CircuitBreakerLoggingConfig(CircuitBreakerRegistry circuitBreakerRegistry) {
        this.circuitBreakerRegistry = circuitBreakerRegistry;
    }

    @PostConstruct
    void registerInventoryServiceBreakerLogging() {
        var circuitBreaker = circuitBreakerRegistry.circuitBreaker("inventoryService");
        circuitBreaker.getEventPublisher()
                .onStateTransition(event -> LOGGER.warn(
                        "Circuit breaker {} state transition {}",
                        circuitBreaker.getName(),
                        event.getStateTransition()
                ))
                .onCallNotPermitted(event -> LOGGER.warn(
                        "Circuit breaker {} rejected a call because it is {}",
                        circuitBreaker.getName(),
                        circuitBreaker.getState()
                ));
    }
}
