#!/bin/bash

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

mkdir conf db pool fakes old
mkdir -p dists/sourcedistribution/main/binary-coal

cp "$SRCDIR/docs/tiffany.example" conf/pdiff.py
cat > conf/distributions <<EOF
Codename: sourcedistribution
Architectures: coal
Components: main
DebIndices: Packages Release . pdiff.py

Codename: test
Architectures: coal
Components: main
Update: fromsource
EOF

testrun - -b . export sourcedistribution 3<<EOF
stdout
-v1*=Exporting sourcedistribution...
-v6*= exporting 'sourcedistribution|main|coal'...
-v6*=  creating './dists/sourcedistribution/main/binary-coal/Packages' (uncompressed,script: pdiff.py)
EOF

dodo test -f dists/sourcedistribution/main/binary-coal/Packages
dodo test -f dists/sourcedistribution/main/binary-coal/Release
dodo test \! -e dists/sourcedistribution/main/binary-coal/Packages.diff

testrun - -b . _addpackage sourcedistribution fakes/1 a  3<<EOF
stderr
*=_addpackage needs -C and -A and -T set!
-v0*=There have been errors!
returns 255
EOF

testrun - -b . -C main -A coal -T deb _addpackage sourcedistribution fakes/1 a  3<<EOF
stderr
*=Error 2 opening 'fakes/1': No such file or directory!
-v0*=There have been errors!
return 254
EOF

touch fakes/1

# TODO: getting a warning here would be nice...
testrun - -b . -C main -A coal -T deb _addpackage sourcedistribution fakes/1 a  3<<EOF
EOF
testrun - --nothingiserror -b . -C main -A coal -T deb _addpackage sourcedistribution fakes/1 a  3<<EOF
returns 1
EOF

cat > fakes/1 <<EOF
Package: 5dchess
Priority: extra
Section: games
Installed-Size: 400000
Maintainer: test <nobody@nowhere>
Architecture: coal
Version: 0.0-1
Filename: pool/main/5/5dchess/5dchess_0.0-1_coal.deb
MD5sum: $EMPTYMD5ONLY
Size: 0
Description: the lazy fox
 jumps over the quick brown dog.

Package: a
Priority: critical
Section: required
Installed-Size: 1
Maintainer: test <nobody@nowhere>
Architecture: all
Version: 1
Filename: pool/main/a/a/a_1_all.deb
MD5sum: $EMPTYMD5ONLY
Size: 0
Description: the lazy fox
 jumps over the quick brown dog.

Package: b
Source: baa
Priority: critical
Section: required
Installed-Size: 1
Maintainer: test <nobody@nowhere>
Architecture: coal
Version: 2
Filename: pool/main/b/baa/b_2_coal.deb
MD5sum: $EMPTYMD5ONLY
Size: 0
Description: the lazy fox
 jumps over the quick brown dog.
EOF

cat > fakes/2 <<EOF
Package: a
Priority: critical
Section: required
Installed-Size: 2
Maintainer: test <nobody@nowhere>
Architecture: all
Version: 2
Filename: pool/main/a/a/a_2_all.deb
MD5sum: $EMPTYMD5ONLY
Size: 0
Description: the lazy fox
 jumps over the quick brown dog.
EOF

testrun - -b . -C main -A coal -T deb _addpackage sourcedistribution fakes/1 a  3<<EOF
*=Error: package a version 1 lists file pool/main/a/a/a_1_all.deb not yet in the pool!
-v0*=There have been errors!
returns 249
EOF

cat > addchecksums.rules <<EOF
stdout
-d1*=db: 'pool/main/a/a/a_1_all.deb' added to checksums.db(pool).
-d1*=db: 'pool/main/a/a/a_2_all.deb' added to checksums.db(pool).
-d1*=db: 'pool/main/b/baa/b_2_coal.deb' added to checksums.db(pool).
-d1*=db: 'pool/main/5/5dchess/5dchess_0.0-1_coal.deb' added to checksums.db(pool).
-v0*=4 files were added but not used.
-v0*=The next deleteunreferenced call will delete them.
EOF

testrun addchecksums -b . _addchecksums <<EOF
pool/main/b/baa/b_2_coal.deb $EMPTYMD5
pool/main/a/a/a_1_all.deb $EMPTYMD5
pool/main/a/a/a_2_all.deb $EMPTYMD5
pool/main/5/5dchess/5dchess_0.0-1_coal.deb $EMPTYMD5
EOF

