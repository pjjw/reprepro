#!/bin/bash

# test some corner cases in updating:
# IgnoreRelease, force, errors, resuming...

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

dodo test ! -f dists
mkdir -p conf test/dists/a/c/source test/test lists

echo "test" > test/test/test.dsc
echo "fake-gz-file" > test/test/test.tar.gz

cat >test/dists/a/c/source/Sources <<EOF
Package: test
Version: 7777
Priority: extra
Section: somewhere
Maintainer: noone
Directory: test
Files:
 $(mdandsize test/test/test.dsc) test.dsc
 $(mdandsize test/test/test.tar.gz) test.tar.gz
EOF

sourcesmd=$(md5 test/dists/a/c/source/Sources)
sourcessize=$(stat -c "%s" test/dists/a/c/source/Sources)
cat > test/dists/a/Release <<EOF
Codename: a
MD5Sum:
 $sourcesmd $sourcessize c/source/Sources
EOF
lzma test/dists/a/c/source/Sources

cat >conf/distributions <<EOF
Codename: t
Architectures: source
Components: c
Update: u
EOF

cat >conf/updates <<EOF
Name: u
Method: copy:$WORKDIR/test
VerifyRelease: blindtrust
Suite: a
EOF

testrun - -b . update 3<<EOF
stderr
-v6*=aptmethod start 'copy:$WORKDIR/test/dists/a/Release'
-v1*=aptmethod got 'copy:$WORKDIR/test/dists/a/Release'
*=aptmethod error receiving 'copy:$WORKDIR/test/dists/a/c/source/Sources':
='Failed to stat - stat (2 No such file or directory)'
='Failed to stat - stat (2: No such file or directory)'
-v0*=There have been errors!
stdout
-v2*=Created directory "./db"
returns 255
EOF

cat >>conf/updates <<EOF
DownloadListsAs: .lzma
EOF

testrun - -b . update 3<<EOF
stderr
-v6*=aptmethod start 'copy:$WORKDIR/test/dists/a/Release'
-v1*=aptmethod got 'copy:$WORKDIR/test/dists/a/Release'
*=Error: './lists/u_a_Release' only lists unrequested compressions of 'c/source/Sources'.
*=Try changing your DownloadListsAs to request e.g. '.'.
-v0*=There have been errors!
returns 255
EOF
ed -s conf/updates <<EOF
g/^DownloadListsAs:/s/.lzma/force.gz force.lzma/
w
q
EOF

testrun - -b . update 3<<EOF
stderr
-v6*=aptmethod start 'copy:$WORKDIR/test/dists/a/Release'
-v1*=aptmethod got 'copy:$WORKDIR/test/dists/a/Release'
*=aptmethod error receiving 'copy:$WORKDIR/test/dists/a/c/source/Sources.gz':
='Failed to stat - stat (2 No such file or directory)'
='Failed to stat - stat (2: No such file or directory)'
-v6*=aptmethod start 'copy:${WORKDIR}/test/dists/a/c/source/Sources.lzma'
-v1*=aptmethod got 'copy:${WORKDIR}/test/dists/a/c/source/Sources.lzma'
-v2*=Uncompress './lists/u_a_c_Sources.lzma' into './lists/u_a_c_Sources' using '/usr/bin/unlzma'...
stdout
-v0*=Calculating packages to get...
-v3*=  processing updates for 't|c|source'
-v5*=  reading './lists/u_a_c_Sources'
-v2*=Created directory "./pool"
-v2*=Created directory "./pool/c"
-v2*=Created directory "./pool/c/t"
-v2*=Created directory "./pool/c/t/test"
stderr
-v6*=aptmethod start 'copy:${WORKDIR}/test/test/test.dsc'
-v1*=aptmethod got 'copy:${WORKDIR}/test/test/test.dsc'
-v6*=aptmethod start 'copy:${WORKDIR}/test/test/test.tar.gz'
-v1*=aptmethod got 'copy:${WORKDIR}/test/test/test.tar.gz'
stdout
-v0*=Getting packages...
-d1*=db: 'pool/c/t/test/test.dsc' added to checksums.db(pool).
-d1*=db: 'pool/c/t/test/test.tar.gz' added to checksums.db(pool).
-v1*=Shutting down aptmethods...
-v0*=Installing (and possibly deleting) packages...
-d1*=db: 'test' added to packages.db(t|c|source).
-v0*=Exporting indices...
-v2*=Created directory "./dists"
-v2*=Created directory "./dists/t"
-v2*=Created directory "./dists/t/c"
-v2*=Created directory "./dists/t/c/source"
-v6*= looking for changes in 't|c|source'...
-v6*=  creating './dists/t/c/source/Sources' (gzipped)
EOF

# test what happens if some compression is forces (i.e. not listed
# in the Release file), but the downloaded file is not correct:

ed -s test/dists/a/Release <<EOF
,s/^ [^ ]*/ 00000000000000000000000000000000/
w
q
EOF

testrun - -b . update 3<<EOF
stderr
-v6*=aptmethod start 'copy:$WORKDIR/test/dists/a/Release'
-v1*=aptmethod got 'copy:$WORKDIR/test/dists/a/Release'
*=aptmethod error receiving 'copy:$WORKDIR/test/dists/a/c/source/Sources.gz':
='Failed to stat - stat (2 No such file or directory)'
='Failed to stat - stat (2: No such file or directory)'
-v6*=aptmethod start 'copy:${WORKDIR}/test/dists/a/c/source/Sources.lzma'
-v1*=aptmethod got 'copy:${WORKDIR}/test/dists/a/c/source/Sources.lzma'
-v2*=Uncompress './lists/u_a_c_Sources.lzma' into './lists/u_a_c_Sources' using '/usr/bin/unlzma'...
*=Wrong checksum of uncompressed content of './lists/u_a_c_Sources.lzma':
*=md5 expected: 00000000000000000000000000000000, got: $sourcesmd
-v0*=There have been errors!
returns 254
EOF

rm test/dists/a/Release

testrun - -b . update 3<<EOF
stderr
*=aptmethod error receiving 'copy:$WORKDIR/test/dists/a/Release':
='Failed to stat - stat (2 No such file or directory)'
='Failed to stat - stat (2: No such file or directory)'
-v0*=There have been errors!
returns 255
EOF

echo "IgnoreRelease: Yes" >> conf/updates

testrun - -b . update 3<<EOF
stderr
*=aptmethod error receiving 'copy:$WORKDIR/test/dists/a/c/source/Sources.gz':
='Failed to stat - stat (2 No such file or directory)'
='Failed to stat - stat (2: No such file or directory)'
-v6*=aptmethod start 'copy:${WORKDIR}/test/dists/a/c/source/Sources.lzma'
-v1*=aptmethod got 'copy:${WORKDIR}/test/dists/a/c/source/Sources.lzma'
-v2*=Uncompress './lists/u_a_c_Sources.lzma' into './lists/u_a_c_Sources' using '/usr/bin/unlzma'...
stdout
-v0*=Calculating packages to get...
-v3*=  processing updates for 't|c|source'
-v5*=  reading './lists/u_a_c_Sources'
EOF

rm -r conf db test lists pool dists
testsuccess
