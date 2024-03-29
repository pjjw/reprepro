#!/bin/bash

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

mkdir conf
mkdir package-1.0
mkdir package-1.0/debian
cat >package-1.0/debian/control <<END
Source: package
Section: sound
Priority: extra
Maintainer: me <me@example.org>
Standards-Version: 0.0

Package: rumsrumsrums
Architecture: all
Description: a package
 .

Package: dumdidum
Architecture: another
Description: a package not build
 .

Package: troettroet
Architecture: $FAKEARCHITECTURE
Description: some test-package
 .
END
cat >package-1.0/debian/changelog <<END
package (1.0-1) test; urgency=critical

  * first version

 -- me <me@example.orgguess@who>  Mon, 01 Jan 1980 01:02:02 +0000
END

dpkg-source -b package-1.0

cat > conf/distributions <<EOF
Codename: bla
Suite: test
Components: main
Architectures: source $FAKEARCHITECTURE another
Tracking: all

Codename: blub
Components: main
Architectures: notinbla
EOF
cat >> conf/options <<EOF
export never
EOF

testrun - includedsc test package_1.0-1.dsc 3<<EOF
stderr
=Data seems not to be signed trying to use directly...
-v1*=package_1.0-1.dsc: component guessed as 'main'
*=Warning: database 'bla|main|source' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-v2*=Created directory "./db"
-v2*=Created directory "./pool"
-v2*=Created directory "./pool/main"
-v2*=Created directory "./pool/main/p"
-v2*=Created directory "./pool/main/p/package"
*=db: 'pool/main/p/package/package_1.0-1.dsc' added to checksums.db(pool).
*=db: 'pool/main/p/package/package_1.0-1.tar.gz' added to checksums.db(pool).
*=db: 'package' added to packages.db(bla|main|source).
*=db: 'package' added to tracking.db(bla).
EOF
rm package_1.0*

testrun - build-needing test another 3<<EOF
stdout
*=package 1.0-1 pool/main/p/package/package_1.0-1.dsc
EOF
testrun - build-needing test $FAKEARCHITECTURE 3<<EOF
stdout
*=package 1.0-1 pool/main/p/package/package_1.0-1.dsc
EOF
testrun - build-needing test source 3<<EOF
stderr
*=Error: Architecture 'source' makes no sense for build-needing!
-v0*=There have been errors!
returns 255
EOF
testrun - build-needing test all 3<<EOF
stderr
*=Error: Architecture 'all' makes no sense for build-needing!
-v0*=There have been errors!
returns 255
EOF
testrun - build-needing test mistake 3<<EOF
stderr
*=Error: Architecture 'mistake' is not known!
-v0*=There have been errors!
returns 255
EOF
testrun - build-needing test notinbla 3<<EOF
stderr
*=Error: Architecture 'notinbla' not found in distribution 'bla'!
-v0*=There have been errors!
returns 255
EOF

mkdir package-1.0/debian/tmp
mkdir package-1.0/debian/tmp/DEBIAN
mkdir -p package-1.0/debian/tmp/usr/share/sounds
touch package-1.0/debian/tmp/usr/share/sounds/krach.wav
cd package-1.0
dpkg-gencontrol -prumsrumsrums
dpkg --build debian/tmp ..
cd ..

testrun - -C main includedeb test rumsrumsrums_1.0-1_all.deb 3<<EOF
stderr
*=Warning: database 'bla|main|${FAKEARCHITECTURE}' was modified but no index file was exported.
*=Warning: database 'bla|main|another' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
*=db: 'pool/main/p/package/rumsrumsrums_1.0-1_all.deb' added to checksums.db(pool).
*=db: 'rumsrumsrums' added to packages.db(bla|main|${FAKEARCHITECTURE}).
*=db: 'rumsrumsrums' added to packages.db(bla|main|another).
EOF

testrun - build-needing test another 3<<EOF
stdout
*=package 1.0-1 pool/main/p/package/package_1.0-1.dsc
EOF
testrun - build-needing test $FAKEARCHITECTURE 3<<EOF
stdout
*=package 1.0-1 pool/main/p/package/package_1.0-1.dsc
EOF

cd package-1.0
dpkg-gencontrol -ptroettroet
dpkg --build debian/tmp ..
cd ..

testrun - -C main includedeb test troettroet_1.0-1_${FAKEARCHITECTURE}.deb 3<<EOF
stderr
*=Warning: database 'bla|main|${FAKEARCHITECTURE}' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
*=db: 'pool/main/p/package/troettroet_1.0-1_${FAKEARCHITECTURE}.deb' added to checksums.db(pool).
*=db: 'troettroet' added to packages.db(bla|main|${FAKEARCHITECTURE}).
EOF

testrun - build-needing test another 3<<EOF
stdout
*=package 1.0-1 pool/main/p/package/package_1.0-1.dsc
EOF
testrun - build-needing test $FAKEARCHITECTURE 3<<EOF
stdout
EOF

# Include a fake .log file to tell reprepro that architecture is done:

echo "There was nothing to do on this architecture!" > package_1.0-1_another.log
echo "package_1.0-1_another.log - -" > package-1.0/debian/files
cd package-1.0
dpkg-genchanges -B > ../package_1.0-1_another.changes
cd ..

testrun - -C main include test package_1.0-1_another.changes 3<<EOF
stderr
=Data seems not to be signed trying to use directly...
*=Ignoring log file: 'package_1.0-1_another.log'!
*=package_1.0-1_another.changes: Not enough files in .changes!
-v0*=There have been errors!
returns 255
EOF

sed -i -e 's/Tracking: all/Tracking: all includelogs/' conf/distributions

