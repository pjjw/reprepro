#!/bin/bash

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

# testing with Sources, as they are easier to generate...

if test -e "$RREDTOOL" ; then

mkdir conf
cat > conf/distributions <<EOF
Codename: test
Architectures: source
Components: main
DscIndices: Sources Release . .gz $RREDTOOL
EOF

# Section and Priority in .dsc are a reprepro extension...

echo "Dummy file" > test_1.tar.gz
cat > test_1.dsc <<EOF
Format: 1.0
Source: test
Binary: more or less
Architecture: who knows what
Version: 1
Section: test
Priority: extra
Maintainer: Guess Who <its@me>
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaa some lines to make it long enough aaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
X-Data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Files:
 $(mdandsize test_1.tar.gz) test_1.tar.gz
EOF
echo "Dummy file" > pre_1.tar.gz
cat > pre_1.dsc <<EOF
Format: 1.0
Source: pre
Binary: pre
Architecture: all
Version: 1
Maintainer: Guess Who <its@me>
Section: pre
Priority: extra
Files:
 $(mdandsize pre_1.tar.gz) pre_1.tar.gz
EOF
echo "New file" > pre_2.tar.gz
cat > pre_2.dsc <<EOF
Format: 1.0
Source: pre
Binary: pre
Architecture: all
Version: 2
Maintainer: Guess Who <its@me>
Section: pre
Priority: extra
Files:
 $(mdandsize pre_2.tar.gz) pre_2.tar.gz
EOF
echo "Even newer" > pre_3.tar.gz
cat > pre_3.dsc <<EOF
Format: 1.0
Source: pre
Binary: pre
Architecture: all
Version: 3
Maintainer: Guess Who <its@me>
Section: pre
Priority: extra
Files:
 $(mdandsize pre_3.tar.gz) pre_3.tar.gz
EOF

mkdir old
testrun - includedsc test test_1.dsc 3<<EOF
-v1*=test_1.dsc: component guessed as 'main'
-v6=Data seems not to be signed trying to use directly...
stdout
-v2*=Created directory "./db"
-v2*=Created directory "./pool"
-v2*=Created directory "./pool/main"
-v2*=Created directory "./pool/main/t"
-v2*=Created directory "./pool/main/t/test"
-d1*=db: 'pool/main/t/test/test_1.dsc' added to checksums.db(pool).
-d1*=db: 'pool/main/t/test/test_1.tar.gz' added to checksums.db(pool).
-d1*=db: 'test' added to packages.db(test|main|source).
-v0*=Exporting indices...
-v2*=Created directory "./dists"
-v2*=Created directory "./dists/test"
-v2*=Created directory "./dists/test/main"
-v2*=Created directory "./dists/test/main/source"
-v6*= looking for changes in 'test|main|source'...
-v6*=  creating './dists/test/main/source/Sources' (uncompressed,gzipped,script: rredtool)
EOF
dodo cp dists/test/main/source/Sources old/0
dodo test "!" -e dists/test/main/source/Sources.diff
testrun - includedsc test pre_1.dsc 3<<EOF
-v1*=pre_1.dsc: component guessed as 'main'
-v6=Data seems not to be signed trying to use directly...
stdout
-v2*=Created directory "./pool/main/p"
-v2*=Created directory "./pool/main/p/pre"
-d1*=db: 'pool/main/p/pre/pre_1.dsc' added to checksums.db(pool).
-d1*=db: 'pool/main/p/pre/pre_1.tar.gz' added to checksums.db(pool).
-d1*=db: 'pre' added to packages.db(test|main|source).
-v0*=Exporting indices...
-v6*= looking for changes in 'test|main|source'...
-v6*=  replacing './dists/test/main/source/Sources' (uncompressed,gzipped,script: rredtool)
EOF
dodo cp dists/test/main/source/Sources old/1
dodo test -f dists/test/main/source/Sources.diff/Index
testrun - includedsc test pre_2.dsc 3<<EOF
-v1*=pre_2.dsc: component guessed as 'main'
-v6=Data seems not to be signed trying to use directly...
stdout
-d1*=db: 'pool/main/p/pre/pre_2.dsc' added to checksums.db(pool).
-d1*=db: 'pool/main/p/pre/pre_2.tar.gz' added to checksums.db(pool).
-d1*=db: 'pre' removed from packages.db(test|main|source).
-d1*=db: 'pre' added to packages.db(test|main|source).
-v0*=Exporting indices...
-v0*=Deleting files no longer referenced...
-v1*=deleting and forgetting pool/main/p/pre/pre_1.dsc
-d1*=db: 'pool/main/p/pre/pre_1.dsc' removed from checksums.db(pool).
-v1*=deleting and forgetting pool/main/p/pre/pre_1.tar.gz
-d1*=db: 'pool/main/p/pre/pre_1.tar.gz' removed from checksums.db(pool).
-v6*= looking for changes in 'test|main|source'...
-v6*=  replacing './dists/test/main/source/Sources' (uncompressed,gzipped,script: rredtool)
EOF
dodo cp dists/test/main/source/Sources old/2
dodo test -f dists/test/main/source/Sources.diff/Index
testrun - includedsc test pre_3.dsc 3<<EOF
-v1*=pre_3.dsc: component guessed as 'main'
-v6=Data seems not to be signed trying to use directly...
stdout
-d1*=db: 'pool/main/p/pre/pre_3.dsc' added to checksums.db(pool).
-d1*=db: 'pool/main/p/pre/pre_3.tar.gz' added to checksums.db(pool).
-d1*=db: 'pre' removed from packages.db(test|main|source).
-d1*=db: 'pre' added to packages.db(test|main|source).
-v0*=Exporting indices...
-v0*=Deleting files no longer referenced...
-v1*=deleting and forgetting pool/main/p/pre/pre_2.dsc
-d1*=db: 'pool/main/p/pre/pre_2.dsc' removed from checksums.db(pool).
-v1*=deleting and forgetting pool/main/p/pre/pre_2.tar.gz
-d1*=db: 'pool/main/p/pre/pre_2.tar.gz' removed from checksums.db(pool).
-v6*= looking for changes in 'test|main|source'...
-v6*=  replacing './dists/test/main/source/Sources' (uncompressed,gzipped,script: rredtool)
EOF
dodo cp dists/test/main/source/Sources old/3
dodo test -f dists/test/main/source/Sources.diff/Index

