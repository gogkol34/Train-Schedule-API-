# schedule.py
import requests
import json
import csv
import sys
import argparse
from datetime import datetime, timedelta
from typing import List, Dict, Optional
import time

CACHE = {}
CACHE_TTL = 60  # seconds

class TrainSchedule:
    def __init__(self):
        self.api_url = "https://transport.opendata.ch/v1/connections"

    def _get_cache_key(self, from_station, to_station, date, time):
        return f"{from_station}:{to_station}:{date}:{time}"

    def fetch_connections(self, from_station: str, to_station: str,
                         date: str = None, time: str = None) -> List[Dict]:
        if date is None:
            date = datetime.now().strftime("%Y-%m-%d")
        if time is None:
            time = datetime.now().strftime("%H:%M")
        cache_key = self._get_cache_key(from_station, to_station, date, time)
        if cache_key in CACHE:
            cached, timestamp = CACHE[cache_key]
            if (datetime.now() - timestamp).seconds < CACHE_TTL:
                return cached
        params = {
            "from": from_station,
            "to": to_station,
            "date": date,
            "time": time
        }
        try:
            response = requests.get(self.api_url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            connections = data.get("connections", [])
            CACHE[cache_key] = (connections, datetime.now())
            return connections
        except Exception as e:
            print(f"Error fetching data: {e}", file=sys.stderr)
            return []

    def format_connection(self, conn: Dict) -> Dict:
        departure = conn.get("from", {})
        arrival = conn.get("to", {})
        duration = conn.get("duration", "")
        changes = conn.get("transfers", 0)
        return {
            "departure": departure.get("departure", ""),
            "departure_station": departure.get("station", {}).get("name", ""),
            "arrival": arrival.get("arrival", ""),
            "arrival_station": arrival.get("station", {}).get("name", ""),
            "duration": duration,
            "changes": changes
        }

    def display(self, connections: List[Dict], limit: int = 10, sort_by: str = "departure"):
        if not connections:
            print("No connections found.")
            return
        formatted = [self.format_connection(c) for c in connections]
        if sort_by == "departure":
            formatted.sort(key=lambda x: x["departure"])
        elif sort_by == "duration":
            formatted.sort(key=lambda x: x["duration"])
        elif sort_by == "changes":
            formatted.sort(key=lambda x: x["changes"])
        else:
            formatted.sort(key=lambda x: x["departure"])
        print(f"\nFound {len(formatted)} connections.")
        print("-" * 80)
        print(f"{'#':<3} {'Departure':<20} {'Arrival':<20} {'Duration':<10} {'Changes':<8}")
        for i, conn in enumerate(formatted[:limit], 1):
            dep_time = conn["departure"][11:16] if conn["departure"] else "?"
            arr_time = conn["arrival"][11:16] if conn["arrival"] else "?"
            dep_st = conn["departure_station"][:10]
            arr_st = conn["arrival_station"][:10]
            print(f"{i:<3} {dep_time} {dep_st:<10} {arr_time} {arr_st:<10} {conn['duration']:<10} {conn['changes']:<8}")
        if len(formatted) > limit:
            print(f"... and {len(formatted)-limit} more")

    def export_json(self, connections: List[Dict], filename: str = "schedule.json"):
        with open(filename, "w", encoding="utf-8") as f:
            json.dump(connections, f, indent=2, ensure_ascii=False)
        print(f"Exported to {filename}")

    def export_csv(self, connections: List[Dict], filename: str = "schedule.csv"):
        with open(filename, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["Departure", "Departure Station", "Arrival", "Arrival Station", "Duration", "Changes"])
            for conn in connections:
                f_conn = self.format_connection(conn)
                writer.writerow([
                    f_conn["departure"],
                    f_conn["departure_station"],
                    f_conn["arrival"],
                    f_conn["arrival_station"],
                    f_conn["duration"],
                    f_conn["changes"]
                ])
        print(f"Exported to {filename}")

def interactive():
    schedule = TrainSchedule()
    print("=== Train Schedule ===")
    from_station = input("From station: ").strip()
    if not from_station:
        print("Station required.")
        return
    to_station = input("To station: ").strip()
    if not to_station:
        print("Station required.")
        return
    date = input("Date (YYYY-MM-DD, leave blank for today): ").strip()
    if not date:
        date = datetime.now().strftime("%Y-%m-%d")
    time_str = input("Time (HH:MM, leave blank for now): ").strip()
    if not time_str:
        time_str = datetime.now().strftime("%H:%M")
    conns = schedule.fetch_connections(from_station, to_station, date, time_str)
    schedule.display(conns)
    if conns:
        export = input("\nExport results? (y/n): ").strip().lower()
        if export == "y":
            fmt = input("Format (json/csv): ").strip().lower()
            fname = input("Filename (default: schedule.{}): ".format(fmt)).strip()
            if not fname:
                fname = f"schedule.{fmt}"
            if fmt == "json":
                schedule.export_json(conns, fname)
            elif fmt == "csv":
                schedule.export_csv(conns, fname)
            else:
                print("Unknown format.")

def cli():
    parser = argparse.ArgumentParser(description="Train Schedule CLI")
    parser.add_argument("--from", dest="from_station", required=True, help="Departure station")
    parser.add_argument("--to", dest="to_station", required=True, help="Destination station")
    parser.add_argument("--date", help="Departure date (YYYY-MM-DD)")
    parser.add_argument("--time", help="Departure time (HH:MM)")
    parser.add_argument("--limit", type=int, default=10, help="Max connections to display")
    parser.add_argument("--sort", default="departure", choices=["departure", "duration", "changes"], help="Sort field")
    parser.add_argument("--export", choices=["json", "csv"], help="Export format")
    parser.add_argument("--output", help="Export filename")
    args = parser.parse_args()

    schedule = TrainSchedule()
    conns = schedule.fetch_connections(args.from_station, args.to_station, args.date, args.time)
    schedule.display(conns, limit=args.limit, sort_by=args.sort)
    if args.export and conns:
        fname = args.output or f"schedule.{args.export}"
        if args.export == "json":
            schedule.export_json(conns, fname)
        elif args.export == "csv":
            schedule.export_csv(conns, fname)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        cli()
    else:
        interactive()
