# kuksa-perf's text summary as JSON lines, for the package's `samples`: one line with the run's
# counts, then one per latency percentile, in microseconds.
#
#   awk -f perf.awk <kuksa-perf output>
#
# {"op":"summary","api":"kuksa.val.v2","sent":3000,"skipped":500,"received":2500,...}
# {"op":"latency","quantile":"0.5","us":66}
#
# A run that received nothing prints no percentiles: kuksa-perf 0.3.2 prints a distribution of
# 0.000 ms for a run that sent nothing, and an empty run is a failed run, never a fast one. A run
# that could not connect gives its first error in `error`. Microseconds are read from the printed
# milliseconds, which have three decimals, so no rounding changes them.
function us(ms) { return sprintf("%.0f", ms * 1000) }
function str(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return "\"" s "\"" }
function put(k, v) { line = line "," str(k) ":" v }
/^ *API:/ { api = $2 }
/^ *Sent:/ { sent = $2 }
/^ *Skipped:/ { skipped = $2 }
/^ *Received:/ { received = $2 }
/^ *Throughput:/ { throughput = $2 }
/^ *Fastest:/ { fastest = us($2) }
/^ *Slowest:/ { slowest = us($2) }
/^ *Average:/ { average = us($2) }
/^Error: / && error == "" { error = substr($0, 8) }
/^ *[0-9]+% in under [0-9.]+ ms$/ {
    n++
    q[n] = substr($1, 1, length($1) - 1) / 100
    v[n] = us($4)
}
END {
    line = "{\"op\":\"summary\""
    if (api != "") put("api", str(api))
    if (sent != "") put("sent", sent)
    if (skipped != "") put("skipped", skipped)
    if (received != "") put("received", received)
    if (throughput != "") put("throughput_per_s", throughput)
    if (received > 0) {
        put("fastest_us", fastest); put("slowest_us", slowest); put("average_us", average)
    }
    if (error != "") put("error", str(error))
    print line "}"
    if (received > 0)
        for (i = 1; i <= n; i++)
            printf "{\"op\":\"latency\",\"quantile\":\"%g\",\"us\":%s}\n", q[i], v[i]
}
