# schedule.rb
require 'net/http'
require 'json'
require 'csv'
require 'time'
require 'optparse'

$cache = {}
CACHE_TTL = 60

def fetch_connections(from, to, date = nil, time = nil)
  key = "#{from}:#{to}:#{date}:#{time}"
  if $cache.key?(key)
    entry = $cache[key]
    if Time.now - entry[:timestamp] < CACHE_TTL
      return entry[:data]
    end
  end
  uri = URI('https://transport.opendata.ch/v1/connections')
  params = { from: from, to: to }
  params[:date] = date if date
  params[:time] = time if time
  uri.query = URI.encode_www_form(params)
  response = Net::HTTP.get_response(uri)
  if response.is_a?(Net::HTTPSuccess)
    data = JSON.parse(response.body)
    connections = data['connections'] || []
    $cache[key] = { data: connections, timestamp: Time.now }
    connections
  else
    puts "Error: #{response.code}"
    []
  end
rescue => e
  puts "Error: #{e.message}"
  []
end

def format_connection(c)
  {
    departure: c['from']['departure'],
    departure_station: c['from']['station']['name'],
    arrival: c['to']['arrival'],
    arrival_station: c['to']['station']['name'],
    duration: c['duration'],
    changes: c['transfers'] || 0
  }
end

def display(connections, limit = 10, sort_by = 'departure')
  if connections.empty?
    puts 'No connections found.'
    return
  end
  formatted = connections.map { |c| format_connection(c) }
  case sort_by
  when 'duration'
    formatted.sort_by! { |c| c[:duration] }
  when 'changes'
    formatted.sort_by! { |c| c[:changes] }
  else
    formatted.sort_by! { |c| c[:departure] }
  end
  puts "\nFound #{formatted.size} connections."
  puts '-' * 80
  puts "%-3s %-20s %-20s %-10s %-8s" % ['#', 'Departure', 'Arrival', 'Duration', 'Changes']
  formatted.first(limit).each_with_index do |c, i|
    dep_time = c[:departure] ? c[:departure][11..15] : '?'
    arr_time = c[:arrival] ? c[:arrival][11..15] : '?'
    dep_st = c[:departure_station][0..9]
    arr_st = c[:arrival_station][0..9]
    puts "%-3d %s %-10s %s %-10s %-10s %-8d" % [i+1, dep_time, dep_st, arr_time, arr_st, c[:duration], c[:changes]]
  end
  if formatted.size > limit
    puts "... and #{formatted.size - limit} more"
  end
end

def export_json(connections, filename)
  File.write(filename, JSON.pretty_generate(connections))
  puts "Exported to #{filename}"
end

def export_csv(connections, filename)
  CSV.open(filename, 'w') do |csv|
    csv << ['Departure', 'Departure Station', 'Arrival', 'Arrival Station', 'Duration', 'Changes']
    connections.each do |c|
      csv << [c['from']['departure'], c['from']['station']['name'], c['to']['arrival'], c['to']['station']['name'], c['duration'], c['transfers'] || 0]
    end
  end
  puts "Exported to #{filename}"
end

def interactive
  puts "=== Train Schedule ==="
  print "From station: "
  from = gets.chomp.strip
  if from.empty?
    puts "Station required."
    return
  end
  print "To station: "
  to = gets.chomp.strip
  if to.empty?
    puts "Station required."
    return
  end
  print "Date (YYYY-MM-DD, leave blank for today): "
  date = gets.chomp.strip
  date = Time.now.strftime('%Y-%m-%d') if date.empty?
  print "Time (HH:MM, leave blank for now): "
  time = gets.chomp.strip
  time = Time.now.strftime('%H:%M') if time.empty?
  conns = fetch_connections(from, to, date, time)
  display(conns)
  if !conns.empty?
    print "\nExport results? (y/n): "
    export_ans = gets.chomp.strip.downcase
    if export_ans == 'y'
      print "Format (json/csv): "
      fmt = gets.chomp.strip.downcase
      print "Filename (default: schedule.#{fmt}): "
      fname = gets.chomp.strip
      fname = "schedule.#{fmt}" if fname.empty?
      if fmt == 'json'
        export_json(conns, fname)
      elsif fmt == 'csv'
        export_csv(conns, fname)
      else
        puts "Unknown format."
      end
    end
  end
end

def cli
  options = {}
  OptionParser.new do |opts|
    opts.on('--from STATION', 'Departure station') { |v| options[:from] = v }
    opts.on('--to STATION', 'Destination station') { |v| options[:to] = v }
    opts.on('--date DATE', 'Date (YYYY-MM-DD)') { |v| options[:date] = v }
    opts.on('--time TIME', 'Time (HH:MM)') { |v| options[:time] = v }
    opts.on('--limit N', Integer, 'Max connections') { |v| options[:limit] = v }
    opts.on('--sort FIELD', 'Sort field') { |v| options[:sort] = v }
    opts.on('--export FORMAT', 'Export format (json/csv)') { |v| options[:export] = v }
    opts.on('--output FILE', 'Output filename') { |v| options[:output] = v }
  end.parse!
  if options[:from].nil? || options[:to].nil?
    puts "--from and --to are required."
    exit 1
  end
  conns = fetch_connections(options[:from], options[:to], options[:date], options[:time])
  display(conns, options[:limit] || 10, options[:sort] || 'departure')
  if options[:export] && !conns.empty?
    fname = options[:output] || "schedule.#{options[:export]}"
    if options[:export] == 'json'
      export_json(conns, fname)
    elsif options[:export] == 'csv'
      export_csv(conns, fname)
    end
  end
end

if ARGV.empty?
  interactive
else
  cli
end
