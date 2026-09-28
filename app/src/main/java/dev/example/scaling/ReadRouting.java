package dev.example.scaling;

import java.util.Map;
import javax.sql.DataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.jdbc.datasource.LazyConnectionDataSourceProxy;
import org.springframework.jdbc.datasource.lookup.AbstractRoutingDataSource;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Read-only transactions go to the replica, everything else to the primary,
 * unless this request has been told to read its own writes.
 *
 * This does not fix replica lag. It decides, per request, which requests are
 * allowed to see it.
 */
@Configuration
public class ReadRouting {

    public enum Target { PRIMARY, REPLICA }

    /** Set for the current request when the caller must see its own writes. */
    public static final ThreadLocal<Boolean> READ_YOUR_WRITES = ThreadLocal.withInitial(() -> false);

    static class Router extends AbstractRoutingDataSource {
        @Override
        protected Object determineCurrentLookupKey() {
            boolean readOnly = TransactionSynchronizationManager.isCurrentTransactionReadOnly();
            return readOnly && !READ_YOUR_WRITES.get() ? Target.REPLICA : Target.PRIMARY;
        }
    }

    @Bean
    @Primary
    DataSource dataSource(@Value("${primary.url}") String primary, @Value("${replica.url}") String replica,
                          @Value("${db.username}") String user, @Value("${db.password}") String password) {
        var primaryDb = pool(primary, user, password);
        var router = new Router();
        router.setTargetDataSources(Map.of(
                Target.PRIMARY, primaryDb,
                Target.REPLICA, pool(replica, user, password)));
        router.setDefaultTargetDataSource(primaryDb);
        router.afterPropertiesSet();
        // The connection is only fetched once the transaction's read-only flag is known.
        return new LazyConnectionDataSourceProxy(router);
    }

    /** A bounded pool per database: 20 connections, so two instances stay under max_connections. */
    private static DataSource pool(String url, String user, String password) {
        var ds = new HikariDataSource();
        ds.setDriverClassName("org.postgresql.Driver");
        ds.setJdbcUrl(url);
        ds.setUsername(user);
        ds.setPassword(password);
        ds.setMaximumPoolSize(20);
        return ds;
    }
}
