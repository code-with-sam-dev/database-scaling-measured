-- Ten million orders, deterministic (setseed), spread over one million
-- customers and twelve months of 2026. No indexes except the primary key.
SELECT setseed(0.42);
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    id           bigint PRIMARY KEY,
    customer_id  int         NOT NULL,
    status       text        NOT NULL,
    created_at   timestamptz NOT NULL,
    amount_cents bigint      NOT NULL
);
INSERT INTO orders
SELECT g,
       (random() * 999999)::int + 1,
       (ARRAY['PAID','PAID','PAID','PAID','PAID','PAID','PAID','PAID','CANCELLED','PENDING'])[(random()*9)::int + 1],
       timestamptz '2026-01-01' + random() * interval '365 days',
       (random() * 20000)::bigint + 100
FROM generate_series(1, 10000000) g;
VACUUM ANALYZE orders;
