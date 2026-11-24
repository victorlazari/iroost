#!/usr/bin/env python3
"""The panel's refresh with one machine that hangs: the real panel (_panel: fzf under a pseudo-terminal), its own
tmux server, a temporary HOME and an ssh stand-in that never answers (no network). It checks, through fzf's --listen
API and the panel's own files, that:

- a healthy profile's new session shows while the hung profile's worker is still blocked, on the first refresh
  (start, the same path as r) and on the periodic one (_ticker);
- the hung profile keeps its last rows, marked stale, rather than vanishing;
- the highlight stays on its session across those reloads; a key and a click still act during a refresh;
- r pressed during a refresh starts no second collection; quitting leaves none of the test's processes behind;
- after the panel is resized, a refresh's redraw (the last one, and the periodic one) keeps the new width;
- with two panels, a change made after one panel's collection read the machine still reaches the other panel
  (which asked after that change), rather than the other panel taking the older rows;
- a change made during a panel's own refresh (`again`, as every session change asks) runs it once more when done.

Run: python3 tests/session-refresh.py [--receipt FILE]. Needs tmux, git, curl, zsh and fzf 0.74+; skips otherwise.
"""
import json, os, pty, shutil, signal, subprocess, sys, tempfile, threading, time, urllib.request, fcntl, termios, struct
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
KEY = 'iroost-test-key-0123456789abcdef'
N = 30
fails, notes = [], {}


def need(cmd):
    if not shutil.which(cmd):
        print(f'skip: needs {cmd}'); sys.exit(0)


for c in ('tmux', 'git', 'curl', 'zsh', 'fzf'):
    need(c)
ver = subprocess.run(['fzf', '--version'], capture_output=True, text=True).stdout.split()[0]
if tuple(int(x) for x in ver.split('.')[:2]) < (0, 74):
    print(f'skip: needs fzf 0.74+ (found {ver})'); sys.exit(0)

receipt = None
if '--receipt' in sys.argv:
    receipt = Path(sys.argv[sys.argv.index('--receipt') + 1])

T = Path(tempfile.mkdtemp(prefix='iroost-refresh-'))
HOME, BIN, W, SOCK = T / 'home', T / 'bin', T / 'w', T / 'tmux.sock'
STATE = HOME / '.cache/iroost'
for d in (HOME, BIN, W / 'loc', W / 'far'):
    d.mkdir(parents=True)
RT = shutil.which('tmux')
port = 0
import socket
with socket.socket() as s:
    s.bind(('127.0.0.1', 0)); port = s.getsockname()[1]


def stub(name, body):
    p = BIN / name
    p.write_text('#!/bin/sh\n' + body + '\n'); p.chmod(0o755)


# tmux: always this test's own server, whatever -L/-S the caller names (the layout's -L iroost too).
stub('tmux', f'''n=$# skip= opts=1
while [ $n -gt 0 ]; do
  x=$1; shift; n=$((n - 1))
  if [ -n "$skip" ]; then skip=
  elif [ -n "$opts" ] && {{ [ "$x" = -L ] || [ "$x" = -S ]; }}; then skip=1
  else case $x in -*) ;; *) opts= ;; esac; set -- "$@" "$x"; fi
done
printf 'tmux %s\\n' "$1" >>{T}/calls
exec {RT} -S {SOCK} "$@"''')
# ssh: never a network. "ok" runs the script here; otherwise it records its pid and blocks until killed.
stub('ssh', f'''for x; do last=$x; done
printf 'ssh %s\\n' $$ >>{T}/calls
if [ "$(cat {T}/ssh.mode 2>/dev/null)" = ok ]; then exec sh -c "$last"; fi
if [ "$(cat {T}/ssh.mode 2>/dev/null)" = gate ]; then
  sh -c "$last" >{T}/ssh.buf.$$; : >{T}/ssh.read.$$
  while [ ! -e {T}/ssh.go ]; do sleep 0.02; done
  exec cat {T}/ssh.buf.$$
fi
echo $$ >{T}/ssh.pid.$$; exec sleep 30''')
stub('openssl', f'echo {KEY}')
stub('fzf', f'exec {shutil.which("fzf")} "$@" --listen-unsafe=${{RFTEST_PORT:-{port}}}')
for n in ('osascript', 'open', 'xdg-open', 'gh'):
    stub(n, 'exit 1')

