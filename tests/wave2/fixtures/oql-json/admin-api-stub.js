// Stub of the Mendix admin API's OQL preview endpoint (POST /dev/preview_execute_oql), used to
// capture what the REAL mxcli binary prints for `oql --direct --json`. The runtime half (the
// bodies below) is synthetic and follows mxcli's own tests (cmd/mxcli/docker/oql_test.go:
// "the runtime omits a column from a row's JSON object when its value is null"); the
// *.stdout / *.stderr files beside this are mxcli v0.26.0's verbatim output for them.
// Re-capture on an mxcli upgrade:
//   node admin-api-stub.js 18991 &
//   mxcli oql --direct --host 127.0.0.1 --port 18991 --token stub --json "<sql from cases.txt>" \
//     > <case>.stdout 2> <case>.stderr
// The case is chosen by its marker string inside the query.
const http = require('http');
const bodies = {
  NULLCOL: { data: [{ zeta: 'z1', mid: 'm1' }, { zeta: 'z2', alpha: 'a2', mid: 'm2' }] },
  ALLNULL: { data: [{ zeta: 'z1', mid: 'm1' }] },
  VIEW:    { data: [{ ID: '281474976710657', n: '7' }] },
  BRACKET: { data: [{ label: 'a]b}c"d', n: '2' }] },
};
http.createServer((req, res) => {
  let b = '';
  req.on('data', (c) => { b += c; });
  req.on('end', () => {
    const q = JSON.parse(b).oql;
    const k = Object.keys(bodies).find((x) => q.includes(x));
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(bodies[k] || { data: [] }));
  });
}).listen(Number(process.argv[2]), '127.0.0.1');
