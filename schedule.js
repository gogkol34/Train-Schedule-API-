// schedule.js
const axios = require('axios');
const fs = require('fs');
const readline = require('readline');

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});

let cache = {};
const CACHE_TTL = 60;

async function fetchConnections(from, to, date, time) {
    const key = `${from}:${to}:${date}:${time}`;
    if (cache[key]) {
        const entry = cache[key];
        if ((Date.now() - entry.timestamp) / 1000 < CACHE_TTL) {
            return entry.data;
        }
    }
    const url = 'https://transport.opendata.ch/v1/connections';
    const params = { from, to };
    if (date) params.date = date;
    if (time) params.time = time;
    try {
        const response = await axios.get(url, { params, timeout: 10000 });
        const data = response.data.connections || [];
        cache[key] = { data, timestamp: Date.now() };
        return data;
    } catch (e) {
        console.error('Error fetching data:', e.message);
        return [];
    }
}

function formatConnection(c) {
    return {
        departure: c.from.departure || '',
        departureStation: c.from.station.name || '',
        arrival: c.to.arrival || '',
        arrivalStation: c.to.station.name || '',
        duration: c.duration || '',
        changes: c.transfers || 0
    };
}

function display(connections, limit = 10, sortBy = 'departure') {
    if (!connections || !connections.length) {
        console.log('No connections found.');
        return;
    }
    let formatted = connections.map(c => formatConnection(c));
    if (sortBy === 'departure') {
        formatted.sort((a, b) => a.departure.localeCompare(b.departure));
    } else if (sortBy === 'duration') {
        formatted.sort((a, b) => a.duration.localeCompare(b.duration));
    } else if (sortBy === 'changes') {
        formatted.sort((a, b) => a.changes - b.changes);
    }
    console.log(`\nFound ${formatted.length} connections.`);
    console.log('-'.repeat(80));
    console.log(`${'#'.padEnd(3)} ${'Departure'.padEnd(20)} ${'Arrival'.padEnd(20)} ${'Duration'.padEnd(10)} ${'Changes'.padEnd(8)}`);
    for (let i = 0; i < Math.min(formatted.length, limit); i++) {
        const c = formatted[i];
        const depTime = c.departure ? c.departure.slice(11, 16) : '?';
        const arrTime = c.arrival ? c.arrival.slice(11, 16) : '?';
        const depSt = c.departureStation.slice(0, 10);
        const arrSt = c.arrivalStation.slice(0, 10);
        console.log(`${String(i+1).padEnd(3)} ${depTime} ${depSt.padEnd(10)} ${arrTime} ${arrSt.padEnd(10)} ${c.duration.padEnd(10)} ${c.changes}`);
    }
    if (formatted.length > limit) {
        console.log(`... and ${formatted.length - limit} more`);
    }
}

function exportJSON(connections, filename) {
    fs.writeFileSync(filename, JSON.stringify(connections, null, 2));
    console.log(`Exported to ${filename}`);
}

function exportCSV(connections, filename) {
    const lines = ['Departure,Departure Station,Arrival,Arrival Station,Duration,Changes'];
    connections.forEach(c => {
        const f = formatConnection(c);
        lines.push(`${f.departure},"${f.departureStation}",${f.arrival},"${f.arrivalStation}",${f.duration},${f.changes}`);
    });
    fs.writeFileSync(filename, lines.join('\n'));
    console.log(`Exported to ${filename}`);
}

function ask(question) {
    return new Promise(resolve => rl.question(question, resolve));
}

async function interactive() {
    console.log('=== Train Schedule ===');
    const from = await ask('From station: ');
    if (!from.trim()) { console.log('Station required.'); rl.close(); return; }
    const to = await ask('To station: ');
    if (!to.trim()) { console.log('Station required.'); rl.close(); return; }
    let date = await ask('Date (YYYY-MM-DD, leave blank for today): ');
    if (!date.trim()) date = new Date().toISOString().slice(0,10);
    let time = await ask('Time (HH:MM, leave blank for now): ');
    if (!time.trim()) time = new Date().toTimeString().slice(0,5);
    const conns = await fetchConnections(from.trim(), to.trim(), date.trim(), time.trim());
    display(conns);
    if (conns.length) {
        const exportAns = await ask('\nExport results? (y/n): ');
        if (exportAns.toLowerCase() === 'y') {
            const fmt = await ask('Format (json/csv): ');
            let fname = await ask('Filename (default: schedule.' + fmt + '): ');
            if (!fname.trim()) fname = 'schedule.' + fmt;
            if (fmt === 'json') exportJSON(conns, fname);
            else if (fmt === 'csv') exportCSV(conns, fname);
            else console.log('Unknown format.');
        }
    }
    rl.close();
}

function cli() {
    const args = require('minimist')(process.argv.slice(2));
    if (!args.from || !args.to) {
        console.error('--from and --to are required.');
        process.exit(1);
    }
    const from = args.from;
    const to = args.to;
    const date = args.date || '';
    const time = args.time || '';
    const limit = args.limit || 10;
    const sortBy = args.sort || 'departure';
    fetchConnections(from, to, date, time).then(conns => {
        display(conns, limit, sortBy);
        if (args.export && conns.length) {
            const fname = args.output || `schedule.${args.export}`;
            if (args.export === 'json') exportJSON(conns, fname);
            else if (args.export === 'csv') exportCSV(conns, fname);
        }
    });
}

if (process.argv.length > 2) {
    cli();
} else {
    interactive();
}
