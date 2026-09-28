package dev.example.scaling;

import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.*;

@RestController
public class ProductController {

    private final ProductCache cache;
    private final String mode;

    public ProductController(ProductCache cache, @Value("${cache.coalescing}") String mode) {
        this.cache = cache;
        this.mode = mode;
    }

    @GetMapping("/products/{id}")
    public String product(@PathVariable long id) {
        return cache.product(id);
    }

    @PutMapping("/products/{id}/price/{cents}")
    public String changePrice(@PathVariable long id, @PathVariable int cents) {
        cache.changePrice(id, cents);
        return "price changed, cache entry deleted";
    }

    @GetMapping("/stats")
    public Map<String, Object> stats() {
        return Map.of("mode", mode, "databaseLoads", cache.databaseLoads.get());
    }

    @PostMapping("/stats/reset")
    public void reset() {
        cache.databaseLoads.set(0);
    }
}