testrun - -b . -C main -A coal -T deb _addpackage sourcedistribution fakes/1 a  3<<EOF
stdout
-v1*=Adding 'a' '1' to 'sourcedistribution|main|coal'.
-d1*=db: 'a' added to packages.db(sourcedistribution|main|coal).
-v0*=Exporting indices...
-v6*= looking for changes in 'sourcedistribution|main|coal'...
-v6*=  replacing './dists/sourcedistribution/main/binary-coal/Packages' (uncompressed,script: pdiff.py)
=making diffs between ./dists/sourcedistribution/main/binary-coal/Packages and ./dists/sourcedistribution/main/binary-coal/Packages.new: 
=generating diff
EOF
sleep 1
testrun - -b . -C main -A coal -T deb _addpackage sourcedistribution fakes/1 5dchess  3<<EOF
stdout
-v1*=Adding '5dchess' '0.0-1' to 'sourcedistribution|main|coal'.
-d1*=db: '5dchess' added to packages.db(sourcedistribution|main|coal).
-v0*=Exporting indices...
-v6*= looking for changes in 'sourcedistribution|main|coal'...
-v6*=  replacing './dists/sourcedistribution/main/binary-coal/Packages' (uncompressed,script: pdiff.py)
=making diffs between ./dists/sourcedistribution/main/binary-coal/Packages and ./dists/sourcedistribution/main/binary-coal/Packages.new: 
=generating diff
=This was too fast, diffile already there, waiting a bit...
EOF
sleep 1
cp dists/sourcedistribution/main/binary-coal/Packages old/1
testrun - -b . -C main -A coal -T deb _addpackage sourcedistribution fakes/2 a 3<<EOF
stderr
*=./pool/main/a/a/a_1_all.deb not found, forgetting anyway
stdout
-v1*=Adding 'a' '2' to 'sourcedistribution|main|coal'.
-d1*=db: 'a' removed from packages.db(sourcedistribution|main|coal).
-d1*=db: 'a' added to packages.db(sourcedistribution|main|coal).
-v0*=Exporting indices...
-v6*= looking for changes in 'sourcedistribution|main|coal'...
-v6*=  replacing './dists/sourcedistribution/main/binary-coal/Packages' (uncompressed,script: pdiff.py)
=making diffs between ./dists/sourcedistribution/main/binary-coal/Packages and ./dists/sourcedistribution/main/binary-coal/Packages.new: 
=generating diff
=This was too fast, diffile already there, waiting a bit...
-v0*=Deleting files no longer referenced...
-v1*=deleting and forgetting pool/main/a/a/a_1_all.deb
-d1*=db: 'pool/main/a/a/a_1_all.deb' removed from checksums.db(pool).
EOF
cp dists/sourcedistribution/main/binary-coal/Packages old/2
sleep 1
testrun - -b . -C main -A coal -T deb _addpackage sourcedistribution fakes/1 b 3<<EOF
stdout
-v1*=Adding 'b' '2' to 'sourcedistribution|main|coal'.
-d1*=db: 'b' added to packages.db(sourcedistribution|main|coal).
-v0*=Exporting indices...
-v6*= looking for changes in 'sourcedistribution|main|coal'...
-v6*=  replacing './dists/sourcedistribution/main/binary-coal/Packages' (uncompressed,script: pdiff.py)
=making diffs between ./dists/sourcedistribution/main/binary-coal/Packages and ./dists/sourcedistribution/main/binary-coal/Packages.new: 
=generating diff
=This was too fast, diffile already there, waiting a bit...
EOF

dodo test -f dists/sourcedistribution/main/binary-coal/Packages
dodo test -f dists/sourcedistribution/main/binary-coal/Release
dodo test -d dists/sourcedistribution/main/binary-coal/Packages.diff
dodo test -f dists/sourcedistribution/main/binary-coal/Packages.diff/Index
testrun empty -b . dumpunreferenced

# now update from that one....
cat > conf/updates <<EOF
Name: fromsource
Suite: sourcedistribution
VerifyRelease: blindtrust
DownloadListsAs: .diff
Method: file:$WORKDIR
EOF
mkdir lists
mkdir -p dists/test/main/binary-coal

cp old/2 lists/fromsource_sourcedistribution_main_coal_Packages

diffname="$(grep "^ $(sha1 old/2)" dists/sourcedistribution/main/binary-coal/Packages.diff/Index | sed -e 's/.* //')"

