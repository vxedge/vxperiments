"""A daemon stopped in the middle of `up`: the run must not read UP (vxedge 0.5.1)."""
import sys, time
sys.path.insert(0, '.')
import live
from live import check, log, reason

def state(a):
    ok, r = a.call('run_list')
    return [x['state'] for x in r['runs']] if ok else r

log('#### halfbuilt')
check(live.leaks(), 'host clean before start')
live.start_daemon()
a = live.agent()
ok, j = a.call('vehicle_up', {'workspace': live.V03})
time.sleep(2)
s = state(a)
check(s == ['RESOURCE_STATE_STAGING'], f'run_list while up runs: {s}')
live.watch(a, j['id'])
s = state(a)
check(s == ['RESOURCE_STATE_UP'], f'run_list once up ends: {s}')
ok, d = a.call('vehicle_down', {'workspace': live.V03})
live.watch(a, d['id'])
for delay in (3, 8, 12):
    log(f'== daemon stopped {delay}s into up')
    ok, j = a.call('vehicle_up', {'workspace': live.V03})
    time.sleep(delay)
    ok, g = a.call('job_get', {'id': j['id']})
    log(f'  at the stop: {g["state"]} {g["progressPercent"]}% {g["message"]}')
    live.stop_daemon()
    running = g['state'] in ('JOB_STATE_RUNNING', 'JOB_STATE_PENDING')
    live.start_daemon(); a.close(); a = live.agent()
    s = state(a)
    want = 'RESOURCE_STATE_DEGRADED' if running else 'RESOURCE_STATE_UP'
    check(s == [want], f'run_list after the daemon stopped: {s}, want {want}')
    ok, u = a.call('vehicle_up', {'workspace': live.V03})
    end = live.watch(a, u['id'])
    check(end['state'] == 'JOB_STATE_SUCCEEDED', f'a second up converges: {end["state"]}')
    s = state(a)
    check(s == ['RESOURCE_STATE_UP'], f'run_list after it: {s}')
    ok, d = a.call('vehicle_down', {'workspace': live.V03})
    end = live.watch(a, d['id'])
    check(end['state'] == 'JOB_STATE_SUCCEEDED', f'down {end["state"]}')
check(state(a) == [], 'run_list empty')
a.close(); live.stop_daemon()
check(live.leaks(), 'host clean after down')
log(f'#### halfbuilt: {len(live.FAILS)} failure(s)')
sys.exit(1 if live.FAILS else 0)
