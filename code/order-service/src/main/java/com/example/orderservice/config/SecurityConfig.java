package com.example.orderservice.config;

import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.security.oauth2.resource.OAuth2ResourceServerProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.util.StringUtils;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http, AppProperties properties) throws Exception {
        http.csrf(csrf -> csrf.disable());

        if (!properties.getSecurity().isEnabled()) {
            http.authorizeHttpRequests(authorize -> authorize.anyRequest().permitAll());
            return http.build();
        }

        String readAuthority = "SCOPE_" + properties.getSecurity().getReadScope();
        String writeAuthority = "SCOPE_" + properties.getSecurity().getWriteScope();

        http.authorizeHttpRequests(authorize -> authorize
                .requestMatchers("/actuator/health/**", "/actuator/info", "/actuator/circuitbreakers").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/orders", "/orders").hasAuthority(writeAuthority)
                .requestMatchers(HttpMethod.GET, "/api/orders/**", "/orders/**", "/api/product/**", "/product/**")
                .hasAuthority(readAuthority)
                .anyRequest().authenticated()
        );
        http.oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()));
        return http.build();
    }

    @Bean
    @ConditionalOnProperty(name = "app.security.enabled", havingValue = "true")
    public JwtDecoder jwtDecoder(OAuth2ResourceServerProperties properties, AppProperties appProperties) {
        NimbusJwtDecoder jwtDecoder =
                (NimbusJwtDecoder) JwtDecoders.fromIssuerLocation(properties.getJwt().getIssuerUri());

        OAuth2TokenValidator<Jwt> withIssuer = JwtValidators.createDefaultWithIssuer(properties.getJwt().getIssuerUri());
        OAuth2TokenValidator<Jwt> audienceValidator = audienceOrClientIdValidator(appProperties.getSecurity().getAudience());

        jwtDecoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(withIssuer, audienceValidator));
        return jwtDecoder;
    }

    static OAuth2TokenValidator<Jwt> audienceOrClientIdValidator(String expectedAudience) {
        return token -> {
            if (!StringUtils.hasText(expectedAudience)) {
                return OAuth2TokenValidatorResult.success();
            }

            List<String> audiences = token.getAudience();
            if (audiences != null && audiences.contains(expectedAudience)) {
                return OAuth2TokenValidatorResult.success();
            }

            String clientId = token.getClaimAsString("client_id");
            if (expectedAudience.equals(clientId)) {
                return OAuth2TokenValidatorResult.success();
            }

            return OAuth2TokenValidatorResult.failure(
                    new OAuth2Error("invalid_token", "Required audience or client_id is missing", null)
            );
        };
    }
}