env = {k: v for k, v in os.environ.items() if not k.startswith(('TMUX', 'XDG_', 'IROOST_', 'FZF_'))}
env.update(HOME=str(HOME), PATH=f'{BIN}:{env["PATH"]}', TERM='xterm-256color', LC_ALL='C.UTF-8', TMPDIR=str(T),
           IROOST_PRS='0', IROOST_POKEMON='off', IROOST_SPOTIFY='off', IROOST_PANEL_WIDTH='56')
IROOST = [str(REPO / 'bin/iroost')]


def tm(*a):
    subprocess.run([RT, '-S', str(SOCK), '-f', '/dev/null', *a], check=True, env=env)


def term(name, d):
    tm('new-session', '-d', '-s', name, '-c', str(d), '/bin/sh')
    tm('set-option', '-t', f'={name}:', '@iroost_agent', 'term')


prof = HOME / '.config/iroost/profiles'
prof.mkdir(parents=True)
(prof / 'local.conf').write_text(f'type=local\nrepos={W}\nonly={W}/loc\n')
(prof / 'far.conf').write_text(f'type=ssh\nhost=fake.invalid\nrepos={W}\nonly={W}/far\n')
for i in range(1, N + 1):
    term(f'loc{i:02}', W / 'loc')
term('far1', W / 'far'); term('far2', W / 'far')

# The last good list: every profile answers once (the panel opens on it, as after any earlier refresh).
(T / 'ssh.mode').write_text('ok')
r = subprocess.run(IROOST + ['_list', '1'], env=env, capture_output=True, timeout=30)
seed = (STATE / 'raw-local').read_text().count('\n'), (STATE / 'raw-far').read_text().count('\n')
if seed != (N, 2):
    fails.append(f'seed: want {N} local and 2 far rows, got {seed} ({r.stderr.decode()[-300:]})')
(T / 'ssh.mode').write_text('block')
# far2 was last seen working: only a fresh answer from its machine may say it finished (an alert).
(STATE / 'seen/far/far2').write_text('0\x1fwork\x1f\n')
(T / 'calls').write_text('')
term('late1', W / 'loc')


def api(q='?limit=300', data=None, p=None):
    req = urllib.request.Request(f'http://127.0.0.1:{p or port}{q}', data=data, headers={'x-api-key': KEY})
    with urllib.request.urlopen(req, timeout=2) as resp:
        return resp.read().decode()


def state(p=None):
    try:
        j = json.loads(api(p=p))
    except Exception:
        return None
    keys = [m['text'].split('\t')[0] for m in j.get('matches', [])]
    cur = (j.get('current') or {}).get('text', '').split('\t')[0]
    return keys, cur, [m['text'] for m in j.get('matches', [])]


def ssh_pids():
    return sorted(int(p.name.split('.')[-1]) for p in T.glob('ssh.pid.*'))


def alive(pid):
    try:
        os.kill(pid, 0); return True
    except ProcessLookupError:
        return False


def wait(pred, secs, step=0.02):
    end = time.monotonic() + secs
    while time.monotonic() < end:
        v = pred()
        if v:
            return v
        time.sleep(step)
    return None


def head_width(st, key='local/'):
    """The visible width of profile KEY's heading in fzf's list (it is ruled out to the panel's width)."""
    import re
    for t in (st or ([], '', []))[2]:
        if t.startswith(key + '\t'):
            return len(re.sub(r'\x1b\[[0-9;]*m', '', t.split('\t', 1)[1]).strip('\n'))
    return None


def resize(cols):
    """Resize the panel's terminal to COLS columns (fzf hears SIGWINCH) and wait for its redraw at that width."""
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 60, cols, 0, 0))
    os.killpg(panel.pid, signal.SIGWINCH)
    return wait(lambda: (w := head_width(state())) and w > 56 and w, 5)


def ssh_count():
    return sum(1 for l in (T / 'calls').read_text().splitlines() if l.startswith('ssh '))


