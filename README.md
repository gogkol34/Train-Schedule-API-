🚂 Train Schedule (API) – Multi‑Language Edition

A command‑line tool that fetches **real‑time train schedules** from the public [Open Transport API](https://transport.opendata.ch/) and displays them in a clean, formatted table.  
Supports caching, filtering, sorting, and export to JSON/CSV.  
Built in **7 programming languages** – perfect for learning API integration, data parsing, or building travel apps.

## ✨ Features
- **Search connections** – get all trains between two stations (e.g., `Bern` → `Zürich`).
- **Date/time selection** – specify departure date and time (default: now).
- **Caching** – stores results for 60 seconds to reduce API calls.
- **Filtering** – hide connections with too many changes or too long duration.
- **Sorting** – sort by departure time, duration, or number of changes.
- **Export** – save results to JSON or CSV file.
- **Interactive mode** – step‑by‑step prompts for stations and options.
- **Command‑line mode** – pass arguments directly for scripting.

## 🗂 Languages & Files
| Language          | File               |
|-------------------|--------------------|
| Python            | `schedule.py`      |
| Go                | `schedule.go`      |
| JavaScript (Node) | `schedule.js`      |
| C#                | `Schedule.cs`      |
| Java              | `Schedule.java`    |
| Ruby              | `schedule.rb`      |
| Swift             | `schedule.swift`   |

## 🚀 How to Run
Each file is standalone – run it with the appropriate interpreter/compiler.  
All versions use the same API endpoint `https://transport.opendata.ch/v1/connections`.

| Language | Command (interactive) | Command (CLI) |
|----------|----------------------|---------------|
| Python   | `python schedule.py` | `python schedule.py --from Bern --to Zürich` |
| Go       | `go run schedule.go` | `go run schedule.go -from Bern -to Zürich` |
| JavaScript | `node schedule.js` | `node schedule.js --from Bern --to Zürich` |
| C#       | `dotnet run` | `dotnet run -- --from Bern --to Zürich` |
| Java     | `java Schedule` | `java Schedule --from Bern --to Zürich` |
| Ruby     | `ruby schedule.rb` | `ruby schedule.rb --from Bern --to Zürich` |
| Swift    | `swift schedule.swift` | `swift schedule.swift --from Bern --to Zürich` |

## 📊 Example Session (Interactive)
=== Train Schedule ===
From station: Bern
To station: Zürich
Date (YYYY-MM-DD, leave blank for today):
Time (HH:MM, leave blank for now):
Fetching connections...
Found 12 connections.

Departure Arrival Duration Changes
1 14:32 Bern 15:46 Zürich 1h14m 0
2 15:02 Bern 16:18 Zürich 1h16m 0
...

Export results? (y/n): y
Format (json/csv): json
Filename (default: schedule.json):
Exported to schedule.json

text

## 🔧 Command‑Line Options (Common)
| Option | Description |
|--------|-------------|
| `--from` | Departure station |
| `--to` | Destination station |
| `--date` | Departure date (YYYY‑MM‑DD) |
| `--time` | Departure time (HH:MM) |
| `--limit` | Max connections to display (default 10) |
| `--sort` | Sort field: `departure`, `duration`, `changes` |
| `--export` | Export to file (e.g., `--export json`) |

## 📁 Export Formats
- **JSON** – full connection data with all fields.
- **CSV** – simple table view.

## 🤝 Contributing
Add more API endpoints (e.g., station search, real‑time delays) – PRs welcome!

## 📜 License
MIT – use freely.
