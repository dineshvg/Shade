#!/bin/bash
# Collects what's needed to tell why Shade is slow or stuck. Run it while the problem is happening:
#   scripts/diagnose.sh            # report on the running app
#   scripts/diagnose.sh --sample   # also record 5 s of the main thread (attach the file to an issue)
set -u
bundle=io.github.dineshvg.shade
pid=$(pgrep -x Shade | head -n 1)

echo "== Shade process"
if [ -z "$pid" ]; then
    echo "Shade isn't running."
else
    ps -o pid,%cpu,%mem,rss,etime,command -p "$pid"
    echo "threads: $(ps -M -p "$pid" | tail -n +2 | wc -l | tr -d ' ')"
    echo "open files/sockets: $(lsof -p "$pid" 2>/dev/null | wc -l | tr -d ' ')"
    echo "connections to the Agent Traffic relay (:18090): $(lsof -nP -iTCP:18090 -sTCP:ESTABLISHED 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
    echo "git processes started by Shade right now: $(pgrep -P "$pid" -x git | wc -l | tr -d ' ')"
fi

echo
echo "== Settings"
echo "Record Agent Traffic by default: $(defaults read "$bundle" recordAgentTraffic 2>/dev/null || echo 'not set (off)')"
cards=$(defaults read "$bundle" cards 2>/dev/null | wc -c | tr -d ' ')
echo "saved cards: ${cards} bytes (re-encoded and saved on every keystroke)"

echo
echo "== Network"
if route -n get default >/dev/null 2>&1; then echo "default route: yes"; else echo "default route: none (offline)"; fi

echo
echo "== Your login shell's startup time (what a new terminal card runs)"
shell=${SHELL:-/bin/zsh}
start=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
"$shell" -l -i -c exit </dev/null >/dev/null 2>&1
end=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
echo "$shell -l -i: $(echo "$end - $start" | bc) s  (over ~0.5 s offline usually means a plugin or version"
echo "  manager in your profile is waiting for the network; try: zsh -xlic exit 2>&1 | tail -50)"

if [ "${1:-}" = "--sample" ] && [ -n "$pid" ]; then
    out="$HOME/Desktop/shade-sample-$(date +%Y%m%d-%H%M%S).txt"
    echo
    echo "== Sampling the main thread for 5 s → $out"
    sample "$pid" 5 -file "$out" >/dev/null 2>&1 && echo "done. Look at the top of 'Thread_… DispatchQueue_1: com.apple.main-thread'."
fi
