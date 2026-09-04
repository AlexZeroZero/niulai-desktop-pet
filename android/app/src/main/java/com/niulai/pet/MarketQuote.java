package com.niulai.pet;

final class MarketQuote {
    final String name;
    final double price;
    final double percent;
    final long timestamp;

    MarketQuote(String name, double price, double percent) {
        this.name = name;
        this.price = price;
        this.percent = percent;
        this.timestamp = System.currentTimeMillis();
    }
}
