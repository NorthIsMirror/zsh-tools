#!/bin/zsh

emulate -L zsh
setopt extendedglob

zmodload zsh/zprof

zshs=( zsh-newheaps-zhalloc zsh-newheaps-only /bin/zsh zsh-head-both zsh-newheaps-three-patches zsh-5.1.1-dev-0-clean )

#
# Children administration
#

trap "finished" SIGUSR1

finished() {
    FINISHED=1
}

# Waits for signal from child process
wait_for_end_of_test() {
    while [ "$FINISHED" -eq 0 ]; do
        sleep 1
    done
    kill -15 "$SUB_PID"
}

_finished_signal_wait() {
    kill -SIGUSR1 "$MAIN_PID"
    sleep 60
}

#
# Tests
#

tests=( string_test array_test function_test search_test )

float multiplier=0.5

string_test() {
    local a=""
    integer i=$(( 150000*multiplier ))
    repeat $i; do a+="$i"; done
}

array_test() {
    typeset -a a
    integer i=$(( 25000*multiplier ))
    repeat $i; do a+=( $i ); done
}

function_test() {
    local count
    integer i=$(( 10000*multiplier ))

    if [ -z "$1" ]; then
        repeat $i; do function_test 100; done
    else
        count="$1"
    fi

    if (( count -- > 0 )); then
        function_test "$count"
    fi
}

search_test() {
    integer elements=$(( 800000 * multiplier ))
    a="${(r:elements:: _:)b}"
    a=( $=a )
    a=( "${(@M)a:#(#i)*_*}" )
    a=( "${(@)a//(#mi)(_|a)/-${MATCH}-}" )
    a=( "${(@)a//(#bi)(_|-)/|${match[1]}|}" )
}

#
# Main code
#

# Detect main vs. for-test invocation
if [ -z "$1" ]; then
    for current_zsh in "$zshs[@]"; do
        type "$current_zsh" 2>/dev/null 1>&2 || { echo >&2 "Skipping non-accessible $current_zsh"; continue }
        zsh_binary="${current_zsh##*/}"

        echo "# Tests for $zsh_binary"
        for test in "$tests[@]"; do
            FINISHED=0
            TEST="$test"

            "$current_zsh" -c "source ./$0 $$ \"$current_zsh\" $test" &

            SUB_PID=$!
            wait_for_end_of_test
        done
        echo
        echo

    done
else
    MAIN_PID="$1"
    zsh_binary="${2##*/}"
    shift
    shift
    echo -n "Running [$zsh_binary]: $@ "

    # Run the test
    zprof -c
    "$@"
    zprof_out=( "${(@f)"$( zprof )"}" )
    zprof_out="$zprof_out[3]"
    zprof_out=( $=zprof_out )
    echo "$zprof_out[3]"

    _finished_signal_wait
fi