testrun - -C main include test package_1.0-1_another.changes 3<<EOF
stderr
=Data seems not to be signed trying to use directly...
stdout
*=db: 'pool/main/p/package/package_1.0-1_another.log' added to checksums.db(pool).
EOF

testrun empty build-needing test another
testrun empty build-needing test $FAKEARCHITECTURE

# TODO: add a new version of that package...
rm -r package-1.0

mkdir onlyonearch-1.0
mkdir onlyonearch-1.0/debian
cat >onlyonearch-1.0/debian/control <<END
Source: onlyonearch
Section: something
Priority: extra
Maintainer: me <me@example.org>
Standards-Version: 0.0

Package: onearch
Architecture: $FAKEARCHITECTURE
Description: some test-onlyonearch
 .
END
cat >onlyonearch-1.0/debian/changelog <<END
onlyonearch (1.0-1) test; urgency=critical

  * first version

 -- me <me@example.orgguess@who>  Mon, 01 Jan 1980 01:02:02 +0000
END
dpkg-source -b onlyonearch-1.0
mkdir onlyonearch-1.0/debian/tmp
mkdir onlyonearch-1.0/debian/tmp/DEBIAN
mkdir -p onlyonearch-1.0/debian/tmp/usr/bin
touch onlyonearch-1.0/debian/tmp/usr/bin/program
cd onlyonearch-1.0
dpkg-gencontrol -ponearch
dpkg --build debian/tmp ..
cd ..
rm -r onlyonearch-1.0

testrun - --delete includedsc test onlyonearch_1.0-1.dsc 3<<EOF
stderr
=Data seems not to be signed trying to use directly...
-v1*=onlyonearch_1.0-1.dsc: component guessed as 'main'
*=Warning: database 'bla|main|source' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-v2*=Created directory "./pool/main/o"
-v2*=Created directory "./pool/main/o/onlyonearch"
-d1*=db: 'pool/main/o/onlyonearch/onlyonearch_1.0-1.dsc' added to checksums.db(pool).
-d1*=db: 'pool/main/o/onlyonearch/onlyonearch_1.0-1.tar.gz' added to checksums.db(pool).
-d1*=db: 'onlyonearch' added to packages.db(bla|main|source).
-d1*=db: 'onlyonearch' added to tracking.db(bla).
EOF

testrun empty build-needing test another
testrun - build-needing test $FAKEARCHITECTURE 3<<EOF
stdout
*=onlyonearch 1.0-1 pool/main/o/onlyonearch/onlyonearch_1.0-1.dsc
EOF

testrun - --delete -C main includedeb test onearch_1.0-1_${FAKEARCHITECTURE}.deb 3<<EOF
stderr
*=Warning: database 'bla|main|${FAKEARCHITECTURE}' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-d1*=db: 'pool/main/o/onlyonearch/onearch_1.0-1_${FAKEARCHITECTURE}.deb' added to checksums.db(pool).
-d1*=db: 'onearch' added to packages.db(bla|main|${FAKEARCHITECTURE}).
EOF

testrun empty build-needing test another
testrun empty build-needing test $FAKEARCHITECTURE

mkdir onlyarchall-1.0
mkdir onlyarchall-1.0/debian
cat >onlyarchall-1.0/debian/control <<END
Source: onlyarchall
Section: something
Priority: extra
Maintainer: me <me@example.org>
Standards-Version: 0.0

Package: archall
Architecture: all
Description: some test-arch all package
 .
END
cat >onlyarchall-1.0/debian/changelog <<END
onlyarchall (1.0-1) test; urgency=critical

  * first version

 -- me <me@example.orgguess@who>  Mon, 01 Jan 1980 01:02:02 +0000
END
dpkg-source -b onlyarchall-1.0
mkdir onlyarchall-1.0/debian/tmp
mkdir onlyarchall-1.0/debian/tmp/DEBIAN
mkdir -p onlyarchall-1.0/debian/tmp/usr/bin
touch onlyarchall-1.0/debian/tmp/usr/bin/program
cd onlyarchall-1.0
dpkg-gencontrol -parchall
dpkg --build debian/tmp ..
cd ..
rm -r onlyarchall-1.0

testrun - --delete includedsc test onlyarchall_1.0-1.dsc 3<<EOF
stderr
=Data seems not to be signed trying to use directly...
-v1*=onlyarchall_1.0-1.dsc: component guessed as 'main'
*=Warning: database 'bla|main|source' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-v2*=Created directory "./pool/main/o/onlyarchall"
-d1*=db: 'pool/main/o/onlyarchall/onlyarchall_1.0-1.dsc' added to checksums.db(pool).
-d1*=db: 'pool/main/o/onlyarchall/onlyarchall_1.0-1.tar.gz' added to checksums.db(pool).
-d1*=db: 'onlyarchall' added to packages.db(bla|main|source).
-d1*=db: 'onlyarchall' added to tracking.db(bla).
EOF

testrun empty build-needing test another
testrun empty build-needing test $FAKEARCHITECTURE

testrun - --delete -C main includedeb test archall_1.0-1_all.deb 3<<EOF
stderr
*=Warning: database 'bla|main|${FAKEARCHITECTURE}' was modified but no index file was exported.
*=Warning: database 'bla|main|another' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-d1*=db: 'pool/main/o/onlyarchall/archall_1.0-1_all.deb' added to checksums.db(pool).
-d1*=db: 'archall' added to packages.db(bla|main|${FAKEARCHITECTURE}).
-d1*=db: 'archall' added to packages.db(bla|main|another).
EOF

testrun empty build-needing test another
testrun empty build-needing test $FAKEARCHITECTURE

rm -r pool conf db *.deb *.log *.changes
testsuccess
