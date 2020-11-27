#!/bin/bash

SWD="${PWD}"

# cleanup to create fresh build
function remove () {
    local opts=-rf
    [[ "${VERBOSE}" == yes ]] && opts="-rfv"
	while [[ "${1}" != "" ]] ; do
		if [[ -e "${1}" ]] ; then
			rm ${opts} "${1}" || return $?
		fi
		shift
	done
	return 0
}

function make_bar () {
    local n
    n=""
    while [[ ${#n} -lt 80 ]] ; do
       n="${n}#"
    done
    echo "${n}"
}

function drawbar () {
    echo ${BAR}
    if [[ "${@}" != "" ]] ; then
        echo "${PWD} : ${@}"
    else
        echo ${PWD}
    fi
    echo ${BAR}
}

function cleanup () {
    remove watcom pcgeos ow-snapshot.tar.gz release "${LOG}"*
    return $?
}

function info () {
    if [[ -e /etc/os-release ]] ; then
        grep -i PRETTY_NAME /etc/os-release | cut -d '"' -f 2
    fi
    uname -a
    sed --version | grep -i '^sed'
    perl --version | grep -i 'version'
    return 0
}

# fetch or update to latest repository version of PC-GEOS
function prep_geos () {
    if [[ ! -d pcgeos ]] ; then
        git clone https://github.com/bluewaysw/pcgeos.git || return $?
    else
        cd pcgeos
        git pull
        cd ${SWD}
    fi
    return 0
}

# if not already downloaded, fetch latest version of WATCOM
function prep_watcom () {
    local opts
    if [[ ! -d watcom ]] ; then
        remove ow-snapshot.tar.gz || return $?
        wget https://github.com/open-watcom/open-watcom-v2/releases/download/Current-build/ow-snapshot.tar.gz || return $?
        mkdir watcom || return $?
        cd watcom
        [[ "${VERBOSE}" == yes ]] && opts="-xvzf" || opts="-xzf"
        tar ${opts} ${SWD}/ow-snapshot.tar.gz || return $?
        cd ${SWD}
        remove ow-snapshot.tar.gz || return $?
    fi
}

function prepare () {
    prep_geos || return $?
    prep_watcom || return $?
    return 0
}

function subshell () {
    /bin/bash ${@}
    return $?
}

function filter () {
    tee -a ${LOG} | grep -i -B 1 "######\|error\|warning\|not found\|can\'t" - | tee -a ${LOG}-errors
}

function process () {

    ${@} | filter "${@}"
    return $?

}

# Build PC/GEOS SDK
function build_sdk () {
    touch ${LOG}
    touch ${LOG}-error

    cd "${BWD}/Tools/pmake/pmake"
    process wmake install

    cd "${BWD}/Installed/Tools"
    process pmake -L 4 install

    cd "${BWD}/Installed"
    process pmake -L 4

    cd "${BWD}/Tools/sdk"
    process ./makesdk "${OWD}/sdk/pcgeos"

    return 0
}

function build_target () {
    cd "${OWD}/sdk"

    # Build target environment
    cd "${SWD}/pcgeos/Tools/build/product/bbxensem/Scripts"
    process perl -I. buildbbx.pl

    return 0
}

function build_all () {
    build_sdk || return $?
    build_target || return $?
    return 0
}

function main () {
#    cleanup || return $?
    info || return $?
    prepare || return $?
    build_all || return $?

}

# configure build environment
BWD=${SWD}/pcgeos
OWD=${SWD}/release
LOG=${SWD}/build.log
BAR=$(make_bar)
VERBOSE=no

export WATCOM=${SWD}/watcom
export PATH=${PATH}:${WATCOM}/binl64:${BWD}/bin
export ROOT_DIR=${BWD}
export LOCAL_DIR=${OWD}

if [[ ${#@} -eq 0 ]] ; then
    main
else
    while [[ "${1}" != '' ]] ; do
        case "${1}" in
            "clean")
                cleanup || exit $?
            ;;
            "info")
                info || exit $?
            ;;
            "verbose")
                VERBOSE=yes
            ;;
            "quite")
                VERBOSE=no
            ;;
            "prepare")
                prepare || exit $?
            ;;
            "build_sdk")
                build_sdk || exit $?
            ;;
            "subshell")
                subshell || exit $?
            ;;

        esac
        shift;
    done
fi


