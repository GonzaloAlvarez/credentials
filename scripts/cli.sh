#!/bin/bash
# 
# General methods for Command Line Interface management
#

export VERBOSITY=4

function yes_or_no {
    while true; do
        read -p "$* [y/n]: " yn
        case $yn in
            [Yy]*) return 0  ;;  
            [Nn]*) echo "Aborted" ; return  1 ;;
        esac
    done
}

function _info {
    if [ $VERBOSITY -ge 3 ]; then
        echo -e -n "[\033[1m\033[32mINFO\033[0m] "
        echo "$@"
    fi
}

function _fatal {
    echo -e -n "[\033[1m\033[31mFATAL\033[0m] "
    if [ "$1" ]; then
        echo "$1"
    else
        echo "Error has occured"
    fi
    clean
    exit 1
}

function _warn {
    if [ $VERBOSITY -ge 2 ]; then
        echo -e -n "[\033[1m\033[33mWARN\033[0m] "
        echo "$@"
    fi
}


