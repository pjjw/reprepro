#!/bin/bash

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

mkdir conf
cat > conf/distributions <<EOF
Codename: o
Architectures: a b
Components: e
DebIndices: .
EOF

testrun - -b . export o 3<<EOF
*=Error parsing ./conf/distributions, line 4, column 13: filename for index files expected!
-v0*=There have been errors!
returns 255
EOF

cat > conf/distributions <<EOF
Codename: o
Architectures: a b
Components: e
DebIndices: X .gz .bz2 strange.sh
EOF
cat > conf/strange.sh <<'EOF'
#!/bin/sh
echo hook "$@"
touch "$1/$3.something.new"
echo "$3.something.new" >&3
touch "$1/$3.something.hidden.new"
echo "$3.something.hidden.new." >&3
exit 0
EOF
chmod a+x conf/strange.sh

testrun - -b . export o 3<<EOF
stdout
-v2*=Created directory "./db"
-v1*=Exporting o...
-v2*=Created directory "./dists"
-v2*=Created directory "./dists/o"
-v2*=Created directory "./dists/o/e"
-v2*=Created directory "./dists/o/e/binary-a"
-v6*= exporting 'o|e|a'...
-v6*=  creating './dists/o/e/binary-a/X' (gzipped,bzip2ed,script: strange.sh)
*=hook ./dists/o e/binary-a/X.new e/binary-a/X new
-v2*=Created directory "./dists/o/e/binary-b"
*=hook ./dists/o e/binary-b/X.new e/binary-b/X new
-v6*= exporting 'o|e|b'...
-v6*=  creating './dists/o/e/binary-b/X' (gzipped,bzip2ed,script: strange.sh)
EOF

find dists -type f | sort > results
cat > results.expected <<EOF
dists/o/Release
dists/o/e/binary-a/Release
dists/o/e/binary-a/X.bz2
dists/o/e/binary-a/X.gz
dists/o/e/binary-a/X.something
dists/o/e/binary-a/X.something.hidden
dists/o/e/binary-b/Release
dists/o/e/binary-b/X.bz2
dists/o/e/binary-b/X.gz
dists/o/e/binary-b/X.something
dists/o/e/binary-b/X.something.hidden
EOF
dodiff results.expected results

grep  something dists/o/Release > results || true
cat > results.expected <<EOF
 $(md5releaseline o e/binary-a/X.something)
 $(md5releaseline o e/binary-b/X.something)
 $(sha1releaseline o e/binary-a/X.something)
 $(sha1releaseline o e/binary-b/X.something)
 $(sha2releaseline o e/binary-a/X.something)
 $(sha2releaseline o e/binary-b/X.something)
EOF
dodiff results.expected results

rm -r conf db dists
rm results results.expected
testsuccess
