#!/bin/sh
set -eu
export LD_LIBRARY_PATH="${MLH_BRIDGE_DIR:?}:${LD_LIBRARY_PATH:-}"

work=$(mktemp -d -t 'mlh ibus-test.XXXXXXXX')
export XDG_CONFIG_HOME="$work/config"
export XDG_CACHE_HOME="$work/cache"
export XDG_RUNTIME_DIR="$work/runtime"
export IBUS_ADDRESS_FILE="$work/ibus-address"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
mkdir -p "$XDG_CONFIG_HOME/mlh"
printf 'ime\tIME\tinput method\n' > "$XDG_CONFIG_HOME/mlh/userdict.txt"
cat > "$work/filter" <<'EOF'
#!/bin/sh
tr '[:lower:]' '[:upper:]'
EOF
cat > "$work/slow" <<'EOF'
#!/bin/sh
exec sleep 5
EOF
cat > "$work/slow-filter" <<'EOF'
#!/bin/sh
sleep 0.5
tr '[:lower:]' '[:upper:]'
EOF
cat > "$work/fail" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$work/client" <<'EOF'
#!/bin/sh
printf '%s' "$MLH_CLIENT_BUNDLE_ID"
EOF
chmod +x "$work/filter" "$work/slow" "$work/slow-filter" "$work/fail" "$work/client"
"${MLH_OPENAI_SERVER:?}" > "$work/openai.port" &
server=$!
for _ in $(seq 1 100); do
    if [ -s "$work/openai.port" ]; then break; fi
    sleep 0.1
done
read -r port < "$work/openai.port"
export MLH_EXEC_BACKEND=openai
export MLH_OPENAI_BASE_URL="http://127.0.0.1:$port/v1"
export MLH_OPENAI_MODEL=test
printf '{"1":{"command":"%s"},"2":{"command":"%s"},"3":{"baseURL":"http://127.0.0.1:%s/v1","model":"test"},"4":{"command":"%s"},"5":{"command":"%s"},"apps":{"mlh-test":{"6":{"command":"%s"}}}}\n' "$work/filter" "$work/slow" "$port" "$work/slow-filter" "$work/fail" "$work/client" > "$XDG_CONFIG_HOME/mlh/execute.json"
mkdir -p "$work/components"
export IBUS_COMPONENT_PATH="$work/components"
cat > "$work/run-engine" <<EOF
#!/bin/sh
echo \$\$ > "$work/engine.pid"
exec "$MLH_IBUS_BINARY"
EOF
chmod +x "$work/run-engine"
"$MLH_IBUS_BINARY" --component-xml "$work/run-engine" > "$work/components/mlh.xml"

compositor=
client=
if [ -n "${MLH_GTK_CLIENT:-}" ]; then
    cat > "$work/sway.conf" <<EOF