testrun - -b . update test 3<<EOF
stderr
-v1*=aptmethod got 'file:$WORKDIR/dists/sourcedistribution/Release'
-v2*=Copy file '$WORKDIR/dists/sourcedistribution/Release' to './lists/fromsource_sourcedistribution_Release'...
-v1*=aptmethod got 'file:$WORKDIR/dists/sourcedistribution/main/binary-coal/Packages.diff/Index'
-v2*=Copy file '$WORKDIR/dists/sourcedistribution/main/binary-coal/Packages.diff/Index' to './lists/fromsource_sourcedistribution_main_coal_Packages.diffindex'...
-v1*=aptmethod got 'file:$WORKDIR/dists/sourcedistribution/main/binary-coal/Packages.diff/${diffname}.gz'
-v2*=Uncompress '$WORKDIR/dists/sourcedistribution/main/binary-coal/Packages.diff/${diffname}.gz' into './lists/fromsource_sourcedistribution_main_coal_Packages.diff-${diffname}' using '/bin/gunzip'...
stdout
-v0*=Calculating packages to get...
-v3*=  processing updates for 'test|main|coal'
-v5*=  reading './lists/fromsource_sourcedistribution_main_coal_Packages'
-v0*=Getting packages...
-v1*=Shutting down aptmethods...
-v0*=Installing (and possibly deleting) packages...
-d1*=db: '5dchess' added to packages.db(test|main|coal).
-d1*=db: 'a' added to packages.db(test|main|coal).
-d1*=db: 'b' added to packages.db(test|main|coal).
-v0*=Exporting indices...
-v6*= looking for changes in 'test|main|coal'...
-v6*=  creating './dists/test/main/binary-coal/Packages' (uncompressed,gzipped)
EOF

dodiff dists/sourcedistribution/main/binary-coal/Packages lists/fromsource_sourcedistribution_main_coal_Packages

cp old/1 lists/fromsource_sourcedistribution_main_coal_Packages

diffname2="$(grep "^ $(sha1 old/1)" dists/sourcedistribution/main/binary-coal/Packages.diff/Index | sed -e 's/.* //')"
testrun - --noskipold -b . update test 3<<EOF
stderr
-v1*=aptmethod got 'file:$WORKDIR/dists/sourcedistribution/Release'
-v2*=Copy file '$WORKDIR/dists/sourcedistribution/Release' to './lists/fromsource_sourcedistribution_Release'...
-v1*=aptmethod got 'file:$WORKDIR/dists/sourcedistribution/main/binary-coal/Packages.diff/Index'
-v2*=Copy file '$WORKDIR/dists/sourcedistribution/main/binary-coal/Packages.diff/Index' to './lists/fromsource_sourcedistribution_main_coal_Packages.diffindex'...
-v1*=aptmethod got 'file:$WORKDIR/dists/sourcedistribution/main/binary-coal/Packages.diff/${diffname2}.gz'
-v2*=Uncompress '$WORKDIR/dists/sourcedistribution/main/binary-coal/Packages.diff/${diffname2}.gz' into './lists/fromsource_sourcedistribution_main_coal_Packages.diff-${diffname2}' using '/bin/gunzip'...
-v1*=aptmethod got 'file:$WORKDIR/dists/sourcedistribution/main/binary-coal/Packages.diff/${diffname}.gz'
-v2*=Uncompress '$WORKDIR/dists/sourcedistribution/main/binary-coal/Packages.diff/${diffname}.gz' into './lists/fromsource_sourcedistribution_main_coal_Packages.diff-${diffname}' using '/bin/gunzip'...
stdout
-v0*=Calculating packages to get...
-v3*=  processing updates for 'test|main|coal'
-v5*=  reading './lists/fromsource_sourcedistribution_main_coal_Packages'
EOF

dodiff dists/sourcedistribution/main/binary-coal/Packages lists/fromsource_sourcedistribution_main_coal_Packages

# Check without DownLoadListsAs and not index file
cat > conf/updates <<EOF
Name: fromsource
Suite: sourcedistribution
VerifyRelease: blindtrust
Method: file:$WORKDIR
EOF
rm -r lists
mkdir lists
testrun - --noskipold -b . update test 3<<EOF
stderr
-v1*=aptmethod got 'file:$WORKDIR/dists/sourcedistribution/Release'
-v2*=Copy file '$WORKDIR/dists/sourcedistribution/Release' to './lists/fromsource_sourcedistribution_Release'...
-v1*=aptmethod got 'file:$WORKDIR/dists/sourcedistribution/main/binary-coal/Packages'
-v2*=Copy file '$WORKDIR/dists/sourcedistribution/main/binary-coal/Packages' to './lists/fromsource_sourcedistribution_main_coal_Packages'...
stdout
-v0*=Calculating packages to get...
-v3*=  processing updates for 'test|main|coal'
-v5*=  reading './lists/fromsource_sourcedistribution_main_coal_Packages'
EOF

rm -r conf dists pool db fakes addchecksums.rules old lists
testsuccess
