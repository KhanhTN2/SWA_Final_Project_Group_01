package com.example.notificationservice.config;

import org.apache.kafka.clients.admin.NewTopic;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;

@Configuration
public class KafkaTopicConfiguration {

    @Bean
    public NewTopic orderCreatedTopic(NotificationProperties properties) {
        return TopicBuilder.name(properties.getOrderCreatedTopic())
                .partitions(1)
                .build();
    }
}
