// Schedule.java
import java.io.*;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;
import com.google.gson.*;

public class Schedule {
    private static final String API_URL = "https://transport.opendata.ch/v1/connections";
    private static final int CACHE_TTL = 60;
    private static final Map<String, CachedData> cache = new HashMap<>();

    static class CachedData {
        List<Connection> data;
        long timestamp;
        CachedData(List<Connection> d, long ts) { data = d; timestamp = ts; }
    }

    static class Connection {
        FromTo from;
        FromTo to;
        String duration;
        int transfers;
    }

    static class FromTo {
        String departure;
        String arrival;
        Station station;
    }

    static class Station {
        String name;
    }

    static class Response {
        List<Connection> connections;
    }

    private static List<Connection> fetchConnections(String from, String to, String date, String time) throws Exception {
        String key = String.format("%s:%s:%s:%s", from, to, date, time);
        CachedData cached = cache.get(key);
        if (cached != null) {
            if ((System.currentTimeMillis() - cached.timestamp) / 1000 < CACHE_TTL) {
                return cached.data;
            }
        }
        StringBuilder urlBuilder = new StringBuilder(API_URL);
        urlBuilder.append("?from=").append(URLEncoder.encode(from, "UTF-8"));
        urlBuilder.append("&to=").append(URLEncoder.encode(to, "UTF-8"));
        if (date != null && !date.isEmpty()) urlBuilder.append("&date=").append(URLEncoder.encode(date, "UTF-8"));
        if (time != null && !time.isEmpty()) urlBuilder.append("&time=").append(URLEncoder.encode(time, "UTF-8"));
        URL url = new URL(urlBuilder.toString());
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        conn.setConnectTimeout(5000);
        conn.setReadTimeout(5000);
        if (conn.getResponseCode() != 200) {
            throw new RuntimeException("HTTP error: " + conn.getResponseCode());
        }
        try (BufferedReader br = new BufferedReader(new InputStreamReader(conn.getInputStream()))) {
            String json = br.lines().collect(Collectors.joining());
            Gson gson = new Gson();
            Response resp = gson.fromJson(json, Response.class);
            List<Connection> connections = resp.connections != null ? resp.connections : new ArrayList<>();
            cache.put(key, new CachedData(connections, System.currentTimeMillis()));
            return connections;
        }
    }

    private static void display(List<Connection> connections, int limit, String sortBy) {
        if (connections == null || connections.isEmpty()) {
            System.out.println("No connections found.");
            return;
        }
        List<Connection> sorted = new ArrayList<>(connections);
        if ("duration".equals(sortBy)) {
            sorted.sort(Comparator.comparing(c -> c.duration));
        } else if ("changes".equals(sortBy)) {
            sorted.sort(Comparator.comparingInt(c -> c.transfers));
        } else {
            sorted.sort(Comparator.comparing(c -> c.from.departure));
        }
        System.out.printf("%nFound %d connections.%n", sorted.size());
        System.out.println(new String(new char[80]).replace('\0', '-'));
        System.out.printf("%-3s %-20s %-20s %-10s %-8s%n", "#", "Departure", "Arrival", "Duration", "Changes");
        for (int i = 0; i < Math.min(sorted.size(), limit); i++) {
            Connection c = sorted.get(i);
            String depTime = c.from.departure != null && c.from.departure.length() > 5 ? c.from.departure.substring(11, 16) : "?";
            String arrTime = c.to.arrival != null && c.to.arrival.length() > 5 ? c.to.arrival.substring(11, 16) : "?";
            String depSt = c.from.station != null ? c.from.station.name : "";
            String arrSt = c.to.station != null ? c.to.station.name : "";
            System.out.printf("%-3d %s %-10s %s %-10s %-10s %-8d%n",
                i+1, depTime, depSt, arrTime, arrSt, c.duration, c.transfers);
        }
        if (sorted.size() > limit) {
            System.out.printf("... and %d more%n", sorted.size() - limit);
        }
    }

    private static void exportJSON(List<Connection> connections, String filename) throws IOException {
        Gson gson = new GsonBuilder().setPrettyPrinting().create();
        String json = gson.toJson(connections);
        try (FileWriter fw = new FileWriter(filename)) {
            fw.write(json);
        }
        System.out.println("Exported to " + filename);
    }

    private static void exportCSV(List<Connection> connections, String filename) throws IOException {
        try (PrintWriter pw = new PrintWriter(filename)) {
            pw.println("Departure,Departure Station,Arrival,Arrival Station,Duration,Changes");
            for (Connection c : connections) {
                pw.printf("%s,\"%s\",%s,\"%s\",%s,%d%n",
                    c.from.departure, c.from.station.name,
                    c.to.arrival, c.to.station.name,
                    c.duration, c.transfers);
            }
        }
        System.out.println("Exported to " + filename);
    }

    private static void interactive() throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        System.out.println("=== Train Schedule ===");
        System.out.print("From station: ");
        String from = reader.readLine().trim();
        if (from.isEmpty()) { System.out.println("Station required."); return; }
        System.out.print("To station: ");
        String to = reader.readLine().trim();
        if (to.isEmpty()) { System.out.println("Station required."); return; }
        System.out.print("Date (YYYY-MM-DD, leave blank for today): ");
        String date = reader.readLine().trim();
        if (date.isEmpty()) date = LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE);
        System.out.print("Time (HH:MM, leave blank for now): ");
        String time = reader.readLine().trim();
        if (time.isEmpty()) time = LocalDateTime.now().format(DateTimeFormatter.ofPattern("HH:mm"));
        List<Connection> conns = fetchConnections(from, to, date, time);
        display(conns, 10, "departure");
        if (!conns.isEmpty()) {
            System.out.print("\nExport results? (y/n): ");
            String exp = reader.readLine().trim().toLowerCase();
            if (exp.equals("y")) {
                System.out.print("Format (json/csv): ");
                String fmt = reader.readLine().trim().toLowerCase();
                System.out.print("Filename (default: schedule." + fmt + "): ");
                String fname = reader.readLine().trim();
                if (fname.isEmpty()) fname = "schedule." + fmt;
                if (fmt.equals("json")) exportJSON(conns, fname);
                else if (fmt.equals("csv")) exportCSV(conns, fname);
                else System.out.println("Unknown format.");
            }
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length > 0) {
            Map<String, String> params = new HashMap<>();
            for (int i = 0; i < args.length; i++) {
                if (args[i].startsWith("--")) {
                    String key = args[i].substring(2);
                    if (i + 1 < args.length && !args[i+1].startsWith("--")) {
                        params.put(key, args[++i]);
                    } else {
                        params.put(key, "true");
                    }
                }
            }
            if (!params.containsKey("from") || !params.containsKey("to")) {
                System.err.println("--from and --to are required.");
                return;
            }
            String from = params.get("from");
            String to = params.get("to");
            String date = params.getOrDefault("date", null);
            String time = params.getOrDefault("time", null);
            int limit = Integer.parseInt(params.getOrDefault("limit", "10"));
            String sortBy = params.getOrDefault("sort", "departure");
            String exportFmt = params.getOrDefault("export", null);
            String output = params.getOrDefault("output", null);
            List<Connection> conns = fetchConnections(from, to, date, time);
            display(conns, limit, sortBy);
            if (exportFmt != null && !conns.isEmpty()) {
                String fname = output != null ? output : "schedule." + exportFmt;
                if (exportFmt.equals("json")) exportJSON(conns, fname);
                else if (exportFmt.equals("csv")) exportCSV(conns, fname);
            }
        } else {
            interactive();
        }
    }
}
