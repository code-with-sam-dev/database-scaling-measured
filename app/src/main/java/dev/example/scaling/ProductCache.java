package dev.example.scaling;

import java.time.Duration;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

/**
 * Cache-aside in front of an expensive query, with three ways of handling
 * many requests that miss at the same moment.
 *
 *   none   every request that misses loads from the database
 *   local  one load per application instance (in-process single flight)
 *   redis  one load across all instances: the winner of a Redis lock loads
 *          and fills the cache, the others wait for the cache to fill
 */
@Service
public class ProductCache {

    private final JdbcClient db;
    private final StringRedisTemplate redis;
    private final String coalescing;
    private final Duration ttl;

    /** How many times this instance actually ran the database query. */
    final AtomicInteger databaseLoads = new AtomicInteger();

    private final ConcurrentHashMap<String, CompletableFuture<String>> inFlight = new ConcurrentHashMap<>();

    public ProductCache(JdbcClient db, StringRedisTemplate redis,
                        @Value("${cache.coalescing}") String coalescing,
                        @Value("${cache.ttl-seconds}") long ttlSeconds) {
        this.db = db;
        this.redis = redis;
        this.coalescing = coalescing;
        this.ttl = Duration.ofSeconds(ttlSeconds);
    }

    public String product(long id) {
        String key = "product:" + id;
        String cached = redis.opsForValue().get(key);
        if (cached != null) return cached;
        return switch (coalescing) {
            case "local" -> inFlight.computeIfAbsent(key, k -> CompletableFuture.supplyAsync(() -> loadAndCache(k, id)))
                    .whenComplete((v, e) -> inFlight.remove(key)).join();
            case "redis" -> singleFlightAcrossInstances(key, id);
            default -> loadAndCache(key, id);
        };
    }

    private String singleFlightAcrossInstances(String key, long id) {
        String lock = "lock:" + key;
        String token = UUID.randomUUID().toString();
        if (Boolean.TRUE.equals(redis.opsForValue().setIfAbsent(lock, token, Duration.ofSeconds(5)))) {
            try {
                // Re-check: the previous winner may have filled the cache and
                // released the lock between our miss and our lock.
                String filled = redis.opsForValue().get(key);
                return filled != null ? filled : loadAndCache(key, id);
            } finally {
                if (token.equals(redis.opsForValue().get(lock))) redis.delete(lock);
            }
        }
        // Lost the race: wait for the winner to fill the cache rather than load.
        for (int i = 0; i < 250; i++) {
            String cached = redis.opsForValue().get(key);
            if (cached != null) return cached;
            sleep(20);
        }
        return loadAndCache(key, id);
    }

    /** A price change: write Postgres first, then delete the cached copy so the next read reloads. */
    public void changePrice(long id, int priceCents) {
        db.sql("UPDATE products SET price_cents = :p WHERE id = :id").param("p", priceCents).param("id", id).update();
        redis.delete("product:" + id);
    }

    private String loadAndCache(String key, long id) {
        databaseLoads.incrementAndGet();
        // An expensive query, slowed to 200 ms on purpose so misses overlap.
        String product = db.sql("SELECT name || ' ' || price_cents FROM products, pg_sleep(0.2) WHERE id = :id")
                .param("id", id).query(String.class).single();
        redis.opsForValue().set(key, product, ttl);
        return product;
    }

    private static void sleep(long ms) {
        try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
    }
}
