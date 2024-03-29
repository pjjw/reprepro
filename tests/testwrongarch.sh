#!/bin/bash

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

mkdir conf
cat > conf/distributions <<EOF
Codename: test
Architectures: a1 a2 source
Components: main
Update: update
EOF
cat > conf/updates <<EOF
Name: update
Architectures: a>a2 source
Suite: test
Method: file:${WORKDIR}/test
IgnoreRelease: yes
EOF
mkdir test
mkdir test/dists
mkdir test/dists/test
mkdir test/dists/test/main
mkdir test/dists/test/main/binary-a
mkdir test/dists/test/main/source

cat > test/dists/test/main/binary-a/Packages <<EOF
Package: fake1
Version: 0a
Architecture: a
Filename: filename
Size: 1
MD5sum: 1111111111111111

Package: fake2
Version: 2all
Architecture: all
Filename: filename
Size: 1
MD5sum: 1111111111111111
EOF
cat > test/dists/test/main/source/Sources <<EOF
Package: fake1
Version: 0s
Files:
 1111111111111111 1 somefile

Package: fake2
Version: 2s
Files:
 1111111111111111 1 somefile
EOF

testrun - dumpupdate 3<<EOF
stderr
*=aptmethod error receiving 'file:${WORKDIR}/test/dists/test/main/binary-a/Packages.gz':
*='<File not there, apt-method suggests '${WORKDIR}/test/dists/test/main/binary-a/Packages' instead>'
='File not found'
*=aptmethod error receiving 'file:${WORKDIR}/test/dists/test/main/binary-a/Packages.bz2':
*=aptmethod error receiving 'file:${WORKDIR}/test/dists/test/main/source/Sources.gz':
*='<File not there, apt-method suggests '${WORKDIR}/test/dists/test/main/source/Sources' instead>'
*=aptmethod error receiving 'file:${WORKDIR}/test/dists/test/main/source/Sources.bz2':
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/main/binary-a/Packages'
-v2*=Copy file '${WORKDIR}/test/dists/test/main/binary-a/Packages' to './lists/update_test_main_a_Packages'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/main/source/Sources'
-v2*=Copy file '${WORKDIR}/test/dists/test/main/source/Sources' to './lists/update_test_main_Sources'...
stdout
-v2*=Created directory "./db"
-v2*=Created directory "./lists"
*=Updates needed for 'test|main|source':
*=add 'fake1' - '0s' 'update'
*=add 'fake2' - '2s' 'update'
*=Updates needed for 'test|main|a2':
*=add 'fake2' - '2all' 'update'
EOF

rm -r conf lists test db
testsuccess
