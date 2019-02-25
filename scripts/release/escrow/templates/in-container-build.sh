#!/bin/bash -e

# Error-check. This directory should exist due to the "docker run" mount.
if [ ! -e /escrow ]
then
  echo "This script is intended to be run inside a specifically-configured "
  echo "Docker container. See build-couchbase-server-from-escrow.sh."
  exit 100
fi

DOCKER_PLATFORM=$1
VERSION=$2

CBDDEPS_VERSIONS="0.8.3 0.9.0 0.9.1"

# Convert Docker platform to Build platform (sorry they're different)
if [ "${DOCKER_PLATFORM}" = "ubuntu18" ]
then
  PLATFORM=ubuntu18.04
elif [ "${DOCKER_PLATFORM}" = "ubuntu16" ]
then
  PLATFORM=ubuntu16.04
else
  PLATFORM="${DOCKER_PLATFORM}"
fi

heading() {
  echo
  echo ::::::::::::::::::::::::::::::::::::::::::::::::::::
  echo $*
  echo ::::::::::::::::::::::::::::::::::::::::::::::::::::
  echo
}

# Set HOME - not always set via "docker exec"
export HOME=/home/couchbase

# Global directories
ROOT=/home/couchbase/escrow
CACHE=/home/couchbase/.cbdepscache
TLMDIR=/home/couchbase/tlm

# Not sure why this is necessary, but it is for v8
if [ "${PLATFORM}" = "ubuntu16.04" ]
then
  heading "Installing pkg-config..."
  sudo apt-get update && sudo apt-get install -y pkg-config
fi

# Create all cbdeps. Start with the cache directory.
mkdir -p ${CACHE}

# Pre-populate the JDK by hand.
heading "Populating JDK..."
cd ${CACHE}
mkdir -p exploded/x86_64
cd exploded/x86_64
tar xf ${ROOT}/deps/jdk-11_linux-x64_bin.tar.gz

# Copy of tlm for working in.
if [ ! -d "${TLMDIR}" ]
then
  cp -aL ${ROOT}/src/tlm ${TLMDIR} > /dev/null 2>&1
fi

# Pre-populate cbdeps
heading "Populating cbdeps..."
case ${PLATFORM} in
  mac*) cbdeps_platform='macos' ;;
  win*) cbdeps_platform='window';;
     *) cbdeps_platform='linux' ;;
esac
for cbdep_ver in ${CBDDEPS_VERSIONS}
  if [ ! -d "${HOME}/.cbdepscache/cbdep/${cbdep_ver}/" ]
  then
    mkdir -p ${HOME}/.cbdepscache/cbdep/${cbdep_ver}/
    cp -aL /escrow/deps/cbdep-*-${cbdeps_platform} ${HOME}/.cbdepscache/cbdep/${cbdep_ver}/
  fi
done

build_cbdep() {
  dep=$1
  tlmsha=$2

  if [ -e ${CACHE}/${dep}*.tgz ]
  then
    echo "Dependency ${dep} already built..."
    return
  fi

  heading "Building dependency ${dep}...."
  cd ${TLMDIR}
  git reset --hard
  git clean -dfx
  git checkout ${tlmsha}

  # Tweak the cbdeps build scripts to "download" the source from our local
  # escrowed copy. Have to re-do this for every dep since we checkout a
  # potentially different SHA each time above.
  shopt -s nullglob
  sed -i.bak \
    -e "s/\(git\|https\):\/\/github.com\/couchbasedeps\/\([^ ]*\)/file:\/\/\/home\/couchbase\/escrow\/deps\/${dep}\/\2/g"
    ${TLMDIR}/deps/packages/CMakeLists.txt \
    ${TLMDIR}/deps/packages/*/CMakeLists.txt \
    ${TLMDIR}/deps/packages/*/*.sh
  shopt -u nullglob
  # Fix the depot_tools entry
  if [ ${dep} == 'v8' ]; then
     sed -i.bak2 -e 's/file:\/\/\/home\/couchbase\/escrow\/deps\/v8\/depot_tools/file:\/\/\/home\/couchbase\/escrow\/deps\/depot_tools\/depot_tools.git/g' ${TLMDIR}/deps/packages/*/*.sh
  fi

  # skip openjdk-rt cbdeps build
  if [ ${dep} == 'openjdk-rt' ]
  then
    rm -f ${TLMDIR}/deps/packages/openjdk-rt/dl_rt_jar.cmake
    touch ${TLMDIR}/deps/packages/openjdk-rt/dl_rt_jar.cmake
  fi

  # Invoke the actual build script
  PACKAGE=${dep} deps/scripts/build-one-cbdep

  echo
  echo "Copying dependency ${dep} to local cbdeps cache..."
  tarball=$( ls ${TLMDIR}/deps/packages/build/deps/${dep}/*/*.tgz )
  cp ${tarball} ${CACHE}
  cp ${tarball/tgz/md5} ${CACHE}/$( basename ${tarball} ).md5
}

# Build all dependencies. The manifest is named after DOCKER_PLATFORM.
for dep in $( cat ${ROOT}/deps/dep_manifest_${DOCKER_PLATFORM}.txt )
do
  DEPS=$(echo ${dep} | sed 's/:/ /')
  echo "Building dep: ${DEPS}"
  build_cbdep $(echo ${dep} | sed 's/:/ /')
done

# Copy in all Go versions.
heading "Copying Golang versions..."
cp -a ${ROOT}/golang/* ${CACHE}

# Finally, build the Couchbase Server package.
heading "Building Couchbase Server ${VERSION} Enterprise Edition..."
${ROOT}/src/cbbuild/scripts/jenkins/couchbase_server/server-linux-build.sh \
  ${PLATFORM} ${VERSION} enterprise 9999

# Remove any "oel6" binaries to avoid confusion
rm -f ${ROOT}/src/couchbase*oel6*rpm

