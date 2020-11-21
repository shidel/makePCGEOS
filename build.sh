#!/bin/bash

# cleanup to create fresh build
function remove () {
	while [[ "${1}" != "" ]] ; do
		if [[ -e "${1}" ]] ; then
			rm -rfv "${1}" || return $?
		fi
		shift
	done
	return 0
}

if [[ "${1}" == "clean" ]] ; then
	remove watcom pcgeos ow-snapshot.tar.gz release
	exit 0
fi

# display some version information
if [[ -e /etc/os-release ]] ; then
	grep -i PRETTY_NAME /etc/os-release | cut -d '"' -f 2
fi

uname -a
sed --version | grep -i '^sed'
perl --version | grep -i 'version'
echo

# fetch or update to latest repository version of PC-GEOS
if [[ ! -d pcgeos ]] ; then
	git clone https://github.com/bluewaysw/pcgeos.git
else
	cd pcgeos
	git pull
	cd ..
fi

# if not already downloaded, fetch latest version of WATCOM
if [[ ! -d watcom ]] ; then
	remove ow-snapshot.tar.gz
	wget https://github.com/open-watcom/open-watcom-v2/releases/download/Current-build/ow-snapshot.tar.gz
	mkdir watcom
	cd watcom
	tar -xvzf ../ow-snapshot.tar.gz
	cd ..
	remove ow-snapshot.tar.gz
fi;

remove release
SRCS=${PWD}

# configure build environment
export WATCOM=${PWD}/watcom
export PATH=${PATH}:${WATCOM}/binl64:${WATCOM}/binnt:${PWD}/pcgeos/bin
export ROOT_DIR=${SRCS}/release
export LOCAL_DIR=

# Build PC/GEOS SDK
cd "${SRCS}/pcgeos/Tools/pmake/pmake"
wmake install

cd "${SRCS}/pcgeos/Installed/Tools"
pmake install

cd "${SRCS}/pcgeos/Installed"
pmake

# Build target environment
cd "${SRCS}/pcgeos/Tools/build/product/bbxensem/Scripts"
perl -I. buildbbx.pl



