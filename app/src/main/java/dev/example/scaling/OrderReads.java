package dev.example.scaling;

import java.util.Map;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class OrderReads {

    private final JdbcClient db;

    public OrderReads(JdbcClient db) {
        this.db = db;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> find(long id) {
        return db.sql("""
                SELECT id, status,
                       CASE WHEN pg_is_in_recovery() THEN 'replica' \
                ELSE 'primary' END AS served_by
                FROM orders WHERE id = :id""")
                .param("id", id).query().singleRow();
    }
}
