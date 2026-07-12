// schedule.go
package main

import (
	"bufio"
	"encoding/csv"
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

type Connection struct {
	From      FromTo   `json:"from"`
	To        FromTo   `json:"to"`
	Duration  string   `json:"duration"`
	Transfers int      `json:"transfers"`
}

type FromTo struct {
	Departure string `json:"departure"`
	Arrival   string `json:"arrival"`
	Station   struct {
		Name string `json:"name"`
	} `json:"station"`
}

type ConnectionsResponse struct {
	Connections []Connection `json:"connections"`
}

var cache = make(map[string]struct {
	Data      []Connection
	Timestamp time.Time
})
const cacheTTL = 60 * time.Second

func fetchConnections(from, to, date, timeStr string) ([]Connection, error) {
	key := fmt.Sprintf("%s:%s:%s:%s", from, to, date, timeStr)
	if entry, ok := cache[key]; ok {
		if time.Since(entry.Timestamp) < cacheTTL {
			return entry.Data, nil
		}
	}
	apiURL := "https://transport.opendata.ch/v1/connections"
	params := url.Values{}
	params.Set("from", from)
	params.Set("to", to)
	if date != "" {
		params.Set("date", date)
	}
	if timeStr != "" {
		params.Set("time", timeStr)
	}
	fullURL := apiURL + "?" + params.Encode()
	resp, err := http.Get(fullURL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	var data ConnectionsResponse
	if err := json.Unmarshal(body, &data); err != nil {
		return nil, err
	}
	cache[key] = struct {
		Data      []Connection
		Timestamp time.Time
	}{Data: data.Connections, Timestamp: time.Now()}
	return data.Connections, nil
}

func display(conns []Connection, limit int, sortBy string) {
	if len(conns) == 0 {
		fmt.Println("No connections found.")
		return
	}
	// format and sort
	type displayConn struct {
		DepTime      string
		DepStation   string
		ArrTime      string
		ArrStation   string
		Duration     string
		Changes      int
	}
	var list []displayConn
	for _, c := range conns {
		depTime := ""
		if len(c.From.Departure) > 5 {
			depTime = c.From.Departure[11:16]
		}
		arrTime := ""
		if len(c.To.Arrival) > 5 {
			arrTime = c.To.Arrival[11:16]
		}
		list = append(list, displayConn{
			DepTime:    depTime,
			DepStation: c.From.Station.Name,
			ArrTime:    arrTime,
			ArrStation: c.To.Station.Name,
			Duration:   c.Duration,
			Changes:    c.Transfers,
		})
	}
	switch sortBy {
	case "departure":
		sort.Slice(list, func(i, j int) bool { return list[i].DepTime < list[j].DepTime })
	case "duration":
		sort.Slice(list, func(i, j int) bool { return list[i].Duration < list[j].Duration })
	case "changes":
		sort.Slice(list, func(i, j int) bool { return list[i].Changes < list[j].Changes })
	default:
		sort.Slice(list, func(i, j int) bool { return list[i].DepTime < list[j].DepTime })
	}
	fmt.Printf("\nFound %d connections.\n", len(list))
	fmt.Printf("%-3s %-20s %-20s %-10s %-8s\n", "#", "Departure", "Arrival", "Duration", "Changes")
	for i, c := range list {
		if i >= limit {
			fmt.Printf("... and %d more\n", len(list)-limit)
			break
		}
		depStr := fmt.Sprintf("%s %s", c.DepTime, truncate(c.DepStation, 10))
		arrStr := fmt.Sprintf("%s %s", c.ArrTime, truncate(c.ArrStation, 10))
		fmt.Printf("%-3d %-20s %-20s %-10s %-8d\n", i+1, depStr, arrStr, c.Duration, c.Changes)
	}
}

func truncate(s string, max int) string {
	if len(s) > max {
		return s[:max]
	}
	return s
}

func exportJSON(conns []Connection, filename string) {
	data, _ := json.MarshalIndent(conns, "", "  ")
	ioutil.WriteFile(filename, data, 0644)
	fmt.Printf("Exported to %s\n", filename)
}

func exportCSV(conns []Connection, filename string) {
	file, _ := os.Create(filename)
	defer file.Close()
	writer := csv.NewWriter(file)
	defer writer.Flush()
	writer.Write([]string{"Departure", "Departure Station", "Arrival", "Arrival Station", "Duration", "Changes"})
	for _, c := range conns {
		writer.Write([]string{
			c.From.Departure,
			c.From.Station.Name,
			c.To.Arrival,
			c.To.Station.Name,
			c.Duration,
			strconv.Itoa(c.Transfers),
		})
	}
	fmt.Printf("Exported to %s\n", filename)
}

func interactive() {
	reader := bufio.NewReader(os.Stdin)
	fmt.Println("=== Train Schedule ===")
	fmt.Print("From station: ")
	from, _ := reader.ReadString('\n')
	from = strings.TrimSpace(from)
	fmt.Print("To station: ")
	to, _ := reader.ReadString('\n')
	to = strings.TrimSpace(to)
	if from == "" || to == "" {
		fmt.Println("Stations required.")
		return
	}
	fmt.Print("Date (YYYY-MM-DD, leave blank for today): ")
	date, _ := reader.ReadString('\n')
	date = strings.TrimSpace(date)
	fmt.Print("Time (HH:MM, leave blank for now): ")
	timeStr, _ := reader.ReadString('\n')
	timeStr = strings.TrimSpace(timeStr)
	conns, err := fetchConnections(from, to, date, timeStr)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	display(conns, 10, "departure")
	if len(conns) > 0 {
		fmt.Print("\nExport results? (y/n): ")
		export, _ := reader.ReadString('\n')
		export = strings.TrimSpace(strings.ToLower(export))
		if export == "y" {
			fmt.Print("Format (json/csv): ")
			fmtF, _ := reader.ReadString('\n')
			fmtF = strings.TrimSpace(strings.ToLower(fmtF))
			fmt.Print("Filename (default: schedule." + fmtF + "): ")
			fname, _ := reader.ReadString('\n')
			fname = strings.TrimSpace(fname)
			if fname == "" {
				fname = "schedule." + fmtF
			}
			if fmtF == "json" {
				exportJSON(conns, fname)
			} else if fmtF == "csv" {
				exportCSV(conns, fname)
			} else {
				fmt.Println("Unknown format.")
			}
		}
	}
}

func cli() {
	from := flag.String("from", "", "Departure station")
	to := flag.String("to", "", "Destination station")
	date := flag.String("date", "", "Departure date (YYYY-MM-DD)")
	timeStr := flag.String("time", "", "Departure time (HH:MM)")
	limit := flag.Int("limit", 10, "Max connections")
	sortBy := flag.String("sort", "departure", "Sort field: departure, duration, changes")
	exportFmt := flag.String("export", "", "Export format: json or csv")
	output := flag.String("output", "", "Export filename")
	flag.Parse()
	if *from == "" || *to == "" {
		fmt.Println("--from and --to are required.")
		flag.Usage()
		return
	}
	conns, err := fetchConnections(*from, *to, *date, *timeStr)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	display(conns, *limit, *sortBy)
	if *exportFmt != "" && len(conns) > 0 {
		fname := *output
		if fname == "" {
			fname = "schedule." + *exportFmt
		}
		if *exportFmt == "json" {
			exportJSON(conns, fname)
		} else if *exportFmt == "csv" {
			exportCSV(conns, fname)
		}
	}
}

func main() {
	if len(os.Args) > 1 {
		cli()
	} else {
		interactive()
	}
}
