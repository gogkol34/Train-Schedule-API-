// schedule.swift
import Foundation

struct Connection: Codable {
    let from: FromTo
    let to: FromTo
    let duration: String
    let transfers: Int
}

struct FromTo: Codable {
    let departure: String
    let arrival: String
    let station: Station
}

struct Station: Codable {
    let name: String
}

struct Response: Codable {
    let connections: [Connection]?
}

var cache: [String: (data: [Connection], timestamp: TimeInterval)] = [:]
let cacheTTL: TimeInterval = 60

func fetchConnections(from: String, to: String, date: String?, time: String?) -> [Connection] {
    let key = "\(from):\(to):\(date ?? ""):\(time ?? "")"
    if let entry = cache[key] {
        if Date().timeIntervalSince1970 - entry.timestamp < cacheTTL {
            return entry.data
        }
    }
    var components = URLComponents(string: "https://transport.opendata.ch/v1/connections")!
    var queryItems = [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)]
    if let d = date { queryItems.append(URLQueryItem(name: "date", value: d)) }
    if let t = time { queryItems.append(URLQueryItem(name: "time", value: t)) }
    components.queryItems = queryItems
    guard let url = components.url else { return [] }
    let semaphore = DispatchSemaphore(value: 0)
    var result: [Connection] = []
    var error: Error? = nil
    let task = URLSession.shared.dataTask(with: url) { data, _, err in
        defer { semaphore.signal() }
        if let err = err { error = err; return }
        guard let data = data else { return }
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(Response.self, from: data)
            result = response.connections ?? []
            cache[key] = (result, Date().timeIntervalSince1970)
        } catch {
            error = error
        }
    }
    task.resume()
    semaphore.wait()
    if let err = error {
        print("Error: \(err)")
        return []
    }
    return result
}

func display(connections: [Connection], limit: Int = 10, sortBy: String = "departure") {
    if connections.isEmpty {
        print("No connections found.")
        return
    }
    var sorted = connections
    switch sortBy {
    case "duration":
        sorted.sort { $0.duration < $1.duration }
    case "changes":
        sorted.sort { $0.transfers < $1.transfers }
    default:
        sorted.sort { $0.from.departure < $1.from.departure }
    }
    print("\nFound \(sorted.count) connections.")
    print(String(repeating: "-", count: 80))
    print(String(format: "%-3s %-20s %-20s %-10s %-8s", "#", "Departure", "Arrival", "Duration", "Changes"))
    for (i, c) in sorted.enumerated() {
        if i >= limit {
            print("... and \(sorted.count - limit) more")
            break
        }
        let depTime = c.from.departure.count > 5 ? String(c.from.departure.suffix(5)) : "?"
        let arrTime = c.to.arrival.count > 5 ? String(c.to.arrival.suffix(5)) : "?"
        let depSt = c.from.station.name.prefix(10)
        let arrSt = c.to.station.name.prefix(10)
        print(String(format: "%-3d %@ %@ %@ %@ %@ %-8d", i+1, depTime, depSt, arrTime, arrSt, c.duration, c.transfers))
    }
}

func exportJSON(connections: [Connection], filename: String) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    do {
        let data = try encoder.encode(connections)
        try data.write(to: URL(fileURLWithPath: filename))
        print("Exported to \(filename)")
    } catch {
        print("Export failed: \(error)")
    }
}

func exportCSV(connections: [Connection], filename: String) {
    var lines = ["Departure,Departure Station,Arrival,Arrival Station,Duration,Changes"]
    for c in connections {
        lines.append("\(c.from.departure),\"\(c.from.station.name)\",\(c.to.arrival),\"\(c.to.station.name)\",\(c.duration),\(c.transfers)")
    }
    do {
        try lines.joined(separator: "\n").write(toFile: filename, atomically: true, encoding: .utf8)
        print("Exported to \(filename)")
    } catch {
        print("Export failed: \(error)")
    }
}

func interactive() {
    print("=== Train Schedule ===")
    print("From station: ", terminator: "")
    guard let from = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !from.isEmpty else {
        print("Station required.")
        return
    }
    print("To station: ", terminator: "")
    guard let to = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !to.isEmpty else {
        print("Station required.")
        return
    }
    print("Date (YYYY-MM-DD, leave blank for today): ", terminator: "")
    var date = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
    if date?.isEmpty ?? true { date = nil }
    print("Time (HH:MM, leave blank for now): ", terminator: "")
    var time = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
    if time?.isEmpty ?? true { time = nil }
    let conns = fetchConnections(from: from, to: to, date: date, time: time)
    display(connections: conns)
    if !conns.isEmpty {
        print("\nExport results? (y/n): ", terminator: "")
        guard let exportAns = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return }
        if exportAns == "y" {
            print("Format (json/csv): ", terminator: "")
            guard let fmt = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return }
            print("Filename (default: schedule.\(fmt)): ", terminator: "")
            var fname = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
            if fname?.isEmpty ?? true { fname = "schedule.\(fmt)" }
            if fmt == "json" {
                exportJSON(connections: conns, filename: fname!)
            } else if fmt == "csv" {
                exportCSV(connections: conns, filename: fname!)
            } else {
                print("Unknown format.")
            }
        }
    }
}

func cli() {
    let args = CommandLine.arguments.dropFirst()
    var params: [String: String] = [:]
    var i = 0
    while i < args.count {
        let arg = args[i]
        if arg.hasPrefix("--") {
            let key = String(arg.dropFirst(2))
            if i + 1 < args.count && !args[i+1].hasPrefix("--") {
                params[key] = args[i+1]
                i += 2
            } else {
                params[key] = "true"
                i += 1
            }
        } else {
            i += 1
        }
    }
    guard let from = params["from"], let to = params["to"] else {
        print("--from and --to are required.")
        return
    }
    let date = params["date"]
    let time = params["time"]
    let limit = Int(params["limit"] ?? "10") ?? 10
    let sortBy = params["sort"] ?? "departure"
    let exportFmt = params["export"]
    let output = params["output"]
    let conns = fetchConnections(from: from, to: to, date: date, time: time)
    display(connections: conns, limit: limit, sortBy: sortBy)
    if let expFmt = exportFmt, !conns.isEmpty {
        let fname = output ?? "schedule.\(expFmt)"
        if expFmt == "json" {
            exportJSON(connections: conns, filename: fname)
        } else if expFmt == "csv" {
            exportCSV(connections: conns, filename: fname)
        }
    }
}

if CommandLine.arguments.count > 1 {
    cli()
} else {
    interactive()
}
