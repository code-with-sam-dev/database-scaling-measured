package dev.example.scaling;

import java.util.Map;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

@RestController
public class OrderController {

    private final JdbcClient db;
    private final OrderReads reads;

    public OrderController(JdbcClient db, OrderReads reads) {
        this.db = db;
        this.reads = reads;
    }

    @PostMapping("/orders/{id}/pay")
    @Transactional
    public Map<String, Object> pay(@PathVariable long id) {
        db.sql("UPDATE orders SET status = 'PAID' WHERE id = :id")
                .param("id", id)
                .update();
        return Map.of("order", id, "status", "PAID");
    }

    /** Header X-Read-Your-Writes: true routes this read to the primary. */
    @GetMapping("/orders/{id}")
    public Map<String, Object> get(
            @PathVariable long id,
            @RequestHeader(value = "X-Read-Your-Writes", defaultValue = "false")
            boolean ryw) {
        ReadRouting.READ_YOUR_WRITES.set(ryw);
        try {
            return reads.find(id);
        } finally {
            ReadRouting.READ_YOUR_WRITES.remove();
        }
    }
}