# The panel, under a pseudo-terminal of a fixed size.
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 60, 56, 0, 0))
panel = subprocess.Popen(IROOST + ['_panel', '1'], stdin=slave, stdout=slave, stderr=slave, env={**env, 'RFTEST_TAG': str(T)},
                         start_new_session=True)
os.close(slave)
def drain():
    try:
        while os.read(master, 65536):
            pass
    except OSError:
        pass


threading.Thread(target=drain, daemon=True).start()


def key_latency(seq, label):
    """Send seq to the panel; the time until fzf's highlight moves (None: it never moved in 3s)."""
    s0 = state()
    t0 = time.monotonic()
    os.write(master, seq)
    moved = wait(lambda: (st := state()) and st[1] != s0[1] and st, 3, 0.005)
    lat = round(time.monotonic() - t0, 3) if moved else None
    notes[label] = lat
    return moved


def published_while_blocked(name, label):
    """Wait for NAME's row after the hung worker started; it counts only if that worker is still blocked."""
    pid = wait(lambda: [p for p in ssh_pids() if p not in seen_pids], 25)
    if not pid:
        fails.append(f'{label}: the hung profile was never asked (fixture)'); return None
    pid = pid[0]; seen_pids.add(pid)
    t0 = time.monotonic()
    notes[f'{label}_kbd_during_refresh_s'] = None
    moved = key_latency(b'\x1b[B', f'{label}_kbd_during_refresh_s')
    if not moved:
        fails.append(f'{label}: the down key moved nothing during the refresh')
    if label == 'manual':
        os.write(master, b'r')  # a refresh is running: r must not start a second collection
    got = wait(lambda: (st := state()) and f'local/{name}' in st[0] and st, 12)
    # Still blocked: its ssh runs and iroost has not given up on it (down-far is its timeout's mark).
    blocked = alive(pid) and not (STATE / 'down-far').exists()
    notes[f'{label}_publish_s'] = round(time.monotonic() - t0, 3) if got else None
    notes[f'{label}_worker_blocked_at_publish'] = blocked
    if not got:
        fails.append(f'{label}: local/{name} never showed')
    elif not blocked:
        fails.append(f'{label}: local/{name} showed only after the hung worker ended '
                     f'({notes[f"{label}_publish_s"]}s): the healthy profile waited for it')
    if got and moved and got[1] != moved[1]:
        fails.append(f'{label}: the highlight moved from {moved[1]} to {got[1]} on reload')
    healthy = sum(1 for k in (got or [[]])[0] if k.startswith('local/') and k != 'local/')
    notes[f'{label}_healthy_rows_at_publish'] = healthy
    return pid


def two_panels():
    """Panel 1 reads the far machine (held before it answers); far3 starts; panel 2 asks for a refresh (the path
    every session change takes); panel 1's answer comes back. Panel 2 must show far3."""
    global panel2, master2
    with socket.socket() as so:
        so.bind(('127.0.0.1', 0)); port2 = so.getsockname()[1]
    master2, slave2 = pty.openpty()
    fcntl.ioctl(slave2, termios.TIOCSWINSZ, struct.pack('HHHH', 60, 56, 0, 0))
    panel2 = subprocess.Popen(IROOST + ['_panel', '2'], stdin=slave2, stdout=slave2, stderr=slave2,
                              env={**env, 'RFTEST_TAG': str(T), 'RFTEST_PORT': str(port2)}, start_new_session=True)
    os.close(slave2)
    def drain2():
        try:
            while os.read(master2, 65536):
                pass
        except OSError:
            pass
    threading.Thread(target=drain2, daemon=True).start()
    if not wait(lambda: (st := state(port2)) and 'local/loc01' in st[0], 15):
        fails.append('two panels: panel 2 never listed (fixture)'); return
    if not wait(lambda: not any((STATE / f'{i}.rflock').exists() for i in (1, 2)) and not ssh_pids_alive(), 20):
        fails.append('two panels: the earlier refreshes never ended (fixture)'); return
    for f in STATE.glob('down-*'):
        f.unlink()
    (T / 'ssh.mode').write_text('gate')
    before = ssh_count()
    os.write(master, b'r')
    if not wait(lambda: list(T.glob('ssh.read.*')), 10):
        fails.append('two panels: panel 1 never read the far machine (fixture)'); return
    term('far3', W / 'far')
    api(q='', data=f'execute-silent({IROOST[0]} _refresh 2 $FZF_PORT again)'.encode(), p=port2)
    # Panel 2's refresh has asked (it holds its lock) before panel 1's collection answers.
    if not wait(lambda: (STATE / '2.rflock').exists(), 5):
        fails.append('two panels: panel 2 never started its refresh (fixture)')
    time.sleep(0.3)
    (T / 'ssh.go').write_text('')
    # What panel 2 shows once both refreshes are over (and their reruns): not a later periodic one's work.
    t0 = time.monotonic()
    wait(lambda: not any((STATE / f'{i}.{x}').exists() for i in (1, 2) for x in ('rflock', 'rfagain')), 12)
    notes['two_panels_settle_s'] = round(time.monotonic() - t0, 3)
    st = state(port2)
    got = st and 'far/far3' in st[0]
    notes['two_panels_far_collections'] = ssh_count() - before
    notes['two_panels_far3_shown'] = bool(got)
    if not got:
        fails.append('two panels: panel 2 asked after far3 started, yet shows the older rows of panel 1\'s collection')


