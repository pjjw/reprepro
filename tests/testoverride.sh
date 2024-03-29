#!/bin/bash

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

mkdir -p conf dists/{c,d}/{main,component}/{source,binary-${FAKEARCHITECTURE}}
mkdir -p dists/{c,d}/main/{source,binary-abacus}
mkdir -p pool/{main,component}/a/aa pool/{main,component}/b/bb
cat > conf/distributions <<EOF
Codename: c
Components: main component
Architectures: ${FAKEARCHITECTURE} source
# Don't do that at home, kids....
DebIndices: Index .
DscIndices: Index .
DebOverride: override-c-deb
DscOverride: override-c-dsc

Codename: d
Components: main component
Architectures: ${FAKEARCHITECTURE} source
# Don't do that at home, kids....
DebIndices: Index .
DscIndices: Index .
DebOverride: override-d-deb
DscOverride: override-d-dsc
EOF
cat > conf/override-c-deb <<EOF
EOF
cat > conf/override-c-dsc <<EOF
EOF
cat > conf/override-d-deb <<EOF
aa Section component/section
aa Somefield value
aa-addons Section component/addons
a* ShouldNot ShowUp
bb Section base
bb-addons Section addons
b* Section blub
EOF
cat > conf/override-d-dsc <<EOF
a* Section component/section
b? Section base
b? SomeOtherfield somevalue
b* ShouldNot ShowUp
EOF

DISTRI=c PACKAGE=aa EPOCH="" VERSION=1 REVISION="-1" SECTION="section" genpackage.sh
mv test.changes aa.changes
DISTRI=c PACKAGE=bb EPOCH="" VERSION=1 REVISION="-1" SECTION="component/base" genpackage.sh
mv test.changes bb.changes

