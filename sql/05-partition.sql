-- The same ten million orders, partitioned by month on created_at, with a
-- local index on customer_id in every partition.
DROP TABLE IF EXISTS orders_p;
CREATE TABLE orders_p (LIKE orders) PARTITION BY RANGE (created_at);
DO $$
BEGIN
  FOR m IN 1..12 LOOP
    EXECUTE format(
      'CREATE TABLE orders_p_2026_%s PARTITION OF orders_p '
      || 'FOR VALUES FROM (%L) TO (%L)',
      lpad(m::text, 2, '0'),
      make_timestamptz(2026, m, 1, 0, 0, 0, 'UTC'),
      CASE WHEN m = 12
        THEN make_timestamptz(2027, 1, 1, 0, 0, 0, 'UTC')
        ELSE make_timestamptz(2026, m + 1, 1, 0, 0, 0, 'UTC')
      END);
  END LOOP;
END $$;
INSERT INTO orders_p SELECT * FROM orders;
CREATE INDEX ON orders_p (customer_id);
VACUUM ANALYZE orders_p;
