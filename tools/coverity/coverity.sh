#!/bin/bash

DEF_TOKEN="a3jzBNx469JJc6Jou5DZDA"
DEF_EMAIL="devel@wazuh.com"
DEF_PROJECT="wazuh%2Fwazuh"
DEF_BRANCH="master"
DEF_TARGET="server"
DEF_THREADS=2

OSSEC_TOKEN="3sQ--QTA0tHNvZNG5FH3IQ"
OSSEC_PROJECT="wazuh%2Fossec-wazuh"

if [ -z "$TOKEN" ]
then
    TOKEN=$DEF_TOKEN
fi

if [ -z "$EMAIL" ]
then
    EMAIL=$DEF_EMAIL
fi

if [ -z "$PROJECT" ]
then
    PROJECT=$DEF_PROJECT
fi

if [ -z "$BRANCH" ]
then
    BRANCH=$DEF_BRANCH
fi

if [ -z "$TARGET" ]
then
    TARGET=$DEF_TARGET
fi

if [ -z "$THREADS" ]
then
    THREADS=$DEF_THREADS
fi

getcoverity() {
    if [ ! -f coverity_tool.tgz ]
    then
        wget https://scan.coverity.com/download/linux64 --post-data "token=$TOKEN&project=$PROJECT" -O coverity_tool.tgz || return $?
        rm -rf cov-analysis-linux64*
    fi

    if [ ! -d cov-analysis-linux64* ]
    then
        tar -zxf coverity_tool.tgz || return $?
    fi

    PATH=$PATH:$(realpath cov-analysis-linux64*)/bin
    if [ "$TARGET" = "winagent" ]
    then
        cov-configure --compiler i686-w64-mingw32-gcc --comptype gcc --template
    fi
}

getwazuh() {
    if [ -d wazuh ]
    then
        cd wazuh
        git fetch --tags --depth 1 || exit 1

        if [ -n "$(git tag -l $BRANCH)" ]
        then
            git checkout $BRANCH || exit 1
        else
            git remote set-branches origin $BRANCH && git fetch --depth 1 && git checkout $BRANCH && git reset --hard origin/$BRANCH || exit 1
        fi

        cd ..
    else
        git clone -b $BRANCH --depth 1 https://github.com/wazuh/wazuh.git wazuh || exit 1
    fi
}

build() {
    cd wazuh/src

    VERSION="$(cat VERSION)-r$(cat REVISION)"
    DESCRIPTION="Revision $(cat REVISION)"

    if [ "$TARGET" = "winagent" ]
    then
        ln -s /usr/bin/true /usr/local/bin/makensis
    fi

    rm -rf cov-int
    find external/* > /dev/null 2>&1 || make deps -j$THREADS
    make clean-internals
    make TARGET=$TARGET external COVERITY=YES -j$THREADS
    cov-build --dir cov-int make TARGET=$TARGET COVERITY=YES -j$THREADS
    status=$?

    if [ "$TARGET" = "winagent" ]
    then
        rm -f /usr/local/bin/makensis
    fi

    cd ../..
    return $status
}

upload() {
    if [ -z "$VERSION" ] || [ -z "$DESCRIPTION" ]
    then
        echo "ERROR: Undefined 'VERSION' or 'DESCRIPTION'. You should build first."
        return 1
    fi

    cd wazuh/src
    tar zcf wazuh.tgz cov-int

    curl --form token=$TOKEN \
      --form email=$EMAIL \
      --form file=@wazuh.tgz \
      --form version="$VERSION" \
      --form description="$DESCRIPTION" \
      https://scan.coverity.com/builds?project=$PROJECT

    status=$?
    rm wazuh.tgz
    cd ../..
    echo
    return $status
}

clean() {
    rm -rf cov-analysis-linux64-* coverity_tool.tgz wazuh
}

if [ "${BASH_SOURCE[0]}" = "$0" ]
then

    if [ "$1" = "--ossec" ]
    then
        TOKEN=$OSSEC_TOKEN
        PROJECT=$OSSEC_PROJECT
    fi

    getcoverity && getwazuh && build || exit 1

    echo "Version: $VERSION"
    cd wazuh
    echo "Branch: $(git rev-parse --abbrev-ref HEAD) ($(git rev-parse HEAD))"
    cd ..
    echo "Project: $PROJECT ($TOKEN)"
    echo "Target: $TARGET"
    echo ""

    echo -n "Do you want to upload? [Y/n]: "
    read r

    if [ -z "$r" ] || [[ $r =~ ^[Yy] ]]
    then
        upload
    fi
fi
