// Schedule.cs
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using System.IO;
using System.Linq;

namespace TrainSchedule
{
    class Connection
    {
        public FromTo from { get; set; }
        public FromTo to { get; set; }
        public string duration { get; set; }
        public int transfers { get; set; }
    }

    class FromTo
    {
        public string departure { get; set; }
        public string arrival { get; set; }
        public Station station { get; set; }
    }

    class Station
    {
        public string name { get; set; }
    }

    class Response
    {
        public List<Connection> connections { get; set; }
    }

    class Program
    {
        private static readonly HttpClient client = new HttpClient();
        private static readonly Dictionary<string, (List<Connection> data, DateTime timestamp)> cache = new Dictionary<string, (List<Connection>, DateTime)>();
        private const int CacheTTL = 60;

        static async Task<List<Connection>> FetchConnections(string from, string to, string date, string time)
        {
            string key = $"{from}:{to}:{date}:{time}";
            if (cache.TryGetValue(key, out var entry))
            {
                if ((DateTime.Now - entry.timestamp).TotalSeconds < CacheTTL)
                    return entry.data;
            }
            string url = "https://transport.opendata.ch/v1/connections";
            var query = System.Web.HttpUtility.ParseQueryString(string.Empty);
            query["from"] = from;
            query["to"] = to;
            if (!string.IsNullOrEmpty(date)) query["date"] = date;
            if (!string.IsNullOrEmpty(time)) query["time"] = time;
            string fullUrl = url + "?" + query.ToString();
            try
            {
                var response = await client.GetStringAsync(fullUrl);
                var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
                var data = JsonSerializer.Deserialize<Response>(response, options);
                var connections = data?.connections ?? new List<Connection>();
                cache[key] = (connections, DateTime.Now);
                return connections;
            }
            catch (Exception e)
            {
                Console.WriteLine($"Error: {e.Message}");
                return new List<Connection>();
            }
        }

        static void Display(List<Connection> connections, int limit = 10, string sortBy = "departure")
        {
            if (connections == null || connections.Count == 0)
            {
                Console.WriteLine("No connections found.");
                return;
            }
            IEnumerable<Connection> sorted = connections;
            if (sortBy == "duration")
                sorted = sorted.OrderBy(c => c.duration);
            else if (sortBy == "changes")
                sorted = sorted.OrderBy(c => c.transfers);
            else
                sorted = sorted.OrderBy(c => c.from.departure);
            var list = sorted.ToList();
            Console.WriteLine($"\nFound {list.Count} connections.");
            Console.WriteLine(new string('-', 80));
            Console.WriteLine($"{"#",-3} {"Departure",-20} {"Arrival",-20} {"Duration",-10} {"Changes",-8}");
            for (int i = 0; i < Math.Min(list.Count, limit); i++)
            {
                var c = list[i];
                string depTime = c.from.departure?.Length > 5 ? c.from.departure.Substring(11, 5) : "?";
                string arrTime = c.to.arrival?.Length > 5 ? c.to.arrival.Substring(11, 5) : "?";
                string depSt = c.from.station?.name ?? "";
                string arrSt = c.to.station?.name ?? "";
                Console.WriteLine($"{i+1,-3} {depTime} {depSt,10} {arrTime} {arrSt,10} {c.duration,10} {c.transfers,8}");
            }
            if (list.Count > limit)
                Console.WriteLine($"... and {list.Count - limit} more");
        }

        static void ExportJSON(List<Connection> connections, string filename)
        {
            var options = new JsonSerializerOptions { WriteIndented = true };
            string json = JsonSerializer.Serialize(connections, options);
            File.WriteAllText(filename, json);
            Console.WriteLine($"Exported to {filename}");
        }

        static void ExportCSV(List<Connection> connections, string filename)
        {
            using var writer = new StreamWriter(filename);
            writer.WriteLine("Departure,Departure Station,Arrival,Arrival Station,Duration,Changes");
            foreach (var c in connections)
            {
                writer.WriteLine($"{c.from.departure},\"{c.from.station?.name}\",{c.to.arrival},\"{c.to.station?.name}\",{c.duration},{c.transfers}");
            }
            Console.WriteLine($"Exported to {filename}");
        }

        static async Task Interactive()
        {
            Console.WriteLine("=== Train Schedule ===");
            Console.Write("From station: ");
            string from = Console.ReadLine()?.Trim();
            if (string.IsNullOrEmpty(from)) { Console.WriteLine("Station required."); return; }
            Console.Write("To station: ");
            string to = Console.ReadLine()?.Trim();
            if (string.IsNullOrEmpty(to)) { Console.WriteLine("Station required."); return; }
            Console.Write("Date (YYYY-MM-DD, leave blank for today): ");
            string date = Console.ReadLine()?.Trim();
            if (string.IsNullOrEmpty(date)) date = DateTime.Now.ToString("yyyy-MM-dd");
            Console.Write("Time (HH:MM, leave blank for now): ");
            string time = Console.ReadLine()?.Trim();
            if (string.IsNullOrEmpty(time)) time = DateTime.Now.ToString("HH:mm");
            var conns = await FetchConnections(from, to, date, time);
            Display(conns);
            if (conns.Count > 0)
            {
                Console.Write("\nExport results? (y/n): ");
                string export = Console.ReadLine()?.Trim().ToLower();
                if (export == "y")
                {
                    Console.Write("Format (json/csv): ");
                    string fmt = Console.ReadLine()?.Trim().ToLower();
                    Console.Write("Filename (default: schedule." + fmt + "): ");
                    string fname = Console.ReadLine()?.Trim();
                    if (string.IsNullOrEmpty(fname)) fname = "schedule." + fmt;
                    if (fmt == "json") ExportJSON(conns, fname);
                    else if (fmt == "csv") ExportCSV(conns, fname);
                    else Console.WriteLine("Unknown format.");
                }
            }
        }

        static async Task Main(string[] args)
        {
            if (args.Length > 0)
            {
                // CLI mode - parse arguments
                var dict = new Dictionary<string, string>();
                for (int i = 0; i < args.Length; i++)
                {
                    if (args[i].StartsWith("--"))
                    {
                        string key = args[i].Substring(2);
                        if (i + 1 < args.Length && !args[i + 1].StartsWith("--"))
                            dict[key] = args[++i];
                        else
                            dict[key] = "true";
                    }
                }
                if (!dict.ContainsKey("from") || !dict.ContainsKey("to"))
                {
                    Console.WriteLine("--from and --to are required.");
                    return;
                }
                string from = dict["from"];
                string to = dict["to"];
                string date = dict.ContainsKey("date") ? dict["date"] : null;
                string time = dict.ContainsKey("time") ? dict["time"] : null;
                int limit = dict.ContainsKey("limit") ? int.Parse(dict["limit"]) : 10;
                string sortBy = dict.ContainsKey("sort") ? dict["sort"] : "departure";
                string exportFmt = dict.ContainsKey("export") ? dict["export"] : null;
                string output = dict.ContainsKey("output") ? dict["output"] : null;
                var conns = await FetchConnections(from, to, date, time);
                Display(conns, limit, sortBy);
                if (!string.IsNullOrEmpty(exportFmt) && conns.Count > 0)
                {
                    string fname = output ?? $"schedule.{exportFmt}";
                    if (exportFmt == "json") ExportJSON(conns, fname);
                    else if (exportFmt == "csv") ExportCSV(conns, fname);
                }
            }
            else
            {
                await Interactive();
            }
        }
    }
}
