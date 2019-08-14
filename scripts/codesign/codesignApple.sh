#!/bin/bash -ex

#
# REMEMBER TO ALWAYS PRESERVE SYMLINKS WHEN ZIP and UNZIP
#
# Verification steps after codesign
# 1. spctl -avvvv pkg_name.app
#    Results "accepted" and Couchbase ID must be present
# 2. codesign -dvvvv pkg_name.app
#    Sealed resource must be version 2
# 3. Best to upload to another website (latestbuilds), download from there and rerun step #1 and #2
#
#

function usage
    {
    echo "Incorrect parameters..."
    echo -e "\nUsage:  ${0}   version   builld_num   edition    OSX (eg. elcaptian) [1 = download package]\n\n"
    }

if [[ "$#" < 2 ]] ; then usage ; exit DEAD ; fi

# enable nocasematch
shopt -s nocasematch

PKG_VERSION=${1}  # Product Version

PKG_BUILD_NUM=${2}  # Build Number

EDITION=${3} # enterprise vs community

OSX=${4} # macos vs elcapitan

DOWNLOAD_NEW_PKG=${5}  # Get new build

ARCHITECTURE='x86_64'

result="rejected"

PKG_URL=http://latestbuilds.service.couchbase.com/builds/latestbuilds/${PRODUCT}/zz-versions/${PKG_VERSION}/${PKG_BUILD_NUM}
PKG_NAME_US=couchbase-server-${EDITION}_${PKG_VERSION}-${PKG_BUILD_NUM}-${OSX}_${ARCHITECTURE}-unsigned.zip
PKG_DIR=couchbase-server-${EDITION}_${PKG_VERSION}

if [[ ${DOWNLOAD_NEW_PKG} ]]
then
    curl -O ${PKG_URL}/${PKG_NAME_US}

    if [[ -d ${PKG_DIR} ]] ; then rm -rf ${PKG_DIR} ; fi
    if [[ -e ${PKG_NAME_US} ]]
    then
        unzip -qq  ${PKG_NAME_US}
    else
        echo ${PKG_NAME_US} not found!
        exit 1
    fi
fi

if [[ -d ${PKG_DIR} ]]
then
    pushd ${PKG_DIR}
else
    mkdir ${PKG_DIR}
    mv *.app ${PKG_DIR}
    mv README.txt ${PKG_DIR}
    pushd ${PKG_DIR}
fi

install_name_tool -change /Users/jenkins/jenkins/workspace/cbdeps-platform-build-old/deps/packages/build/install/lib/libpcre.1.dylib @rpath/libpcre.1.dylib Couchbase\ Server.app/Contents/Resources/couchbase-core/lib/libpcrecpp.dylib
install_name_tool -change /Users/jenkins/jenkins/workspace/cbdeps-platform-build-old/deps/packages/build/install/lib/libpcre.1.dylib @rpath/libpcre.1.dylib Couchbase\ Server.app/Contents/Resources/couchbase-core/lib/libpcreposix.dylib

install_name_tool -change /Users/jenkins/jenkins/workspace/cbdeps-platform-build-old/deps/packages/build/install/lib/libpcre.1.dylib @rpath/libpcre.1.dylib  Couchbase\ Server.app/Contents/Resources/couchbase-core/bin/pcregrep
install_name_tool -change /Users/jenkins/jenkins/workspace/cbdeps-platform-build-old/deps/packages/build/install/lib/libpcreposix.0.dylib  @rpath/libpcreposix.dylib Couchbase\ Server.app/Contents/Resources/couchbase-core/bin/pcregrep

install_name_tool -change  /Users/jenkins/jenkins/workspace/cbdeps-platform-build-old/deps/packages/build/install/lib/libpcre.1.dylib @rpath/libpcre.1.dylib Couchbase\ Server.app/Contents/Resources/couchbase-core/bin/pcretest
install_name_tool -change   /Users/jenkins/jenkins/workspace/cbdeps-platform-build-old/deps/packages/build/install/lib/libpcreposix.0.dylib  @rpath/libpcreposix.dylib Couchbase\ Server.app/Contents/Resources/couchbase-core/bin/pcretest

