package com.example.orderservice.config;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;

import static org.assertj.core.api.Assertions.assertThat;

class SecurityConfigTest {

    @Test
    void audienceValidatorAcceptsMatchingClientIdWhenAudienceIsMissing() {
        Jwt jwt = new Jwt(
                "token-value",
                Instant.now(),
                Instant.now().plusSeconds(300),
                Map.of("alg", "none"),
                Map.of("client_id", "expected-client")
        );

        OAuth2TokenValidatorResult result =
                SecurityConfig.audienceOrClientIdValidator("expected-client").validate(jwt);

        assertThat(result.hasErrors()).isFalse();
    }

    @Test
    void audienceValidatorAcceptsMatchingAudienceWhenPresent() {
        Jwt jwt = new Jwt(
                "token-value",
                Instant.now(),
                Instant.now().plusSeconds(300),
                Map.of("alg", "none"),
                Map.of("aud", List.of("expected-audience"))
        );

        OAuth2TokenValidatorResult result =
                SecurityConfig.audienceOrClientIdValidator("expected-audience").validate(jwt);

        assertThat(result.hasErrors()).isFalse();
    }
}
