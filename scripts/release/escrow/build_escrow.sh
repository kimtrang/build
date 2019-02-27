#!/bin/bash -e
: <<'END'
Pretty much what the ticket says (https://issues.couchbase.com/browse/CBD-2372) ... there's scripting that you're familiar with, but we need a job to run that script against the current source code and then try running a build with the result. Run on at least one Linux platform

It *might* require setting up a dedicated VM for the slave, since it does a bunch of Docker stuff itself - may not work right if the slave itself is a Docker container.
END

# QQQ keep this list somewhere canonical per build
IMAGES="couchbasebuild/server-centos7-build:20181228"
#IMAGES="couchbasebuild/server-amzn2-build:20181228
#couchbasebuild/server-centos7-build:20181228
#couchbasebuild/server-debian8-build:20181228
#couchbasebuild/server-debian9-build:20181228
#couchbasebuild/server-suse11-build:20180713
#couchbasebuild/server-suse15-build:20181228
#couchbasebuild/server-ubuntu16-build:20181228
#couchbasebuild/server-ubuntu18-build:20181228"

# QQQ possibly keep this list somewhere canonical per build also
GOVERS="1.7.6 1.8.3 1.8.5 1.9.6 1.10.3 1.11.4 1.11.5"

# QQQ parameterize?
VERSION=6.5.0
PRODUCT=couchbase-server

# QQQ extract from tlm/deps/packages/boost/CMakeLists.txt
BOOST_MODULES="intrusive assert config core detail functional math move mpl
optional preprocessor static_assert throw_exception type_index
type_traits utility variant"

# QQQ extract from asterix-opt/cmake/Modules/FindCouchbaseJava.cmake
JDKVER=11

# CBDDEPS
CBDDEPS_VERSIONS="0.8.3 0.9.0 0.9.1"

# END normal per-version configuration variables

# Compute list of platforms from Docker image names
# (will need to change this algorithm if we change the
# Docker image naming convention)
PLATFORMS=$(
  perl -e 'print join(" ", map { m@couchbasebuild/server-(.*)-build@ && $1} @ARGV)' $IMAGES
)

heading() {
  echo
  echo ::::::::::::::::::::::::::::::::::::::::::::::::::::
  echo $*
  echo ::::::::::::::::::::::::::::::::::::::::::::::::::::
  echo
}

# Top-level directory; everything to escrow goes in here.
ROOT=`pwd`
ESCROW=${ROOT}/${PRODUCT}-${VERSION}
mkdir -p ${ESCROW}

# Save copies of all Docker build images
echo "Saving Docker images..."
mkdir -p ${ESCROW}/docker_images
cd ${ESCROW}/docker_images
for img in ${IMAGES}
do
  heading "Saving Docker image ${img}"
  echo "... Pulling ${img}..."
  docker pull ${img}
  echo "... Saving local copy of ${img}..."
  output=`basename ${img}`.tar.gz
  if [ ! -s "${output}" ]
  then
    docker save ${img} | gzip > ${output}
  fi
done

# Get the source code
heading "Downloading released source code for ${PRODUCT} ${VERSION}..."
mkdir -p ${ESCROW}/src
cd ${ESCROW}/src
git config --global user.name "Couchbase Build Team"
git config --global user.email "build-team@couchbase.com"
git config --global color.ui false
#repo init -u git://github.com/couchbase/manifest -g all -m released/couchbase-server/${VERSION}.xml
repo init -u git://github.com/couchbase/manifest -g all -m couchbase-server/mad-hatter.xml
repo sync --jobs=6

# Ensure we have git history for 'master' branch of tlm, so we can
# switch to the right cbdeps build steps
( cd tlm && git fetch couchbase refs/heads/master )

# Download all cbdeps source code
mkdir -p ${ESCROW}/deps

get_cbdep_git() {
  local dep=$1

  cd ${ESCROW}/deps
  if [ ! -d ${dep} ]
  then
    heading "Downloading cbdep ${dep} ..."
    # This special approach ensures all remote branches are brought
    # down as well, which ensures in-container-build.sh can also check
    # them out. See https://stackoverflow.com/a/37346281/1425601 .
    mkdir ${dep}
    cd ${dep}
    git clone --bare git://github.com/couchbasedeps/${dep}.git
    git config core.bare false
    git checkout
  fi
}

get_cbddeps2_src() {
  local dep=$1
  local manifest=$2

  cd ${ESCROW}/deps
  if [ ! -d ${dep} ]
  then
    mkdir ${dep}
    cd ${dep}
    heading "Downloading cbdep2 ${dep} ..."
    repo init -u git://github.com/couchbase/manifest -g all -m cbdeps/${dep}/${manifest}
    repo sync --jobs=6
  fi
}

download_cbdep() {
  local dep=$1
  local ver=$2
  local dep_manifest=$3

  if [ "${dep}" = "boost" ]
  then
    # Boost is stored in separate repos; this means copying some logic
    # from tlm/deps/packages/boost, namely the set of repos
    for repo in ${BOOST_MODULES}
    do
      get_cbdep_git boost_${repo}
    done
  # skip openjdk-rt cbdeps build
  elif [[ ${dep} == 'openjdk-rt' ]]; then
    :
  else
    get_cbdep_git ${dep}
  fi

  # Split off the "version" and "build number"
  version=$(echo ${ver} | perl -nle '/^(.*?)(-cb.*)?$/ && print $1')
  cbnum=$(echo ${ver} | perl -nle '/-cb(.*)/ && print $1')
  echo "KIMKIM === version:$version cbnum:$cbnum"

  # Figure out the tlm SHA which builds this dep
  tlmsha=$(
    cd ${ESCROW}/src/tlm &&
    git grep -c "_ADD_DEP_PACKAGE(${dep} ${version} .* ${cbnum})" \
      $(git rev-list --all -- deps/packages/CMakeLists.txt) \
      -- deps/packages/CMakeLists.txt \
    | awk -F: '{ print $1 }' | head -1
  )
  echo "tlmsha: cd ${ESCROW}/src/tlm && git grep -c \"_ADD_DEP_PACKAGE(${dep} ${version} .* ${cbnum})\" \
		git grep -c \"_ADD_DEP_PACKAGE(${dep} ${version} .* ${cbnum})\" \
		-- deps/packages/CMakeLists.txt \
		| awk -F: '{ print $1 }' | head -1"

  if [ -z "${tlmsha}" ]; then
    echo "ERROR: couldn't find tlm SHA for ${dep} ${version} @${cbnum}@"
    exit 1
  fi

  echo "${dep}:${tlmsha}" >> ${dep_manifest}
  echo "${dep}:${tlmsha}"
}

# Determine set of cbdeps used by this build, per platform.
for platform in ${PLATFORMS}
do
  add_packs=$(
    grep ${platform} ${ESCROW}/src/tlm/deps/manifest.cmake |grep -v V2 \
    | awk '{sub(/\(/, "", $2); print $2 ":" $4}'
  )
  #folly_extra_deps="gflags glog"
  gflags_extra_deps="gflags:2.2.1-cb2"
  jemalloc_extra_deps="jemalloc:4.5.0.1-cb1"
  # special case for folly's jemalloc and gflags
  add_packs+=$(echo -e "\n${jemalloc_extra_deps}")
  add_packs+=$(echo -e "\n${gflags_extra_deps}")
  echo "add_packs: $add_packs"
done
  # Download and keep a record of all third-party deps
  dep_manifest=${ESCROW}/deps/dep_manifest_${platform}.txt
  rm -f ${dep_manifest}
  for add_pack in ${add_packs}
  do
    download_cbdep $(echo ${add_pack} | sed 's/:/ /g') ${dep_manifest}
  done

### Ensure rocksdb and folly built last
egrep -v "^rocksdb|^folly" ${dep_manifest} >> ${ESCROW}/deps/dep2.txt
egrep "^rocksdb|^folly" ${dep_manifest} > ${ESCROW}/deps/dep2.txt
mv ${ESCROW}/deps/dep2.txt ${dep_manifest}

### KIM - Need to build cbdeps V2
for platform in ${PLATFORMS}
do
  add_packs_v2=$(
    grep ${platform} ${ESCROW}/src/tlm/deps/manifest.cmake | grep V2 \
    | awk '{sub(/\(/, "", $2); print $2 ":" $5 "-" $7}'
  )
done
echo "add_packs_v2: $add_packs_v2"
# Download and keep a record of all third-party V2 deps
dep_v2_manifest=${ESCROW}/deps/dep_v2_manifest_${platform}.txt
echo "$add_packs_v2" > ${dep_v2_manifest}
for add_pack in ${add_packs_v2}
do
  get_cbddeps2_src $(echo ${add_pack} | sed 's/:.*/ /g') master.xml
done

# Need this tool for v8 build
get_cbdep_git depot_tools

# Copy in pre-packaged JDK
jdkfile=jdk-${JDKVER}_linux-x64_bin.tar.gz
#http://nas-n.mgt.couchbase.com/builds/downloads/jdk/jdk-11_linux-x64_bin.tar.gz
curl -o ${ESCROW}/deps/${jdkfile} http://nas-n.mgt.couchbase.com/builds/downloads/jdk/${jdkfile}

# Copy in cbdep - NEED a for loop to get all platforms
for cbdep_ver in ${CBDDEPS_VERSIONS}
do
  curl -o ${ESCROW}/deps/cbdep-${cbdep_ver}-window http://packages.couchbase.com/cbdep/${cbdep_ver}/cbdep-${cbdep_ver}-window
  curl -o ${ESCROW}/deps/cbdep-${cbdep_ver}-linux http://packages.couchbase.com/cbdep/${cbdep_ver}/cbdep-${cbdep_ver}-linux
  curl -o ${ESCROW}/deps/cbdep-${cbdep_ver}-macos http://packages.couchbase.com/cbdep/${cbdep_ver}/cbdep-${cbdep_ver}-macos
done

:<<'END'
# One unfortunate patch required for flatbuffers to be built with GCC 7
heading "Patching flatbuffers for GCC 7"
cd ${ESCROW}/deps/flatbuffers
git checkout v1.4.0 > /dev/null
if [ $(git rev-parse HEAD) = "eba6b6f7c93cab4b945f1e39d9ef413d51d3711d" ]
then
  git cherry-pick bbb72f0b
  git tag -f v1.4.0
fi
END

heading "Downloading Go installers..."
mkdir -p ${ESCROW}/golang
cd ${ESCROW}/golang
for gover in ${GOVERS}
do
  echo "... Go ${gover}..."
  gofile="go${gover}.linux-amd64.tar.gz"
  if [ ! -e ${gofile} ]
  then
    curl -o ${gofile} http://storage.googleapis.com/golang/${gofile}
  fi
done

heading "Copying build scripts into escrow..."
cd ${ROOT}
cp -a build-one-cbdep templates/* ${ESCROW}
perl -pi -e "s/\@\@VERSION\@\@/${VERSION}/g; s/\@\@PLATFORMS\@\@/${PLATFORMS}/g" \
  ${ESCROW}/README.md ${ESCROW}/build-couchbase-server-from-escrow.sh

heading "Creating escrow tarball (will take some time)..."
cd ${ROOT}
tar czf ${PRODUCT}-${VERSION}.tar.gz ${PRODUCT}-${VERSION}

heading "Done!"
