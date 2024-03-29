#!/bin/bash

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

dodo test ! -d db
mkdir -p conf db pool
cat > conf/distributions <<EOF
Codename: n
Components: c
Architectures: a
EOF
cat > conf/options <<EOF
export never
EOF

echo "fake-deb1" > fake1.deb
echo "fake-deb2" > fake2.deb
echo "fake-deb3" > fake3.deb

fakedeb1md="$(md5 fake1.deb)"
fakedeb2md="$(md5 fake2.deb)"
fakedeb3md="$(md5 fake3.deb)"
fakedeb1sha1="$(sha1 fake1.deb)"
fakedeb2sha1="$(sha1 fake2.deb)"
fakedeb3sha1="$(sha1 fake3.deb)"
fakedeb1sha2="$(sha256 fake1.deb)"
fakedeb2sha2="$(sha256 fake2.deb)"
fakedeb3sha2="$(sha256 fake3.deb)"
fakesize=10

cat > fakeindex <<EOF
Package: fake
Version: 0
Source: pseudo (9999)
Architecture: all
Filename: pool/c/p/pseudo/fake_0_all.deb
Section: base
Priority: extra
Size: $fakesize
MD5Sum: $fakedeb1md
EOF

testrun - -b . -C c -A a -T deb _addpackage n fakeindex fake  3<<EOF
returns 249
stderr
*=Error: package fake version 0 lists file pool/c/p/pseudo/fake_0_all.deb not yet in the pool!
-v0*=There have been errors!
stdout
EOF

mkdir -p pool/c/p/pseudo
cp fake2.deb pool/c/p/pseudo/fake_0_all.deb

testrun - -b . _detect pool/c/p/pseudo/fake_0_all.deb 3<<EOF
stderr
stdout
-d1*=db: 'pool/c/p/pseudo/fake_0_all.deb' added to checksums.db(pool).
-v0*=1 files were added but not used.
-v0*=The next deleteunreferenced call will delete them.
EOF

testrun - -b . -C c -A a -T deb _addpackage n fakeindex fake  3<<EOF
returns 254
stderr
*=File "pool/c/p/pseudo/fake_0_all.deb" is already registered with different checksums!
*=md5 expected: $fakedeb2md, got: $fakedeb1md
*=Error: package fake version 0 lists different checksums than in the pool!
-v0*=There have been errors!
stdout
EOF

testrun - -b . _forget pool/c/p/pseudo/fake_0_all.deb 3<<EOF
stderr
stdout
-d1*=db: 'pool/c/p/pseudo/fake_0_all.deb' removed from checksums.db(pool).
EOF

cp fake1.deb pool/c/p/pseudo/fake_0_all.deb

testrun - -b . _detect pool/c/p/pseudo/fake_0_all.deb 3<<EOF
stderr
stdout
-d1*=db: 'pool/c/p/pseudo/fake_0_all.deb' added to checksums.db(pool).
-v0*=1 files were added but not used.
-v0*=The next deleteunreferenced call will delete them.
EOF

testrun - -b . -C c -A a -T deb _addpackage n fakeindex fake  3<<EOF
stderr
*=Warning: database 'n|c|a' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-d1*=db: 'fake' added to packages.db(n|c|a).
-v1*=Adding 'fake' '0' to 'n|c|a'.
EOF

testrun - -b . checkpool 3<<EOF
stderr
stdout
EOF

testrun - -b . check 3<<EOF
stderr
stdout
-v1*=Checking n...
EOF

cp fake3.deb pool/c/p/pseudo/fake_0_all.deb

testrun - -b . check 3<<EOF
stderr
stdout
-v1*=Checking n...
EOF

testrun - -b . checkpool 3<<EOF
return 254
stderr
*=WRONG CHECKSUMS of './pool/c/p/pseudo/fake_0_all.deb':
*=md5 expected: $fakedeb1md, got: $fakedeb3md
*=sha1 expected: $fakedeb1sha1, got: $fakedeb3sha1
*=sha256 expected: $fakedeb1sha2, got: $fakedeb3sha2
-v0*=There have been errors!
stdout
EOF

testrun - -b . _forget pool/c/p/pseudo/fake_0_all.deb 3<<EOF
stderr
stdout
-d1*=db: 'pool/c/p/pseudo/fake_0_all.deb' removed from checksums.db(pool).
EOF

testrun - -b . _detect pool/c/p/pseudo/fake_0_all.deb 3<<EOF
stderr
stdout
-d1*=db: 'pool/c/p/pseudo/fake_0_all.deb' added to checksums.db(pool).
EOF

testrun - -b . checkpool 3<<EOF
stderr
stdout
EOF

testrun - -b . check 3<<EOF
stdout
-v1*=Checking n...
stderr
*=File "pool/c/p/pseudo/fake_0_all.deb" is already registered with different checksums!
*=md5 expected: $fakedeb3md, got: $fakedeb1md
*=Files are missing for 'fake'!
-v0*=There have been errors!
returns 254
EOF

testrun - -b . _forget pool/c/p/pseudo/fake_0_all.deb 3<<EOF
stderr
stdout
-d1*=db: 'pool/c/p/pseudo/fake_0_all.deb' removed from checksums.db(pool).
EOF

# Correct size but wrong checksum:
testrun - -b . check 3<<EOF
stdout
-v1*=Checking n...
stderr
*=Deleting unexpected file './pool/c/p/pseudo/fake_0_all.deb'!
*=(not in database and wrong in pool)
*= Missing file pool/c/p/pseudo/fake_0_all.deb
*=Files are missing for 'fake'!
-v0*=There have been errors!
returns 249
EOF
# Wrong size:
echo "Tooo long......" > pool/c/p/pseudo/fake_0_all.deb
testrun - -b . check 3<<EOF
stdout
-v1*=Checking n...
stderr
*=Deleting unexpected file './pool/c/p/pseudo/fake_0_all.deb'!
*=(not in database and wrong in pool)
*= Missing file pool/c/p/pseudo/fake_0_all.deb
*=Files are missing for 'fake'!
-v0*=There have been errors!
returns 249
EOF

cp fake1.deb pool/c/p/pseudo/fake_0_all.deb

testrun - -b . check 3<<EOF
stderr
-v0*=Warning: readded existing file 'pool/c/p/pseudo/fake_0_all.deb' mysteriously missing from the checksum database.
stdout
-v1*=Checking n...
-d1*=db: 'pool/c/p/pseudo/fake_0_all.deb' added to checksums.db(pool).
stderr
EOF

testout - -b . _dumpcontents 'n|c|a' 3<<EOF
EOF

cat >results.expected << EOF
'fake' -> 'Package: fake
Version: 0
Source: pseudo (9999)
Architecture: all
Filename: pool/c/p/pseudo/fake_0_all.deb
Section: base
Priority: extra
Size: $fakesize
MD5Sum: $fakedeb1md
'
EOF
dodiff results.expected results
cat results

testrun - -b . _listchecksums 3<<EOF
stdout
*=pool/c/p/pseudo/fake_0_all.deb :1:$fakedeb1sha1 :2:$fakedeb1sha2 $fakedeb1md $fakesize
stderr
EOF

dodo test ! -e dists

rm -r -f db conf pool fake*.deb fakeindex
testsuccess
