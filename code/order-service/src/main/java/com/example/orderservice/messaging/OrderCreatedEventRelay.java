package com.example.orderservice.messaging;

import com.example.orderservice.event.OrderCreatedEvent;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

@Component
public class OrderCreatedEventRelay {

    private final OrderEventPublisher orderEventPublisher;

    public OrderCreatedEventRelay(OrderEventPublisher orderEventPublisher) {
        this.orderEventPublisher = orderEventPublisher;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onOrderCreated(OrderCreatedEvent event) {
        orderEventPublisher.publish(event);
    }
}