testrun - --nodelete include c aa.changes 3<<EOF
=Data seems not to be signed trying to use directly...
stdout
-v2*=Created directory "./db"
-d1*=db: 'pool/main/a/aa/aa-addons_1-1_all.deb' added to checksums.db(pool).
-d1*=db: 'pool/main/a/aa/aa_1-1_${FAKEARCHITECTURE}.deb' added to checksums.db(pool).
-d1*=db: 'pool/main/a/aa/aa_1-1.tar.gz' added to checksums.db(pool).
-d1*=db: 'pool/main/a/aa/aa_1-1.dsc' added to checksums.db(pool).
-d1*=db: 'aa-addons' added to packages.db(c|main|${FAKEARCHITECTURE}).
-d1*=db: 'aa' added to packages.db(c|main|${FAKEARCHITECTURE}).
-d1*=db: 'aa' added to packages.db(c|main|source).
-v0*=Exporting indices...
-v6*= looking for changes in 'c|main|${FAKEARCHITECTURE}'...
-v6*=  creating './dists/c/main/binary-${FAKEARCHITECTURE}/Index' (uncompressed)
-v6*= looking for changes in 'c|component|${FAKEARCHITECTURE}'...
-v6*=  creating './dists/c/component/binary-${FAKEARCHITECTURE}/Index' (uncompressed)
-v6*= looking for changes in 'c|main|source'...
-v6*=  creating './dists/c/main/source/Index' (uncompressed)
-v6*= looking for changes in 'c|component|source'...
-v6*=  creating './dists/c/component/source/Index' (uncompressed)
EOF
testrun - --nodelete include c bb.changes 3<<EOF
=Data seems not to be signed trying to use directly...
stdout
-d1*=db: 'pool/component/b/bb/bb-addons_1-1_all.deb' added to checksums.db(pool).
-d1*=db: 'pool/component/b/bb/bb_1-1_${FAKEARCHITECTURE}.deb' added to checksums.db(pool).
-d1*=db: 'pool/component/b/bb/bb_1-1.tar.gz' added to checksums.db(pool).
-d1*=db: 'pool/component/b/bb/bb_1-1.dsc' added to checksums.db(pool).
-d1*=db: 'bb-addons' added to packages.db(c|component|${FAKEARCHITECTURE}).
-d1*=db: 'bb' added to packages.db(c|component|${FAKEARCHITECTURE}).
-d1*=db: 'bb' added to packages.db(c|component|source).
-v0*=Exporting indices...
-v6*= looking for changes in 'c|main|${FAKEARCHITECTURE}'...
-v6*= looking for changes in 'c|component|${FAKEARCHITECTURE}'...
-v6*=  replacing './dists/c/component/binary-${FAKEARCHITECTURE}/Index' (uncompressed)
-v6*= looking for changes in 'c|main|source'...
-v6*= looking for changes in 'c|component|source'...
-v6*=  replacing './dists/c/component/source/Index' (uncompressed)
EOF
ed -s aa.changes <<EOF
g/^Distribution/s/ c/ d/
w
q
EOF
ed -s bb.changes <<EOF
g/^Distribution/s/ c/ d/
w
q
EOF
testrun - --nodelete include d aa.changes 3<<EOF
=Data seems not to be signed trying to use directly...
stdout
-d1*=db: 'pool/component/a/aa/aa-addons_1-1_all.deb' added to checksums.db(pool).
-d1*=db: 'pool/component/a/aa/aa_1-1_${FAKEARCHITECTURE}.deb' added to checksums.db(pool).
-d1*=db: 'pool/component/a/aa/aa_1-1.tar.gz' added to checksums.db(pool).
-d1*=db: 'pool/component/a/aa/aa_1-1.dsc' added to checksums.db(pool).
-d1*=db: 'aa-addons' added to packages.db(d|component|${FAKEARCHITECTURE}).
-d1*=db: 'aa' added to packages.db(d|component|${FAKEARCHITECTURE}).
-d1*=db: 'aa' added to packages.db(d|component|source).
-v0*=Exporting indices...
-v6*= looking for changes in 'd|component|${FAKEARCHITECTURE}'...
-v6*=  creating './dists/d/component/binary-${FAKEARCHITECTURE}/Index' (uncompressed)
-v6*= looking for changes in 'd|main|${FAKEARCHITECTURE}'...
-v6*=  creating './dists/d/main/binary-${FAKEARCHITECTURE}/Index' (uncompressed)
-v6*= looking for changes in 'd|component|source'...
-v6*=  creating './dists/d/component/source/Index' (uncompressed)
-v6*= looking for changes in 'd|main|source'...
-v6*=  creating './dists/d/main/source/Index' (uncompressed)
EOF
testrun - --nodelete include d bb.changes 3<<EOF
=Data seems not to be signed trying to use directly...
stdout
-d1*=db: 'pool/main/b/bb/bb-addons_1-1_all.deb' added to checksums.db(pool).
-d1*=db: 'pool/main/b/bb/bb_1-1_${FAKEARCHITECTURE}.deb' added to checksums.db(pool).
-d1*=db: 'pool/main/b/bb/bb_1-1.tar.gz' added to checksums.db(pool).
-d1*=db: 'pool/main/b/bb/bb_1-1.dsc' added to checksums.db(pool).
-d1*=db: 'bb-addons' added to packages.db(d|main|${FAKEARCHITECTURE}).
-d1*=db: 'bb' added to packages.db(d|main|${FAKEARCHITECTURE}).
-d1*=db: 'bb' added to packages.db(d|main|source).
-v0*=Exporting indices...
-v6*= looking for changes in 'd|component|${FAKEARCHITECTURE}'...
-v6*= looking for changes in 'd|main|${FAKEARCHITECTURE}'...
-v6*=  replacing './dists/d/main/binary-${FAKEARCHITECTURE}/Index' (uncompressed)
-v6*= looking for changes in 'd|component|source'...
-v6*= looking for changes in 'd|main|source'...
-v6*=  replacing './dists/d/main/source/Index' (uncompressed)
EOF

cp dists/c/main/binary-abacus/Index Index.expected
ed -s Index.expected <<EOF
/^Priority:/i
Somefield: value
.
g/Section/s#section#component/addons#
/Section/s#addons#section#
%s/main/component/
w
EOF
dodiff Index.expected dists/d/component/binary-abacus/Index

cp dists/c/component/source/Index Index.expected
ed -s Index.expected <<EOF
/^Priority:/i
SomeOtherfield: somevalue
.
g/Section/s#component/base#base#
%s/component/main/
w
EOF
dodiff Index.expected dists/d/main/source/Index


dodo rm -r aa* bb* pool dists db conf

testsuccess