(cd dists/test/main/source/Sources.diff/ && ls *.gz) | sort |sed -e 's/\.gz$//' > patches

cat > results.expected <<EOF
SHA1-Current: $(sha1 old/3)
SHA1-History:
EOF
i=0
for p in $(cat patches) ; do
cat >> results.expected <<EOF
 $(sha1and7size old/$i) ${p}
EOF
i=$((i+1))
done
cat >> results.expected <<EOF
SHA1-Patches:
EOF
for p in $(cat patches) ; do
	dodo gunzip dists/test/main/source/Sources.diff/${p}.gz
cat >> results.expected <<EOF
 $(sha1and7size dists/test/main/source/Sources.diff/${p}) ${p}
EOF
done
cat >> results.expected <<EOF
X-Patch-Precedence: merged
EOF

dodiff results.expected dists/test/main/source/Sources.diff/Index

i=1
for p in $(cat patches) ; do
	cp dists/test/main/source/Sources.diff/$p $i.diff
	i=$((i+1))
done
cat > results.expected << EOF
1c
Package: pre
Format: 1.0
Binary: pre
Architecture: all
Version: 3
Maintainer: Guess Who <its@me>
Priority: extra
Section: pre
Directory: pool/main/p/pre
Files: 
 $(mdandsize pre_3.dsc) pre_3.dsc
 $(mdandsize pre_3.tar.gz) pre_3.tar.gz
Checksums-Sha1: 
 $(sha1andsize pre_3.dsc) pre_3.dsc
 $(sha1andsize pre_3.tar.gz) pre_3.tar.gz
Checksums-Sha256: 
 $(sha2andsize pre_3.dsc) pre_3.dsc
 $(sha2andsize pre_3.tar.gz) pre_3.tar.gz

Package: test
.
EOF
dodiff results.expected 1.diff
rm 1.diff
cat > results.expected << EOF
17,18c
 $(sha2andsize pre_3.dsc) pre_3.dsc
 $(sha2andsize pre_3.tar.gz) pre_3.tar.gz
.
14,15c
 $(sha1andsize pre_3.dsc) pre_3.dsc
 $(sha1andsize pre_3.tar.gz) pre_3.tar.gz
.
11,12c
 $(mdandsize pre_3.dsc) pre_3.dsc
 $(mdandsize pre_3.tar.gz) pre_3.tar.gz
.
5c
Version: 3
.
EOF
dodiff results.expected 2.diff
rm 2.diff
dodiff results.expected 3.diff
rm 3.diff
cat > results.expected << EOF
1c
Package: pre
.
EOF
dodiff results.expected 4.diff
rm 4.diff

rm -r old db pool conf dists pre_*.dsc pre_*.tar.gz test_1.dsc test_1.tar.gz  results.expected patches

else
echo
echo
echo
echo
echo "WARNING: $RREDTOOL does not exists. cannot test diff generation"
echo
echo
echo
echo
echo
fi

testsuccess
