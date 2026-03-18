package com.example.inventoryservice.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app")
public class InventoryProperties {

    private boolean failMode;

    public boolean isFailMode() {
        return failMode;
    }

    public void setFailMode(boolean failMode) {
        this.failMode = failMode;
    }
}
