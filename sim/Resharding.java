import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;
import java.util.TreeMap;

/**
 * What happens to key ownership when four shards become five.
 *
 *     java sim/Resharding.java
 *
 * One million deterministic keys ("customer-0" .. "customer-999999"), each
 * hashed once with MD5 so the routing is stable and reproducible on any
 * machine. Three routers are compared:
 *
 *   modulo            shard = hash mod N
 *   ring, 1 vnode     consistent hashing, one point per shard
 *   ring, 200 vnodes  consistent hashing, two hundred points per shard
 *
 * The EXPECTATION for a perfectly balanced consistent hash is that the new
 * fifth shard takes one fifth of the keys and nothing else moves. What each
 * router actually does is measured here, not assumed.
 */
public class Resharding {

    static final int KEYS = 1_000_000;

    static long hash(String s) {
        try {
            byte[] d = MessageDigest.getInstance("MD5")
                    .digest(s.getBytes(StandardCharsets.UTF_8));
            long h = 0;
            for (int i = 0; i < 8; i++) h = (h << 8) | (d[i] & 0xff);
            return h;
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    interface Router { int shardFor(long keyHash); }

    static Router modulo(int shards) {
        return h -> (int) Long.remainderUnsigned(h, shards);
    }

    static Router ring(int shards, int vnodes) {
        TreeMap<Long, Integer> ring = new TreeMap<>();
        for (int s = 0; s < shards; s++)
            for (int v = 0; v < vnodes; v++)
                ring.put(hash("shard-" + s + "#" + v), s);
        return h -> {
            Map.Entry<Long, Integer> e = ring.ceilingEntry(h);
            return (e != null ? e : ring.firstEntry()).getValue();
        };
    }

    static void compare(String name, Router before, Router after, long[] hashes) {
        int moved = 0;
        int[] load = new int[5];
        for (long h : hashes) {
            int b = before.shardFor(h), a = after.shardFor(h);
            if (a != b) moved++;
            load[a]++;
        }
        int min = Integer.MAX_VALUE, max = 0;
        for (int l : load) { min = Math.min(min, l); max = Math.max(max, l); }
        System.out.printf(
                "%-18s moved %6.2f%%   largest shard %5.1f%%   smallest %5.1f%%%n",
                name,
                100.0 * moved / hashes.length,
                100.0 * max / hashes.length,
                100.0 * min / hashes.length);
    }

    public static void main(String[] args) {
        long[] hashes = new long[KEYS];
        for (int i = 0; i < KEYS; i++) hashes[i] = hash("customer-" + i);

        System.out.println("1,000,000 keys, 4 shards -> 5 shards");
        System.out.println(
                "ideal for a balanced consistent hash: 20.00% move, every shard 20.0%");
        System.out.println();
        compare("modulo", modulo(4), modulo(5), hashes);
        compare("ring, 1 vnode", ring(4, 1), ring(5, 1), hashes);
        compare("ring, 200 vnodes", ring(4, 200), ring(5, 200), hashes);
    }
}
