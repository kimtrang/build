#!/bin/bash

LATESTBUILDS=${1-/home/couchbase/latestbuilds}

remove_glob() {
  glob=$1
  days=$2
  echo Removing ${glob} older than ${days} days...
  find . -name ${glob} -atime +${days} -exec sh -c 'echo > "{}"; rm "{}"' \;
}

# @@@@@@@@@
# Clean up Couchbase Server
# @@@@@@@@@
cd ${LATESTBUILDS}/couchbase-server

# All Windows ".bits" files older than 1 day (only needed for intra-build
# communication)
remove_glob "*windows_amd64-bits.tar" 1

# All MacOS .orig files from codesigning
remove_glob "*macos*.orig" 5

# All debug packages older than 30 days
remove_glob "*debug*" 30
remove_glob "*dbg*" 30
remove_glob "*-PDB.zip" 30

# All Ubuntu 12/14, Debian 8, Centos 6, Suse, Mac, "oel", and Windows builds
# older than 30/60 days
remove_glob "*macos*.zip" 30
remove_glob "*windows*exe" 30
remove_glob "*windows*msi" 60
remove_glob "*ubuntu12.04*.deb" 30
remove_glob "*ubuntu14.04*.deb" 30
remove_glob "*ubuntu16.04*.deb" 30
remove_glob "*debian7*.deb" 60
remove_glob "*debian8*.deb" 30
remove_glob "*centos6*.rpm" 30
remove_glob "*suse11*.rpm" 30
remove_glob "*suse12*.rpm" 30
remove_glob "*oel*.rpm" 30

# All Source tarballs older than 60 days
remove_glob "*source.tar.gz" 60

