package com.example.orderservice.config;

import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class SecurityConfigValidatorTest {

    @Test
    void acceptsCognitoAccessTokenClientIdWhenAudienceClaimIsMissing() {
        Jwt jwt = jwt(Map.of("client_id", "demo-client"));

        OAuth2TokenValidatorResult result = SecurityConfig.audienceOrClientIdValidator("demo-client").validate(jwt);

        assertThat(result.hasErrors()).isFalse();
    }

    @Test
    void acceptsAudienceClaimWhenPresent() {
        Jwt jwt = jwt(Map.of("aud", List.of("demo-client")));

        OAuth2TokenValidatorResult result = SecurityConfig.audienceOrClientIdValidator("demo-client").validate(jwt);

        assertThat(result.hasErrors()).isFalse();
    }

    @Test
    void rejectsTokenWhenNeitherAudienceNorClientIdMatches() {
        Jwt jwt = jwt(Map.of("client_id", "different-client"));

        OAuth2TokenValidatorResult result = SecurityConfig.audienceOrClientIdValidator("demo-client").validate(jwt);

        assertThat(result.hasErrors()).isTrue();
    }

    private Jwt jwt(Map<String, Object> claims) {
        return new Jwt(
                "token-value",
                Instant.now(),
                Instant.now().plusSeconds(300),
                Map.of("alg", "none"),
                claims
        );
    }
}
