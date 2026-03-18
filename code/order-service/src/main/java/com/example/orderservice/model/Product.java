package com.example.orderservice.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;

@Entity
@Table(name = "products")
public class Product {

    @Id
    @Column(name = "product_number")
    private String productNumber;

    @Column(name = "name", nullable = false)
    private String name;

    @Transient
    private int numberOnStock;

    @Transient
    private String message;

    public Product() {
    }

    public Product(String productNumber, String name, int numberOnStock) {
        this.productNumber = productNumber;
        this.name = name;
        this.numberOnStock = numberOnStock;
    }

    public Product(String productNumber, String name, int numberOnStock, String message) {
        this.productNumber = productNumber;
        this.name = name;
        this.numberOnStock = numberOnStock;
        this.message = message;
    }

    public String getProductNumber() {
        return productNumber;
    }

    public void setProductNumber(String productNumber) {
        this.productNumber = productNumber;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public int getNumberOnStock() {
        return numberOnStock;
    }

    public void setNumberOnStock(int numberOnStock) {
        this.numberOnStock = numberOnStock;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }

    @Override
    public String toString() {
        return "Product{" +
                "productNumber='" + productNumber + '\'' +
                ", name='" + name + '\'' +
                ", numberOnStock=" + numberOnStock +
                ", message='" + message + '\'' +
                '}';
    }
}