def rerun():
    """Panel 1's refresh reads the far machine (held); far4 starts; a change asks panel 1 `again`. Once its refresh
    is done it must run once more and show far4, and leave no lock behind."""
    if not wait(lambda: not any((STATE / f'{i}.rflock').exists() for i in (1, 2)) and not ssh_pids_alive(), 20):
        fails.append('rerun: the earlier refreshes never ended (fixture)'); return
    for f in [*T.glob('ssh.read.*'), *T.glob('ssh.buf.*'), T / 'ssh.go', *STATE.glob('down-*')]:
        f.unlink(missing_ok=True)
    (T / 'ssh.mode').write_text('gate')
    os.write(master, b'r')
    if not wait(lambda: list(T.glob('ssh.read.*')), 10):
        fails.append('rerun: panel 1 never read the far machine (fixture)'); return
    term('far4', W / 'far')
    api(q='', data=f'execute-silent({IROOST[0]} _refresh 1 $FZF_PORT again)'.encode())
    if not wait(lambda: (STATE / '1.rfagain').exists(), 5):
        fails.append('rerun: the change was not queued (fixture)')
    (T / 'ssh.go').write_text('')
    t0 = time.monotonic()
    settled = wait(lambda: not any((STATE / f'1.{x}').exists() for x in ('rflock', 'rfagain')), 12)
    notes['rerun_settle_s'] = round(time.monotonic() - t0, 3) if settled else None
    got = wait(lambda: (st := state()) and 'far/far4' in st[0], 3)
    notes['rerun_far4_shown'] = bool(got)
    if not settled:
        fails.append('rerun: panel 1\'s refresh lock was still held 12s after its machine answered')
    if not got:
        fails.append('rerun: a change queued during the refresh never ran (far4 not shown)')


def ssh_pids_alive():
    return [p for p in ssh_pids() if alive(p)]


