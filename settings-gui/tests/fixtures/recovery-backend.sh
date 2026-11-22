#!/bin/sh
set -eu

fixture_dir=${0%/*}
state_dir=${MLH_TEST_STATE_DIR:?}
case ${1:-} in
    snapshot)
        if [ -f "$state_dir/applied" ]; then
            if [ -f "$state_dir/fail_snapshot" ] && [ ! -f "$state_dir/allow_snapshot" ]; then
                printf '%s\n' 'fixture snapshot unavailable' >&2
                exit 1
            fi
            cat "$fixture_dir/recovery-after.json"
        else
            cat "$fixture_dir/recovery-before.json"
        fi
        ;;
    apply)
        cat >/dev/null
        touch "$state_dir/applied"
        printf '%s\n' 'fixture apply failed after partial save' >&2
        exit 1
        ;;
    *) exit 2 ;;
esac
