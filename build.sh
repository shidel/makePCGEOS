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

    if [[ "${SWD}" != "${SWD,,}" ]] ; then
        echo "The perl script used in the build process restricts the path to all lowercase." >&2
        echo "Please relocate these files to a directory like \'${SWD,,}\'" >&2
        echo "Aborted!" >&2
        return 1
    fi

    local YMLS="${SWD}/pcgeos/.travis.yml"
    local YMLD="${SWD}/makePCGEOS.sh"
    local line
    local flag
    local perltee
    local logmsg
    local teefile
    local bitpatch

    [[ "$(uname -p)" == "x86_64" ]] && bitpatch=true

    echo '#!/bin/bash'>"${YMLD}"
    chmod +x "${YMLD}"
    echo ''>>"${YMLD}"
    clone make_bar draw_bar >>"${YMLD}"
    echo 'BAR=$(make_bar)'>>"${YMLD}"

    echo ''>>"${YMLD}"
    echo TRAVIS_BUILD_DIR="\"${SWD}/pcgeos\"">>"${YMLD}"
    echo 'cd $TRAVIS_BUILD_DIR || exit 1'>>"${YMLD}"

    # remove old Watcom download to allow script reuse
    echo '[[ -e ow-snapshot.tar.gz ]] && rm ow-snapshot.tar.gz'>>"${YMLD}"
    echo '[[ -e ow-snapshot.tar ]] && rm ow-snapshot.tar'>>"${YMLD}"

    echo ''>>"${YMLD}"

    # extract build commands from yaml file
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

        # remove leeading "- " from commands
        line="${line:2}"

        # add logging for perl scripts
        if [[ "${line/perl}" != "${line}" ]] ; then
            line="${line}"' | tee '${perltee}'$TRAVIS_BUILD_DIR/_perl.log'
            perltee="-a "
        fi

        # adjust tee command to not destroy previously logged info
        if [[ "${line/tee }" != "${line}" ]] && [[ "${line/tee -a }" == "${line}" ]] ; then
            teefile="${line#*tee }"
            teefile="${teefile%%|*}"
            echo "echo \"log: ${teefile}\">${teefile}">>"${YMLD}"
            line="${line/tee /tee -a }"
        fi

        # x86_64 bit build patch. esp compiler not automatically building on
        # 64 bit platforms. Must manually build it. For now.
        if [[ ${bitpatch} ]] && [[ "${line/cd \$TRAVIS_BUILD_DIR\/Tools\/sdk}" != "${line}" ]] ; then
            unset bitpatch
            echo "# start x86_64 bit patch">>"${YMLD}"
            echo "cd \$TRAVIS_BUILD_DIR/Installed/Tools/esp">>"${YMLD}"
            echo "draw_bar 'pmake -L 4 install '>>\$TRAVIS_BUILD_DIR/_build.log">>"${YMLD}"
            echo "pmake -L 4 install | tee -a \$TRAVIS_BUILD_DIR/_build.log">>"${YMLD}"
            echo "# end x86_64 bit patch">>"${YMLD}"
        fi

        # insert new bar in log before each line that references a log file
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

function sizeof () {
    local sz=0
    while [[ "${1}" != '' ]] ; do
        sz=$(( ${sz} + $(stat --format %s "${1}" 2>/dev/null || echo 0) ))
        shift
    done
    echo ${sz}
}

function main () {

    local lsz=-1
    local pss=0
    local csz

    info | tee pcgeos/_console.log

    prepare || return $?
    yml || return $?

    # run the build script up to 5 times. Keep repeating until the output files
    # stop growing. This is most likely do to esp not being automatically
    # generated.
    lsz=-1
    while [[ $pss -lt 5 ]] ; do
        (( pss++ ))

        csz=$( sizeof ${SWD}/pcgeos/_out/sdk/*.zip \
            ${SWD}/pcgeos/_out/sdk/pcgeos/Target/Ensemble.*/localpc/*.zip )

        csz=$(( ${csz} / 1024 )) # probably remove this when pmake no longer
                                 # changes during each build. It causes the zip
                                 # file size to fluctuate by a few bytes.

        [[ ${csz} -eq ${lsz} ]] && break
        lsz=${csz}
        echo ${csz}
        echo "Compile pass #${pss}"

        "${SWD}/makePCGEOS.sh" 2>&1 | tee -a pcgeos/_console.log || return $?
    done

    [[ ! -d ${SWD}/release ]] && mkdir -p ${SWD}/release
    cp -fav ${SWD}/pcgeos/_out/sdk/*.zip \
            ${SWD}/pcgeos/_out/sdk/pcgeos/Target/Ensemble.*/localpc/*.zip \
            release

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


