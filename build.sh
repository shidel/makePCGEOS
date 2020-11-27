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

function draw_bar () {
    echo ${BAR}
    if [[ "${@}" != "" ]] ; then
        echo "${PWD} : ${@}"
    else
        echo ${PWD}
    fi
    echo ${BAR}
}

function cleanup () {
    remove pcgeos makePCGEOS.sh release
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
function prepare_geos () {
    if [[ ! -d pcgeos ]] ; then
        git clone https://github.com/bluewaysw/pcgeos.git || return $?
    else
        cd pcgeos
        git pull
        cd ${SWD}
    fi
    return 0
}

function prepare () {
    prepare_geos || return $?
    return 0
}

function filter () {
    tee -a ${LOG} | grep -i -B 1 "${BAR}\|error\|warning\|not found\|can\'t" - | tee -a ${LOG}-errors
}

function process () {

    ${@} | filter "${@}"
    return $?

}

function clone () {

    while [[ "${1}" != '' ]] ; do
        grep -A 1000 "function ${1} ()" "${0}" | grep -m 1 -B 1000 "^}"
        echo
        shift
    done

}

function yml () {
    local YMLS="${SWD}/pcgeos/.travis.yml"
    local YMLD="${SWD}/makePCGEOS.sh"
    local line
    local flag
    local perltee
    local logmsg
    local teefile

    echo '#!/bin/bash'>"${YMLD}"
    chmod +x "${YMLD}"
    echo ''>>"${YMLD}"
    clone make_bar draw_bar >>"${YMLD}"
    echo 'BAR=$(make_bar)'>>"${YMLD}"

    echo ''>>"${YMLD}"
    echo TRAVIS_BUILD_DIR="\"${SWD}/pcgeos\"">>"${YMLD}"
    echo 'cd $TRAVIS_BUILD_DIR || exit 1'>>"${YMLD}"
    echo '[[ -e ow-snapshot.tar.gz ]] && rm ow-snapshot.tar.gz'>>"${YMLD}"

    echo ''>>"${YMLD}"

    while IFS=""; read line ; do
        case "${line// }" in
            'script:' )
                flag=1
                continue
                ;;
            'before_deploy:' )
                flag=2
                ;;
        esac
        [[ "${flag}" != '1' ]] && continue
        line="${line:2}"
        if [[ "${line/perl}" != "${line}" ]] ; then
            line="${line}"' | tee '${perltee}'$TRAVIS_BUILD_DIR/_perl.log'
            perltee="-a "
        fi
        if [[ "${line/tee }" != "${line}" ]] && [[ "${line/tee -a }" == "${line}" ]] ; then
            teefile="${line#*tee }"
            teefile="${teefile%%|*}"
            echo "echo \"log: ${teefile}\">${teefile}">>"${YMLD}"
            line="${line/tee /tee -a }"
        fi
        if [[ "${line/.log}" != "${line}" ]] ; then
            teefile="${line#*tee -a }"
            teefile="${teefile%%|*}"
            logmsg="${line%%tee *}"
            logmsg="${logmsg%|*}"
            echo "draw_bar '${logmsg}'>>${teefile}">>"${YMLD}"
        fi
        echo "${line}">>"${YMLD}"
    done< "${YMLS}"

    [[ "${flag}" != 2 ]] && return 1 || return 0
}

function main () {
    info
    prepare || return $?
    yml || return $?
    "${SWD}/makePCGEOS.sh" || return $?
    return 0
}

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
            "release")
                main || exit $?
            ;;
        esac
        shift;
    done
fi