panel2 = master2 = None
seen_pids = set()
try:
    st0 = wait(lambda: (st := state()) and sum(k.startswith('local/loc') for k in st[0]) == N and st, 15)
    if not st0:
        fails.append('the panel never listed the last good rows (fixture)')
        raise SystemExit
    pid1 = published_while_blocked('late1', 'manual')
    # Resized while the hung profile still holds the refresh: its last redraw must keep the new width.
    notes['resized_width'] = resize(80)
    if not notes['resized_width']:
        fails.append('resize: the panel never redrew wider (fixture)')
    notes['manual_ssh_collections'] = ssh_count()
    if ssh_count() != 1:
        fails.append(f'manual: want 1 collection of the hung profile, got {ssh_count()}')
    # The hung worker times out: its last rows stay, marked stale.
    if pid1:
        wait(lambda: not alive(pid1), 12)
        wait(lambda: not (STATE / '1.rflock').exists(), 5)
        time.sleep(0.5)
        st = state() or ([], '', [])
        notes['manual_width_after_refresh'] = head_width(st)
        if notes['resized_width'] and head_width(st) != notes['resized_width']:
            fails.append(f'resize: the refresh redrew at the old width ({head_width(st)}, panel is {notes["resized_width"]})')
        far = [t for t in st[2] if t.startswith('far/')]
        notes['stale_far_rows'] = sum(1 for t in far if t != far[0]) if far else 0
        if not any(k == 'far/far1' for k in st[0]):
            fails.append('stale: the hung profile\'s last rows vanished after its timeout')
        if not any(t.startswith('far/\t') and 'stale' in t for t in st[2]):
            fails.append('stale: the hung profile\'s heading does not say stale')
        if (STATE / 'unread/far/far2').exists():
            fails.append('stale: the hung profile\'s old rows made an alert (far2 marked finished)')
        kept = sorted(f.name for f in (STATE / 'seen/far').glob('*'))
        notes['stale_seen_kept'] = kept
        if kept != ['far1', 'far2']:
            fails.append(f'stale: the hung profile\'s sessions were dropped from the alert state: {kept}')
    # A click on a row: fzf's highlight or the viewer's target goes to it.
    tgt0 = (STATE / '1.target').read_text() if (STATE / '1.target').exists() else ''
    s0 = state()
    t0 = time.monotonic()
    os.write(master, b'\x1b[<0;10;12M\x1b[<0;10;12m')
    clicked = wait(lambda: ((STATE / '1.target').exists() and (STATE / '1.target').read_text() != tgt0) or
                   ((st := state()) and st[1] != s0[1]), 3, 0.005)
    notes['click_s'] = round(time.monotonic() - t0, 3) if clicked else None
    if not clicked:
        fails.append('click: neither the highlight nor the viewer target moved')
    # The periodic refresh (_ticker, every 15s) with the machine hung again.
    for f in STATE.glob('down-*'):
        f.unlink()
    term('late2', W / 'loc')
    published_while_blocked('late2', 'ticker')
    st = state()
    notes['ticker_width_at_publish'] = head_width(st)
    if notes['resized_width'] and head_width(st) != notes['resized_width']:
        fails.append(f'resize: the periodic refresh redrew at the old width ({head_width(st)}, panel is {notes["resized_width"]})')
    time.sleep(0.3)
    os.write(master, b'r')
    time.sleep(0.5)
    notes['total_ssh_collections'] = ssh_count()
    if ssh_count() != 2:
        fails.append(f'ticker: want 2 collections of the hung profile in all, got {ssh_count()}')
    two_panels()
    rerun()
finally:
    os.write(master, b'q')
    if panel2:
        os.write(master2, b'q')
        try:
            panel2.wait(10)
        except subprocess.TimeoutExpired:
            fails.append('quit: panel 2 did not end'); os.killpg(panel2.pid, signal.SIGKILL)
    try:
        panel.wait(10)
    except subprocess.TimeoutExpired:
        fails.append('quit: the panel did not end'); os.killpg(panel.pid, signal.SIGKILL)

    def ours():
        left = []
        for p in Path('/proc').iterdir():
            if not p.name.isdigit():
                continue
            try:
                cmd = (p / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
                envb = (p / 'environ').read_bytes()
            except OSError:
                continue
            if f'RFTEST_TAG={T}'.encode() in envb and p.name != str(os.getpid()):
                left.append(f'{p.name}:{cmd[:80]}')
        return left
    left = wait(lambda: not ours() and ['none'], 12, 0.2)
    notes['leftover_processes'] = [] if left else ours()
    if not left:
        fails.append(f'quit: processes left behind: {ours()}')
    subprocess.run([RT, '-S', str(SOCK), 'kill-server'], capture_output=True)
    shutil.rmtree(T, ignore_errors=True)

print(json.dumps(notes, sort_keys=True))
if receipt:
    with receipt.open('a') as f:
        f.write(json.dumps({'fails': fails, **notes}, sort_keys=True) + '\n')
for f in fails:
    print('FAIL:', f)
print('ok' if not fails else f'{len(fails)} failure(s)')
sys.exit(1 if fails else 0)
