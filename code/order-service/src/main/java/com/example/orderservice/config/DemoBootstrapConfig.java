package com.example.orderservice.config;

import com.example.orderservice.model.Product;
import com.example.orderservice.repository.ProductRepository;
import java.util.List;
import org.apache.kafka.clients.admin.NewTopic;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;

@Configuration
public class DemoBootstrapConfig {

    private static final Logger LOGGER = LoggerFactory.getLogger(DemoBootstrapConfig.class);

    @Bean
    public ApplicationRunner productCatalogSeeder(ProductRepository productRepository) {
        List<Product> defaults = List.of(
                new Product("PROD001", "Laptop", 0),
                new Product("PROD002", "Mouse", 0),
                new Product("PROD003", "Keyboard", 0),
                new Product("PROD004", "Monitor", 0),
                new Product("PROD005", "Headphones", 0)
        );

        return arguments -> {
            int inserted = 0;
            for (Product product : defaults) {
                if (productRepository.existsById(product.getProductNumber())) {
                    continue;
                }
                productRepository.save(new Product(product.getProductNumber(), product.getName(), 0));
                inserted++;
            }

            if (inserted > 0) {
                LOGGER.info("Seeded {} default catalog products", inserted);
            } else {
                LOGGER.info("Default catalog products already present");
            }
        };
    }

    @Bean
    public NewTopic orderCreatedTopic(AppProperties appProperties) {
        return TopicBuilder.name(appProperties.getKafka().getOrderCreatedTopic())
                .partitions(1)
                .build();
    }
}
