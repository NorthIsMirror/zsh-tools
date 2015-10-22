#!/bin/zsh

emulate -L zsh
setopt extendedglob

zshs=( /bin/zsh zsh-head-both zsh-5.1.1-dev-0-clean )

# Convert sizes to number of megabytes
to_mbytes() {
    local size="$1"
    #echo "Converting $1"
    if [[ "$size" = [0-9]#[Mm]* ]]; then
        size="${size%[Mm]*}"
    elif [[ "$size" = [0-9]#[Kk]* ]]; then
        size="${size%[Kk]*}"
        (( size = size / 1024.0 ))
    elif [[ "$size" = [0-9]# ]]; then
        case $( uname ) in
            *Linux*)
                (( size = size / 1024.0 ))
                ;;
            *)
                (( size = size / (1024.0 * 1024.0) ))
                ;;
        esac
    else
        echo "Bad size occured: $size"
    fi

    REPLY="$size"
}

#
# Children administration
#

trap "finished" SIGUSR1

finished() {
    FINISHED=1
}

# Gets memory size of the zsh that runs the test
get_mem() {
    case $( uname ) in
        *Darwin*)
            output=( "${(@f)"$( top -pid "$SUB_PID" -stats mem -l 1 )"}" )
            to_mbytes "$output[-1]"
            ;;
        *Linux*)
            output=( "${(@f)"$( top -p "$SUB_PID" -bn 1 )"}" )
            output=$output[-1]
            output=( $=output )
            to_mbytes "$output[6]"
            ;;
    esac
}

# Waits for signal from child process
wait_get_mem() {
    local number
    float average=0.0
    integer count=0

    echo -n "# $TEST "

    sleep 1
    while [ "$FINISHED" -eq 0 ]; do
        get_mem
        number=`LANG=C printf "%.1f" "$REPLY"`
        echo -n "${number%.0}, "

        average+=number
        count+=1
        sleep 3
    done

    # Remove last result - to be certain that the average
    # is only above data from actively working test function
    if [ "$count" -gt 1 ]; then
        average=average-number
        count=count-1
    fi
    average=average/count

    # Take the explicit last result, it's telling
    # how zsh behaves when computation is stopped
    sleep 1
    get_mem
    number=`LANG=C printf "%.1f" "$REPLY"`
    echo "last: ${number%.0}"
    kill -15 "$SUB_PID"

    # Suitable for gnuplot - X Y
    LANG=C printf "$TEST %.1f\n" $average
}

_finished_signal_wait() {
    kill -SIGUSR1 "$MAIN_PID"
    sleep 60
}

#
# Tests
#

tests=( string_test array_test function_test search_test )

string_test() {
    local a=""
    integer i=150000
    repeat $i; do a+="$i"; done

    _finished_signal_wait
}

array_test() {
    typeset -a a
    integer i=25000
    repeat $i; do a+=( $i ); done

    _finished_signal_wait
}

function_test() {
    local count

    if [ -z "$1" ]; then
        repeat 10000; do function_test 100; done
        _finished_signal_wait
    else
        count="$1"
    fi

    if (( count -- > 0 )); then
        function_test "$count"
    fi
}

search_test() {
    integer elements=600000
    a="${(r:elements:: _:)b}"
    a=( $=a )
    a=( "${(@M)a:#(#i)*_*}" )
    a=( "${(@)a//(#mi)(_|a)/-${MATCH}-}" )
    a=( "${(@)a//(#bi)(_|-)/|${match[1]}|}" )

    _finished_signal_wait
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
            wait_get_mem
        done
        echo
        echo

    done

    # Example gnuplot invocation:
    #set style data histogram
    #set style fill solid border rgb "black"
    #plot "result" index 0 using 2: xtic(1), "result" index 1 using 2: xtic(1), "result" index 2 using 2: xtic(1)
else
    MAIN_PID="$1"
    zsh_binary="${2##*/}"
    shift
    shift
    # Echo status only when output is not to terminal
    [ ! -t 1 ] && echo >&2 "Running [$zsh_binary]: $@"

    # Run the test
    eval "run_test() { $@ }"
    run_test
fi