output HEADLESS-1 resolution 1280x720
seat * fallback true
EOF
    WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman sway --config "$work/sway.conf" --debug > "$work/sway.log" 2>&1 &
    compositor=$!
    for _ in $(seq 1 100); do
        if [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then break; fi
        sleep 0.1
    done
    export WAYLAND_DISPLAY=wayland-1
    export GTK_IM_MODULE=ibus
    export GSK_RENDERER=cairo
fi
ibus-daemon --single --panel disable --emoji-extension disable &
daemon=$!
engine=
cleanup() {
    kill "$server" 2>/dev/null || :
    wait "$server" 2>/dev/null || :
    if [ -n "$client" ]; then kill "$client" 2>/dev/null || :; wait "$client" 2>/dev/null || :; fi
    if [ -f "$work/engine.pid" ]; then read -r engine < "$work/engine.pid"; fi
    if [ -n "$engine" ]; then kill "$engine" 2>/dev/null || :; wait "$engine" 2>/dev/null || :; fi
    kill "$daemon" 2>/dev/null || :
    wait "$daemon" 2>/dev/null || :
    if [ -n "$compositor" ]; then kill "$compositor" 2>/dev/null || :; wait "$compositor" 2>/dev/null || :; fi
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

address=
for _ in $(seq 1 100); do
    address=$(ibus address)
    if [ -n "$address" ] && [ "$address" != '(null)' ]; then break; fi
    sleep 0.1
done
if [ -z "$address" ] || [ "$address" = '(null)' ]; then
    echo 'IBus failed to start' >&2
    exit 1
fi

ibus list-engine
gdbus call --address "$address" --dest org.freedesktop.DBus \
    --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ListNames
gdbus call --address "$address" --dest org.freedesktop.IBus \
    --object-path /org/freedesktop/IBus --method org.freedesktop.IBus.SetGlobalEngine mlh
IBUS_TEST_ADDRESS="$address" cargo test --manifest-path "$MLH_MANIFEST" --test real_ibus -- --ignored
if [ -n "${MLH_GTK_CLIENT:-}" ]; then
    if [ -z "${MLH_VTE_ONLY:-}" ]; then
    "$MLH_GTK_CLIENT" > "$work/gtk.log" 2>&1 &
    client=$!
    sleep 1
    wtype -M shift -m shift -s 1500 -d 30 'nihongof/' -k space
    if ! wait "$client"; then
        cat "$work/gtk.log" >&2
        exit 1
    fi
    client=
    cat "$work/gtk.log"
    "$MLH_GTK_CLIENT" > "$work/gtk.log" 2>&1 &
    client=$!
    sleep 1
    wtype -M shift -m shift -s 1500 -d 30 'nihongo/' -k space -s 300 -M ctrl -k g -m ctrl
    if ! wait "$client"; then
        cat "$work/gtk.log" >&2
        exit 1
    fi
    client=
    cat "$work/gtk.log"
    MLH_EXPECT=日本語 "$MLH_GTK_CLIENT" > "$work/gtk.log" 2>&1 &
    client=$!
    sleep 1
    wtype -M shift -m shift -s 1500 -d 30 'nihongo/' -k space -s 300 -k Return
    if ! wait "$client"; then
        cat "$work/gtk.log" >&2
        exit 1
    fi
    client=
    cat "$work/gtk.log"
    MLH_EXPECT='input method' "$MLH_GTK_CLIENT" > "$work/gtk.log" 2>&1 &
    client=$!
    sleep 1
    wtype -M shift -m shift -s 1500 -d 30 'imed/' -k space -s 300 -k space '/'
    if ! wait "$client"; then
        cat "$work/gtk.log" >&2
        exit 1
    fi
    client=
    cat "$work/gtk.log"
    MLH_EXPECT=HELLO "$MLH_GTK_CLIENT" > "$work/gtk.log" 2>&1 &
    client=$!
    sleep 1
    wtype -M shift -m shift -s 1500 -d 30 'hello1x/' -k space
    if ! wait "$client"; then cat "$work/gtk.log" >&2; exit 1; fi
    client=
    cat "$work/gtk.log"
    MLH_EXPECT=hello "$MLH_GTK_CLIENT" > "$work/gtk.log" 2>&1 &
    client=$!
    sleep 1
    wtype -M shift -m shift -s 1500 -d 30 'hello2x/' -k space -s 300 -k Escape
    if ! wait "$client"; then cat "$work/gtk.log" >&2; exit 1; fi
    client=
    cat "$work/gtk.log"
    MLH_FOCUS_TEST=1 MLH_FOCUS_MARKER="$work/switched" MLH_EXPECT=日本語 "$MLH_GTK_CLIENT" > "$work/gtk.log" 2>&1 &
    client=$!
    sleep 1
    swaymsg -s "$XDG_RUNTIME_DIR"/sway-ipc.*.sock '[title="mlh-first"] focus'
    wtype -M shift -m shift -s 1500 -d 30 'nihongo/' -k space
    swaymsg -s "$XDG_RUNTIME_DIR"/sway-ipc.*.sock '[title="mlh-second"] focus'
    touch "$work/switched"
    if ! wait "$client"; then cat "$work/gtk.log" >&2; exit 1; fi
    client=
    cat "$work/gtk.log"
    rm "$work/switched"
    MLH_FOCUS_TEST=1 MLH_FOCUS_MARKER="$work/switched" MLH_EXPECT=hello "$MLH_GTK_CLIENT" > "$work/gtk.log" 2>&1 &
    client=$!
    sleep 1
    swaymsg -s "$XDG_RUNTIME_DIR"/sway-ipc.*.sock '[title="mlh-first"] focus'
    wtype -M shift -m shift -s 1500 -d 30 'hello4x/' -k space
    sleep 0.1
    swaymsg -s "$XDG_RUNTIME_DIR"/sway-ipc.*.sock '[title="mlh-second"] focus'
    touch "$work/switched"
    if ! wait "$client"; then cat "$work/gtk.log" >&2; exit 1; fi
    client=
    cat "$work/gtk.log"
    rm "$work/switched"
    MLH_FOCUS_TEST=1 MLH_FOCUS_MARKER="$work/switched" MLH_EXPECT=hello "$MLH_GTK_CLIENT" > "$work/gtk.log" 2>&1 &
    client=$!
    sleep 1
    swaymsg -s "$XDG_RUNTIME_DIR"/sway-ipc.*.sock '[title="mlh-first"] focus'
    wtype -M shift -m shift -s 1500 -d 30 'hello3x/' -k space -s 2000 &
    keyboard=$!
    sleep 2.1
    swaymsg -s "$XDG_RUNTIME_DIR"/sway-ipc.*.sock '[title="mlh-second"] focus'
    touch "$work/switched"
    wait "$keyboard"
    if ! wait "$client"; then cat "$work/gtk.log" >&2; exit 1; fi
    client=
    cat "$work/gtk.log"
    MLH_EXPECT=ABC "$MLH_GTK_CLIENT" > "$work/gtk.log" 2>&1 &
    client=$!
    sleep 1
    wtype -M shift -m shift -s 1500 -d 30 'hello3x/' -k space -s 1000
    if ! wait "$client"; then cat "$work/gtk.log" >&2; exit 1; fi
    client=
    cat "$work/gtk.log"
    fi
    gjs "$(dirname "$0")/fixtures/vte-client.js" > "$work/vte.log" 2>&1 &
    client=$!
    sleep 1
    wtype -M shift -m shift -s 1500 -d 30 'nihongo/' -k space -s 300 -k Return -s 500
    if ! wait "$client"; then cat "$work/vte.log" >&2; exit 1; fi
    client=
    cat "$work/vte.log"
    if rg -q 'Event with type .* not holding a GdkDevice' "$work/vte.log"; then
        echo 'terminal conversion unexpectedly forwarded synthetic keys' >&2
        exit 1
    fi
    MLH_VTE_EXPECT=HELLO MLH_VTE_FORBIDDEN=hello gjs "$(dirname "$0")/fixtures/vte-client.js" > "$work/vte.log" 2>&1 &
    client=$!
    sleep 1
    wtype -M shift -m shift -s 1500 -d 30 'hello1x/' -k space -s 500
    if ! wait "$client"; then cat "$work/vte.log" >&2; exit 1; fi
    client=
    cat "$work/vte.log"
    if [ -n "${MLH_GNOME_TERMINAL_TEST:-}" ]; then
        sh "$MLH_GNOME_TERMINAL_TEST" --title 'mlh helper test'
        terminal_pid=$(gdbus call --session --dest org.freedesktop.DBus \
            --object-path /org/freedesktop/DBus \
            --method org.freedesktop.DBus.GetConnectionUnixProcessID org.mlh.Terminal)
        terminal_pid=${terminal_pid#*uint32 }
        terminal_pid=${terminal_pid%%,*}
        if ! tr '\0' '\n' < "/proc/$terminal_pid/environ" | rg -Fx 'GTK_IM_MODULE=ibus'; then
            echo 'GNOME Terminal helper did not enable the GTK IBus module' >&2
            exit 1
        fi
    fi
fi
for _ in $(seq 1 100); do
    if gdbus call --address "$address" --dest org.freedesktop.IBus.Mlh \
        --object-path /org/freedesktop/IBus/Factory \
        --method org.freedesktop.IBus.Factory.CreateEngine mlh; then
        exit 0
    fi
    sleep 0.1
done
echo 'mlh engine failed to register' >&2
exit 1
