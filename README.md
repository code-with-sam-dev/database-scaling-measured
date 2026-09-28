# Database scaling, measured

Every number in the video, reproducible on your machine: what each scaling
technique fixes, and the bill it sends you.

Recorded September 2026 with PostgreSQL 17.11 (a primary and a streaming
replica), Redis 7.4.11, Spring Boot 4.1.1 and Java 25. Everything is measured on
one machine; treat the numbers as comparisons, not as a benchmark of your
production.

## Rerun it

You need Docker (about 12 GB for it) and JDK 25.

    scripts/verify.sh

It starts the stack from empty, loads ten million orders, and writes every
transcript the video shows to `captures/`.

## What each chapter measures

| # | Chapter | Script | What it shows |
|---|---|---|---|
| 1 | Measure | `scripts/median.sh` | `EXPLAIN (ANALYZE, BUFFERS)` of a selective query on 10M rows: a full scan to return one row |
| 2 | Index | `verify.sh`, `scripts/insert-bill.sh` | the right composite index against the same columns in the wrong order; insert cost with 0, 1 and 3 indexes |
| 3 | Replica | `scripts/natural-lag.sh`, `stale-read.sh`, `read-your-writes.sh` | replay lag, a stale read with replay deliberately paused, and read-your-writes routing in Spring |
| 4 | Cache | `scripts/stampede.sh`, `invalidation.sh` | 500 callers on one expired key across two app instances: no coordination, in-process single flight, Redis single flight; a stale cached price and invalidation on write |
| 5 | Partition | `sql/05-partition.sql`, `scripts/drop-vs-delete.sh` | partitions touched with and without the partition key; deleting a month against dropping its partition |
| 6 | Shard | `sim/Resharding.java` | keys reassigned when four shards become five: modulo, a ring with one point per shard, a ring with 200 virtual nodes |

The replica stale read pauses WAL replay on purpose, because local lag is
usually well under a second. Every script says what it does at the top.

## Layout

    compose.yaml   primary (5470), replica (5471), redis (6390)
    db/            replication setup
    sql/           data loads and the partitioned table
    scripts/       one script per measurement, plus verify.sh
    app/           the Spring Boot app: read routing, cache-aside, single flight
    sim/           the resharding simulation and the stampede client
    captures/      the transcripts from the recorded run
