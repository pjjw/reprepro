#!/bin/bash

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

mkdir conf
cat >conf/distributions <<EOF
Codename: test
Architectures: $FAKEARCHITECTURE source
Components: all

Codename: copy
Architectures: $FAKEARCHITECTURE source
Components: all
Pull: rule
EOF
touch conf/updates
cat >conf/pulls <<EOF
Name: rule
From: test
EOF
cat >conf/incoming <<EOF
Name: i
Tempdir: tmp
Incomingdir: i
Default: test
EOF
cat >conf/options <<EOF
onlysmalldeletes
EOF

mkdir i
cd i
for i in $(seq 1 40) ; do
PACKAGE=a$i EPOCH="" VERSION=$i REVISION="" SECTION="many" genpackage.sh
mv test.changes a$i.changes
done
cd ..

cat > pi.rules <<EOF
=Data seems not to be signed trying to use directly...
stdout
-v2*=Created directory "./db"
-v2*=Created directory "./tmp"
-v2*=Created directory "./pool"
-v2*=Created directory "./pool/all"
-v2*=Created directory "./pool/all/a"
-v0*=Exporting indices...
-v2*=Created directory "./dists"
-v2*=Created directory "./dists/test"
-v2*=Created directory "./dists/test/all"
-v2*=Created directory "./dists/test/all/binary-${FAKEARCHITECTURE}"
-v6*= looking for changes in 'test|all|${FAKEARCHITECTURE}'...
-v6*=  creating './dists/test/all/binary-${FAKEARCHITECTURE}/Packages' (uncompressed,gzipped)
-v2*=Created directory "./dists/test/all/source"
-v6*= looking for changes in 'test|all|source'...
-v6*=  creating './dists/test/all/source/Sources' (gzipped)
EOF

for i in $(seq 1 40) ; do
cat >>pi.rules <<EOF
-v2*=Created directory "./pool/all/a/a$i"
-d1*=db: 'pool/all/a/a${i}/a${i}_${i}.dsc' added to checksums.db(pool).
-d1*=db: 'pool/all/a/a${i}/a${i}_${i}.tar.gz' added to checksums.db(pool).
-d1*=db: 'pool/all/a/a${i}/a${i}_${i}_${FAKEARCHITECTURE}.deb' added to checksums.db(pool).
-d1*=db: 'pool/all/a/a${i}/a${i}-addons_${i}_all.deb' added to checksums.db(pool).
-d1*=db: 'a${i}' added to packages.db(test|all|source).
-d1*=db: 'a${i}' added to packages.db(test|all|${FAKEARCHITECTURE}).
-d1*=db: 'a${i}-addons' added to packages.db(test|all|${FAKEARCHITECTURE}).
-v1*=deleting './i/a${i}.changes'...
-v1*=deleting './i/a${i}_${i}.dsc'...
-v1*=deleting './i/a${i}_${i}.tar.gz'...
-v1*=deleting './i/a${i}_${i}_${FAKEARCHITECTURE}.deb'...
-v1*=deleting './i/a${i}-addons_${i}_all.deb'...
EOF
done

testrun pi -b . processincoming i
dodo rmdir i
rm pi.rules

cat >pull.rules <<EOF
stdout
-v0*=Calculating packages to pull...
-v3*=  pulling into 'copy|all|source'
-v5*=  looking what to get from 'test|all|source'
-v3*=  pulling into 'copy|all|${FAKEARCHITECTURE}'
-v5*=  looking what to get from 'test|all|${FAKEARCHITECTURE}'
-v0*=Installing (and possibly deleting) packages...
-v0*=Exporting indices...
-v2*=Created directory "./dists/copy"
-v2*=Created directory "./dists/copy/all"
-v2*=Created directory "./dists/copy/all/binary-${FAKEARCHITECTURE}"
-v6*= looking for changes in 'copy|all|${FAKEARCHITECTURE}'...
-v6*=  creating './dists/copy/all/binary-${FAKEARCHITECTURE}/Packages' (uncompressed,gzipped)
-v2*=Created directory "./dists/copy/all/source"
-v6*= looking for changes in 'copy|all|source'...
-v6*=  creating './dists/copy/all/source/Sources' (gzipped)
EOF

for i in $(seq 1 40) ; do
cat >>pull.rules <<EOF
-d1*=db: 'a${i}' added to packages.db(copy|all|source).
-d1*=db: 'a${i}' added to packages.db(copy|all|${FAKEARCHITECTURE}).
-d1*=db: 'a${i}-addons' added to packages.db(copy|all|${FAKEARCHITECTURE}).
EOF
done

testrun pull -b . pull
rm pull.rules

sed -e 's/Pull: rule/Pull: -/' -i conf/distributions

testrun - -b . pull 3<<EOF
stdout
-v0*=Calculating packages to pull...
-v3*=  pulling into 'copy|all|source'
-v5*=  marking everything to be deleted
-v3*=  pulling into 'copy|all|${FAKEARCHITECTURE}'
#-v5*=  marking everything to be deleted
-v0*=Installing (and possibly deleting) packages...
stderr
*=Not processing 'copy' because of --onlysmalldeletes
EOF

sed -e 's/Pull: -/Update: -/' -i conf/distributions
testrun - -b . --noskipold update 3<<EOF
stdout
-v2*=Created directory "./lists"
-v0*=Calculating packages to get...
-v3*=  processing updates for 'copy|all|source'
-v5*=  marking everything to be deleted
-v3*=  processing updates for 'copy|all|${FAKEARCHITECTURE}'
#-v5*=  marking everything to be deleted
stderr
*=Not processing updates for 'copy' because of --onlysmalldeletes!
EOF

rm -r conf
rm -r db
rm -r pool
rm -r dists
rmdir tmp
rmdir lists
testsuccess
