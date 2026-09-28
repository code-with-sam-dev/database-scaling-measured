import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * 500 callers released at the same instant against one expired cache key,
 * split evenly across two application instances.
 *
 *     java sim/Stampede.java 500 8081 8082
 *
 * This client only fires requests. What is measured is how many times the
 * applications ran the database query, read from their /stats endpoints.
 */
public class Stampede {
    public static void main(String[] args) throws Exception {
        int callers = Integer.parseInt(args[0]);
        String[] ports = {args[1], args[2]};
        HttpClient http = HttpClient.newBuilder()
                .executor(Executors.newVirtualThreadPerTaskExecutor())
                .build();
        CountDownLatch ready = new CountDownLatch(callers),
                go = new CountDownLatch(1),
                done = new CountDownLatch(callers);
        AtomicInteger ok = new AtomicInteger();
        try (var pool = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < callers; i++) {
                String port = ports[i % 2];
                pool.submit(() -> {
                    ready.countDown();
                    try {
                        go.await();
                        var r = http.send(
                                HttpRequest.newBuilder(URI.create(
                                        "http://localhost:" + port + "/products/42"))
                                        .build(),
                                HttpResponse.BodyHandlers.ofString());
                        if (r.statusCode() == 200) ok.incrementAndGet();
                    } catch (Exception e) {
                        // counted as not ok
                    } finally {
                        done.countDown();
                    }
                    return null;
                });
            }
            ready.await();
            go.countDown();
            done.await();
        }
        System.out.println(callers + " callers, " + ok.get() + " answered");
    }
}