echo ------- Unlocking keychain -----------
set +x
security unlock-keychain -p `cat ~/.ssh/security-password.txt` ${HOME}/Library/Keychains/login.keychain
set -x

echo -------- Must sign Sparkle framework all versions ----------
sign_flags="--force --deep --strict --timestamp --verbose --options runtime --preserve-metadata=identifier,entitlements,requirements"
java_sign_flags="--force --deep --strict --timestamp --verbose --options runtime --entitlements ${WORKSPACE}/build/scripts/codesign/java.entitlements"
echo options: $sign_flags -----
codesign $sign_flags --sign "Developer ID Application: Couchbase, Inc" Couchbase\ Server.app/Contents/Frameworks/Sparkle.framework/Versions/A/Sparkle
codesign $sign_flags --sign "Developer ID Application: Couchbase, Inc" Couchbase\ Server.app/Contents/Frameworks/Sparkle.framework/Versions/A

codesign $sign_flags --sign "Developer ID Application: Couchbase, Inc" Couchbase\ Server.app/Contents/Frameworks/Sparkle.framework/Versions/Current/Sparkle
codesign $sign_flags --sign "Developer ID Application: Couchbase, Inc" Couchbase\ Server.app/Contents/Frameworks/Sparkle.framework/Versions/Current

echo -------- Must sign exe/zip/jar binaries for notarization ----------
codesign $sign_flags --sign "Developer ID Application: Couchbase, Inc" Couchbase\ Server.app/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/Autoupdate
cd Couchbase\ Server.app
find Contents/Resources/couchbase-core/bin Contents/Resources/couchbase-core/lib  -type f -exec file $i {} \; | egrep -i 'executable|archive|shared' >> ../exe_libs_tmp.txt
cat ../exe_libs_tmp.txt | awk -F':' '{print $1}' > ../exe_libs.txt
for fl in `cat ../exe_libs.txt`; do echo $fl;  codesign $sign_flags  --sign "Developer ID Application: Couchbase, Inc" $fl ; done

echo -------- Sign jdk binaries with java.entitlements for notarization ----------
JAVA_FILES='Contents/Resources/couchbase-core/lib/cbas/repo/netty-all-4.1.32.Final.jar
Contents/Resources/couchbase-core/lib/cbas/repo/netty-tcnative-boringssl-static-2.0.20.Final.jar
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/java.base.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/java.desktop.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/java.instrument.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/java.management.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/java.prefs.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/java.rmi.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/java.scripting.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/java.security.jgss.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/java.smartcardio.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.aot.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.attach.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.compiler.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.crypto.cryptoki.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.crypto.ec.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.hotspot.agent.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.jartool.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.javadoc.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.jcmd.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.jconsole.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.jdeps.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.jdi.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.jdwp.agent.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.jlink.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.jshell.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.jstatd.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.management.agent.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.management.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.net.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.pack.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.rmic.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.scripting.nashorn.shell.jmod
Contents/Resources/couchbase-core/lib/cbas/runtime/jmods/jdk.security.auth.jmod'
for fl in ${JAVA_FILES}; do
    mkdir -p tmp
    cd tmp; 7za x ../$fl
    find . -type f -exec file $i {} \; | egrep -i 'executable|archive|shared' > /tmp/k
    for xi in $(cat /tmp/k | awk -F':' '{print $1}'); do codesign $sign_flags --sign "Developer ID Application: Couchbase, Inc" $xi; done
    zip  -qry ../$fl .
    cd ..; rm -rf tmp
done

cd ..

echo --------- Sign Couchbase app last --------------
codesign $sign_flags --sign "Developer ID Application: Couchbase, Inc" Couchbase\ Server.app

popd

# Verify codesigned successfully
spctl -avvvv ${PKG_DIR}/*.app > tmp.txt 2>&1
result=`grep "accepted" tmp.txt | awk '{ print $3 }'`
echo ${result}
if [[ ${result} =~ "accepted" ]]
then
    # Ensure it's actually signed
    if [[ -z $(grep "no usable signature" tmp.txt) ]]
    then
        exit 0
    else
        exit 1
    fi
else
    exit 1
fi
