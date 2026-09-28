-- The write bill of indexes. A copy of the schema with one million rows, then
-- 100,000 rows inserted in one statement, timed. Run with 0, 1 and 3 indexes.
-- The insert runs inside a transaction that is rolled back, so every run starts
-- from the same table; VACUUM clears what the rollback left behind.
DROP TABLE IF EXISTS orders_w;
CREATE TABLE orders_w (LIKE orders INCLUDING DEFAULTS);
ALTER TABLE orders_w ADD PRIMARY KEY (id);
INSERT INTO orders_w SELECT * FROM orders WHERE id <= 1000000;
