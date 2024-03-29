#!/bin/bash

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

dodo test ! -d db
mkdir -p conf dists
echo "export never" > conf/options
cat > conf/distributions <<EOF
Codename: codename1
Update: notexisting
Components: component
Architectures: architecture
EOF
cat > conf/updates <<EOF
Name: chainb5
From: chainb4

Name: chainb4
From: chainb3

Name: chainb3
From: chainb2

Name: chainb2
From: chainb1

Name: chainb1
From: circular2

Name: circular1
From: circular2

Name: circular2
From: circular1

Name: chaina1
From: circular1

Name: chaina2
From: chaina1

Name: chaina3
From: chaina2

Name: chaina4
From: chaina3

Name: chaina5
From: chaina4

Name: chaina6
From: chaina5
EOF

mkdir lists db

testrun - -b . update 3<<EOF
returns 255
stderr
*=Error: Update rule 'circular1' part of circular From-referencing.
-v0*=There have been errors!
stdout
EOF

cat > conf/updates <<EOF
Name: name
From: broken
EOF

testrun - -b . update 3<<EOF
returns 255
stderr
*=./conf/updates: Update pattern 'name' references unknown pattern 'broken' via From!
-v0*=There have been errors!
stdout
EOF

cat > conf/updates <<EOF
EOF

testrun - -b . update 3<<EOF
returns 255
stderr
*=Cannot find definition of upgrade-rule 'notexisting' for distribution 'codename1'!
-v0*=There have been errors!
stdout
EOF

cat > conf/distributions <<EOF
Codename: codename1
Update: test
Components: component
Architectures: architecture
EOF
cat > conf/updates <<EOF
Name: test
Components: comonent
Architectures: achitecture
VerifyRelease: blindtrust
Method: file:///notexistant
EOF

testrun - -b . update 3<<EOF
returns 255
stderr
*=Warning parsing ./conf/updates, line 2: unknown component 'comonent' will be ignored!
*=Warning parsing ./conf/updates, line 3: unknown architecture 'achitecture' will be ignored!
*=aptmethod error receiving 'file:///notexistant/dists/codename1/Release':
*='File not found'
-v0*=There have been errors!
stdout
EOF

cat > conf/updates <<EOF
Name: test
Components: comonent
EOF

rm -r db
mkdir db

cat > conf/distributions <<EOF
Codename: codename1
Components: a bb
UDebComponents: a
Architectures: x yyyyyyyyyy source
Update: a b - b c

Codename: codename2
Components: a bb
Architectures: x yyyyyyyyyy
Update: c - a
EOF
cat > conf/updates <<EOF
Name: base
VerifyRelease: blindtrust
Method: file:$WORKDIR/testsource
Components: error1

Name: a
Components: a
From: base

Name: b
Components: a
From: base

Name: c
From: base
EOF

#testrun - -b . update 3<<EOF
#returns 255
#stderr
#-v0*=There have been errors!
#stdout
#EOF

cat > conf/updates <<EOF
Name: base
VerifyRelease: blindtrust
Method: file:$WORKDIR/testsource
Suite: test

Name: a
Suite: codename1
From: base

Name: b
Suite: codename2
DownloadListsAs: .gz .lzma
From: base

Name: c
Suite: *
From: base
EOF

testrun - -b . update codename2 3<<EOF
returns 255
stderr
*=aptmethod error receiving 'file:$WORKDIR/testsource/dists/codename1/Release':
*=aptmethod error receiving 'file:$WORKDIR/testsource/dists/codename2/Release':
*='File not found'
-v0*=There have been errors!
stdout
EOF

mkdir testsource testsource/dists testsource/dists/codename1 testsource/dists/codename2
touch testsource/dists/codename1/Release testsource/dists/codename2/Release

testrun - -b . update codename2 3<<EOF
returns 255
stderr
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/Release'
-v2*=Copy file '$WORKDIR/testsource/dists/codename2/Release' to './lists/base_codename2_Release'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/Release'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/Release' to './lists/base_codename1_Release'...
*=Missing checksums in Release file './lists/base_codename2_Release'!
-v0*=There have been errors!
stdout
EOF

cat > testsource/dists/codename1/Release <<EOF
Codename: codename1
Architectures: x yyyyyyyyyy
Components: a bb
MD5Sum:
EOF
cat > testsource/dists/codename2/Release <<EOF
Codename: codename2
Architectures: x yyyyyyyyyy
Components: a bb
MD5Sum:
EOF

testrun - -b . update codename2 3<<EOF
returns 254
stderr
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/Release'
-v2*=Copy file '$WORKDIR/testsource/dists/codename2/Release' to './lists/base_codename2_Release'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/Release'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/Release' to './lists/base_codename1_Release'...
*=Could not find 'a/binary-x/Packages' within './lists/base_codename2_Release'
-v0*=There have been errors!
stdout
EOF

mkdir -p testsource/dists/codename1/a/debian-installer/binary-x
touch testsource/dists/codename1/a/debian-installer/binary-x/Packages
mkdir -p testsource/dists/codename1/a/debian-installer/binary-yyyyyyyyyy
touch testsource/dists/codename1/a/debian-installer/binary-yyyyyyyyyy/Packages
mkdir -p testsource/dists/codename1/a/binary-x
touch testsource/dists/codename1/a/binary-x/Packages
mkdir -p testsource/dists/codename1/a/binary-yyyyyyyyyy
touch testsource/dists/codename1/a/binary-yyyyyyyyyy/Packages
mkdir -p testsource/dists/codename1/a/source
touch testsource/dists/codename1/a/source/Sources
mkdir -p testsource/dists/codename1/bb/binary-x
touch testsource/dists/codename1/bb/binary-x/Packages
mkdir -p testsource/dists/codename1/bb/binary-yyyyyyyyyy
touch testsource/dists/codename1/bb/binary-yyyyyyyyyy/Packages
mkdir -p testsource/dists/codename1/bb/source
touch testsource/dists/codename1/bb/source/Sources

cat > testsource/dists/codename1/Release <<EOF
Codename: codename1
Architectures: x yyyyyyyyyy
Components: a bb
MD5Sum:
 11111111111111111111111111111111 17 bb/source/Sources.lzma
 $(cd testsource ; md5releaseline codename1 a/debian-installer/binary-x/Packages)
 $(cd testsource ; md5releaseline codename1 a/debian-installer/binary-yyyyyyyyyy/Packages)
 $(cd testsource ; md5releaseline codename1 a/binary-x/Packages)
 $(cd testsource ; md5releaseline codename1 a/binary-yyyyyyyyyy/Packages)
 $(cd testsource ; md5releaseline codename1 a/source/Sources)
 $(cd testsource ; md5releaseline codename1 bb/binary-x/Packages)
 $(cd testsource ; md5releaseline codename1 bb/binary-yyyyyyyyyy/Packages)
 $(cd testsource ; md5releaseline codename1 bb/source/Sources)
EOF

mkdir -p testsource/dists/codename2/a/binary-x
touch testsource/dists/codename2/a/binary-x/Packages
mkdir -p testsource/dists/codename2/a/binary-yyyyyyyyyy
touch testsource/dists/codename2/a/binary-yyyyyyyyyy/Packages
mkdir -p testsource/dists/codename2/bb/binary-x
touch testsource/dists/codename2/bb/binary-x/Packages
mkdir -p testsource/dists/codename2/bb/binary-yyyyyyyyyy
touch testsource/dists/codename2/bb/binary-yyyyyyyyyy/Packages
mkdir -p testsource/dists/codename2/a/debian-installer/binary-x
touch testsource/dists/codename2/a/debian-installer/binary-x/Packages
mkdir -p testsource/dists/codename2/a/debian-installer/binary-yyyyyyyyyy
touch testsource/dists/codename2/a/debian-installer/binary-yyyyyyyyyy/Packages
mkdir -p testsource/dists/codename2/a/source
touch testsource/dists/codename2/a/source/Sources
mkdir -p testsource/dists/codename2/bb/source
touch testsource/dists/codename2/bb/source/Sources

cat > testsource/dists/codename2/Release <<EOF
Codename: codename2
Architectures: x yyyyyyyyyy
Components: a bb
MD5Sum:
 $(cd testsource ; md5releaseline codename2 a/debian-installer/binary-x/Packages)
 $(cd testsource ; md5releaseline codename2 a/debian-installer/binary-yyyyyyyyyy/Packages)
 $(cd testsource ; md5releaseline codename2 a/binary-x/Packages)
 $(cd testsource ; md5releaseline codename2 a/binary-yyyyyyyyyy/Packages)
 $(cd testsource ; md5releaseline codename2 a/source/Sources)
 $(cd testsource ; md5releaseline codename2 bb/binary-x/Packages)
 $(cd testsource ; md5releaseline codename2 bb/binary-yyyyyyyyyy/Packages)
 $(cd testsource ; md5releaseline codename2 bb/source/Sources)
EOF

lzma testsource/dists/codename2/a/binary-x/Packages
lzma testsource/dists/codename2/a/source/Sources
lzma testsource/dists/codename2/bb/source/Sources
lzma testsource/dists/codename2/a/debian-installer/binary-yyyyyyyyyy/Packages
lzma testsource/dists/codename2/bb/binary-yyyyyyyyyy/Packages
lzma testsource/dists/codename2/bb/binary-x/Packages
lzma testsource/dists/codename2/a/binary-yyyyyyyyyy/Packages
lzma testsource/dists/codename2/a/debian-installer/binary-x/Packages

cat >> testsource/dists/codename2/Release <<EOF
 $(cd testsource ; md5releaseline codename2 a/debian-installer/binary-x/Packages.lzma)
 $(cd testsource ; md5releaseline codename2 a/debian-installer/binary-yyyyyyyyyy/Packages.lzma)
 $(cd testsource ; md5releaseline codename2 a/binary-x/Packages.lzma)
 $(cd testsource ; md5releaseline codename2 a/binary-yyyyyyyyyy/Packages.lzma)
 $(cd testsource ; md5releaseline codename2 a/source/Sources.lzma)
 $(cd testsource ; md5releaseline codename2 bb/binary-x/Packages.lzma)
 $(cd testsource ; md5releaseline codename2 bb/binary-yyyyyyyyyy/Packages.lzma)
 $(cd testsource ; md5releaseline codename2 bb/source/Sources.lzma)
EOF


testout - -b . update codename2 3<<EOF
stderr
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/Release'
-v2*=Copy file '$WORKDIR/testsource/dists/codename2/Release' to './lists/base_codename2_Release'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/Release'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/Release' to './lists/base_codename1_Release'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/a/binary-x/Packages'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/a/binary-x/Packages' to './lists/base_codename1_a_x_Packages'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/bb/binary-x/Packages'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/bb/binary-x/Packages' to './lists/base_codename1_bb_x_Packages'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/a/binary-yyyyyyyyyy/Packages'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/a/binary-yyyyyyyyyy/Packages' to './lists/base_codename1_a_yyyyyyyyyy_Packages'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/bb/binary-yyyyyyyyyy/Packages'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/bb/binary-yyyyyyyyyy/Packages' to './lists/base_codename1_bb_yyyyyyyyyy_Packages'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/a/binary-x/Packages.lzma'
-v2*=Uncompress '$WORKDIR/testsource/dists/codename2/a/binary-x/Packages.lzma' into './lists/base_codename2_a_x_Packages' using '/usr/bin/unlzma'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/bb/binary-x/Packages.lzma'
-v2*=Uncompress '$WORKDIR/testsource/dists/codename2/bb/binary-x/Packages.lzma' into './lists/base_codename2_bb_x_Packages' using '/usr/bin/unlzma'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/a/binary-yyyyyyyyyy/Packages.lzma'
-v2*=Uncompress '$WORKDIR/testsource/dists/codename2/a/binary-yyyyyyyyyy/Packages.lzma' into './lists/base_codename2_a_yyyyyyyyyy_Packages' using '/usr/bin/unlzma'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/bb/binary-yyyyyyyyyy/Packages.lzma'
-v2*=Uncompress '$WORKDIR/testsource/dists/codename2/bb/binary-yyyyyyyyyy/Packages.lzma' into './lists/base_codename2_bb_yyyyyyyyyy_Packages' using '/usr/bin/unlzma'...
EOF

true > results.expected
if [ $verbosity -ge 0 ] ; then
echo "Calculating packages to get..." > results.expected ; fi
if [ $verbosity -ge 3 ] ; then
echo "  processing updates for 'codename2|bb|yyyyyyyyyy'" >>results.expected ; fi
if [ $verbosity -ge 5 ] ; then
echo "  reading './lists/base_codename2_bb_yyyyyyyyyy_Packages'" >>results.expected
echo "  marking everything to be deleted" >>results.expected
echo "  reading './lists/base_codename1_bb_yyyyyyyyyy_Packages'" >>results.expected ; fi
if [ $verbosity -ge 3 ] ; then
echo "  processing updates for 'codename2|bb|x'" >>results.expected ; fi
if [ $verbosity -ge 5 ] ; then
echo "  reading './lists/base_codename2_bb_x_Packages'" >>results.expected
echo "  marking everything to be deleted" >>results.expected
echo "  reading './lists/base_codename1_bb_x_Packages'" >>results.expected ; fi
if [ $verbosity -ge 3 ] ; then
echo "  processing updates for 'codename2|a|yyyyyyyyyy'" >>results.expected ; fi
if [ $verbosity -ge 5 ] ; then
echo "  reading './lists/base_codename2_a_yyyyyyyyyy_Packages'" >>results.expected
echo "  marking everything to be deleted" >>results.expected
echo "  reading './lists/base_codename1_a_yyyyyyyyyy_Packages'" >>results.expected ; fi
if [ $verbosity -ge 3 ] ; then
echo "  processing updates for 'codename2|a|x'" >>results.expected ; fi
if [ $verbosity -ge 5 ] ; then
echo "  reading './lists/base_codename2_a_x_Packages'" >>results.expected
echo "  marking everything to be deleted" >>results.expected
echo "  reading './lists/base_codename1_a_x_Packages'" >>results.expected ; fi
dodiff results.expected results
mv results.expected results2.expected

testout - -b . update codename1 3<<EOF
stderr
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/Release'
-v2*=Copy file '$WORKDIR/testsource/dists/codename2/Release' to './lists/base_codename2_Release'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/Release'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/Release' to './lists/base_codename1_Release'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/a/debian-installer/binary-x/Packages'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/a/debian-installer/binary-x/Packages' to './lists/base_codename1_a_x_uPackages'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/a/debian-installer/binary-yyyyyyyyyy/Packages'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/a/debian-installer/binary-yyyyyyyyyy/Packages' to './lists/base_codename1_a_yyyyyyyyyy_uPackages'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/a/debian-installer/binary-x/Packages.lzma'
-v2*=Uncompress '$WORKDIR/testsource/dists/codename2/a/debian-installer/binary-x/Packages.lzma' into './lists/base_codename2_a_x_uPackages' using '/usr/bin/unlzma'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/a/debian-installer/binary-yyyyyyyyyy/Packages.lzma'
-v2*=Uncompress '$WORKDIR/testsource/dists/codename2/a/debian-installer/binary-yyyyyyyyyy/Packages.lzma' into './lists/base_codename2_a_yyyyyyyyyy_uPackages' using '/usr/bin/unlzma'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/a/source/Sources'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/a/source/Sources' to './lists/base_codename1_a_Sources'...
-v1*=aptmethod error receiving 'file:$WORKDIR/testsource/dists/codename1/bb/source/Sources.lzma':
-v1*='File not found'
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/bb/source/Sources'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/bb/source/Sources' to './lists/base_codename1_bb_Sources'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/a/source/Sources.lzma'
-v2*=Uncompress '$WORKDIR/testsource/dists/codename2/a/source/Sources.lzma' into './lists/base_codename2_a_Sources' using '/usr/bin/unlzma'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/bb/source/Sources.lzma'
-v2*=Uncompress '$WORKDIR/testsource/dists/codename2/bb/source/Sources.lzma' into './lists/base_codename2_bb_Sources' using '/usr/bin/unlzma'...
EOF

ed -s testsource/dists/codename1/Release <<EOF
g/^ 11111111111111111/d
w
q
EOF

true > results.expected
if [ $verbosity -ge 0 ] ; then
echo "Calculating packages to get..." > results.expected ; fi
if [ $verbosity -ge 3 ] ; then
echo "  processing updates for 'codename1|bb|source'" >>results.expected ; fi
if [ $verbosity -ge 5 ] ; then
echo "  reading './lists/base_codename1_bb_Sources'" >>results.expected
echo "  reading './lists/base_codename2_bb_Sources'" >>results.expected
echo "  marking everything to be deleted" >>results.expected
echo "  reading './lists/base_codename2_bb_Sources'" >>results.expected
echo "  reading './lists/base_codename1_bb_Sources'" >>results.expected
fi
if [ $verbosity -ge 3 ] ; then
echo "  processing updates for 'codename1|bb|yyyyyyyyyy'" >>results.expected ; fi
if [ $verbosity -ge 5 ] ; then
echo "  reading './lists/base_codename1_bb_yyyyyyyyyy_Packages'" >>results.expected
echo "  reading './lists/base_codename2_bb_yyyyyyyyyy_Packages'" >>results.expected
echo "  marking everything to be deleted" >>results.expected
echo "  reading './lists/base_codename2_bb_yyyyyyyyyy_Packages'" >>results.expected
echo "  reading './lists/base_codename1_bb_yyyyyyyyyy_Packages'" >>results.expected
fi
if [ $verbosity -ge 3 ] ; then
echo "  processing updates for 'codename1|bb|x'" >>results.expected ; fi
if [ $verbosity -ge 5 ] ; then
echo "  reading './lists/base_codename1_bb_x_Packages'" >>results.expected
echo "  reading './lists/base_codename2_bb_x_Packages'" >>results.expected
echo "  marking everything to be deleted" >>results.expected
echo "  reading './lists/base_codename2_bb_x_Packages'" >>results.expected
echo "  reading './lists/base_codename1_bb_x_Packages'" >>results.expected
fi
if [ $verbosity -ge 3 ] ; then
echo "  processing updates for 'codename1|a|source'" >>results.expected ; fi
if [ $verbosity -ge 5 ] ; then
echo "  reading './lists/base_codename1_a_Sources'" >>results.expected
echo "  reading './lists/base_codename2_a_Sources'" >>results.expected
echo "  marking everything to be deleted" >>results.expected
echo "  reading './lists/base_codename2_a_Sources'" >>results.expected
echo "  reading './lists/base_codename1_a_Sources'" >>results.expected
fi
if [ $verbosity -ge 3 ] ; then
echo "  processing updates for 'u|codename1|a|yyyyyyyyyy'" >>results.expected ; fi
if [ $verbosity -ge 5 ] ; then
echo "  reading './lists/base_codename1_a_yyyyyyyyyy_uPackages'" >>results.expected
echo "  reading './lists/base_codename2_a_yyyyyyyyyy_uPackages'" >>results.expected
echo "  marking everything to be deleted" >>results.expected
echo "  reading './lists/base_codename2_a_yyyyyyyyyy_uPackages'" >>results.expected
echo "  reading './lists/base_codename1_a_yyyyyyyyyy_uPackages'" >>results.expected
fi
if [ $verbosity -ge 3 ] ; then
echo "  processing updates for 'codename1|a|yyyyyyyyyy'" >>results.expected ; fi
if [ $verbosity -ge 5 ] ; then
echo "  reading './lists/base_codename1_a_yyyyyyyyyy_Packages'" >>results.expected
echo "  reading './lists/base_codename2_a_yyyyyyyyyy_Packages'" >>results.expected
echo "  marking everything to be deleted" >>results.expected
echo "  reading './lists/base_codename2_a_yyyyyyyyyy_Packages'" >>results.expected
echo "  reading './lists/base_codename1_a_yyyyyyyyyy_Packages'" >>results.expected
fi
if [ $verbosity -ge 3 ] ; then
echo "  processing updates for 'u|codename1|a|x'" >>results.expected ; fi
if [ $verbosity -ge 5 ] ; then
echo "  reading './lists/base_codename1_a_x_uPackages'" >>results.expected
echo "  reading './lists/base_codename2_a_x_uPackages'" >>results.expected
echo "  marking everything to be deleted" >>results.expected
echo "  reading './lists/base_codename2_a_x_uPackages'" >>results.expected
echo "  reading './lists/base_codename1_a_x_uPackages'" >>results.expected
fi
if [ $verbosity -ge 3 ] ; then
echo "  processing updates for 'codename1|a|x'" >>results.expected ; fi
if [ $verbosity -ge 5 ] ; then
echo "  reading './lists/base_codename1_a_x_Packages'" >>results.expected
echo "  reading './lists/base_codename2_a_x_Packages'" >>results.expected
echo "  marking everything to be deleted" >>results.expected
echo "  reading './lists/base_codename2_a_x_Packages'" >>results.expected
echo "  reading './lists/base_codename1_a_x_Packages'" >>results.expected
fi
dodiff results.expected results

testrun - -b . update codename2 codename1 3<<EOF
stderr
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/Release'
-v2*=Copy file '$WORKDIR/testsource/dists/codename2/Release' to './lists/base_codename2_Release'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/Release'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/Release' to './lists/base_codename1_Release'...
stdout
-v0*=Nothing to do found. (Use --noskipold to force processing)
EOF
dodo rm lists/_codename*
testout - -b . update codename2 codename1 3<<EOF
stderr
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename1/Release'
-v2*=Copy file '$WORKDIR/testsource/dists/codename2/Release' to './lists/base_codename2_Release'...
-v1*=aptmethod got 'file:$WORKDIR/testsource/dists/codename2/Release'
-v2*=Copy file '$WORKDIR/testsource/dists/codename1/Release' to './lists/base_codename1_Release'...
EOF
grep '^C' results.expected > resultsboth.expected || true
grep '^  ' results2.expected >> resultsboth.expected || true
grep '^  ' results.expected >> resultsboth.expected || true
grep '^[^ C]' results.expected >> resultsboth.expected || true
dodiff resultsboth.expected results

sed -i -e "s/Method: file:/Method: copy:/" conf/updates

dodo rm lists/_codename*
testout - -b . update codename1 3<<EOF
stderr
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename1/Release'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename1/Release'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/Release'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/Release'
EOF
dodiff results.expected results

rm -r lists ; mkdir lists

testout - -b . update codename2 3<<EOF
stderr
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename1/Release'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename1/Release'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/Release'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/Release'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename1/a/binary-x/Packages'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename1/a/binary-x/Packages'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename1/bb/binary-x/Packages'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename1/bb/binary-x/Packages'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename1/a/binary-yyyyyyyyyy/Packages'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename1/a/binary-yyyyyyyyyy/Packages'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename1/bb/binary-yyyyyyyyyy/Packages'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename1/bb/binary-yyyyyyyyyy/Packages'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/a/binary-x/Packages.lzma'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/a/binary-x/Packages.lzma'
-v2*=Uncompress './lists/base_codename2_a_x_Packages.lzma' into './lists/base_codename2_a_x_Packages' using '/usr/bin/unlzma'...
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/bb/binary-x/Packages.lzma'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/bb/binary-x/Packages.lzma'
-v2*=Uncompress './lists/base_codename2_bb_x_Packages.lzma' into './lists/base_codename2_bb_x_Packages' using '/usr/bin/unlzma'...
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/a/binary-yyyyyyyyyy/Packages.lzma'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/a/binary-yyyyyyyyyy/Packages.lzma'
-v2*=Uncompress './lists/base_codename2_a_yyyyyyyyyy_Packages.lzma' into './lists/base_codename2_a_yyyyyyyyyy_Packages' using '/usr/bin/unlzma'...
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/bb/binary-yyyyyyyyyy/Packages.lzma'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/bb/binary-yyyyyyyyyy/Packages.lzma'
-v2*=Uncompress './lists/base_codename2_bb_yyyyyyyyyy_Packages.lzma' into './lists/base_codename2_bb_yyyyyyyyyy_Packages' using '/usr/bin/unlzma'...
EOF
dodiff results2.expected results

testout - -b . update codename1 3<<EOF
stderr
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename1/Release'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename1/Release'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/Release'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/Release'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename1/a/debian-installer/binary-x/Packages'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename1/a/debian-installer/binary-x/Packages'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename1/a/debian-installer/binary-yyyyyyyyyy/Packages'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename1/a/debian-installer/binary-yyyyyyyyyy/Packages'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/a/debian-installer/binary-x/Packages.lzma'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/a/debian-installer/binary-x/Packages.lzma'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/a/debian-installer/binary-yyyyyyyyyy/Packages.lzma'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/a/debian-installer/binary-yyyyyyyyyy/Packages.lzma'
-v2*=Uncompress './lists/base_codename2_a_x_uPackages.lzma' into './lists/base_codename2_a_x_uPackages' using '/usr/bin/unlzma'...
-v2*=Uncompress './lists/base_codename2_a_yyyyyyyyyy_uPackages.lzma' into './lists/base_codename2_a_yyyyyyyyyy_uPackages' using '/usr/bin/unlzma'...
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename1/a/source/Sources'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename1/a/source/Sources'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename1/bb/source/Sources'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename1/bb/source/Sources'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/a/source/Sources.lzma'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/a/source/Sources.lzma'
-v2*=Uncompress './lists/base_codename2_a_Sources.lzma' into './lists/base_codename2_a_Sources' using '/usr/bin/unlzma'...
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/bb/source/Sources.lzma'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/bb/source/Sources.lzma'
-v2*=Uncompress './lists/base_codename2_bb_Sources.lzma' into './lists/base_codename2_bb_Sources' using '/usr/bin/unlzma'...
EOF
dodiff results.expected results

# Test repositories without uncompressed files listed:
printf '%%g/^ .*[^a]$/d\nw\nq\n' | ed -s testsource/dists/codename2/Release
# lists/_codename* no longer has to be deleted, as without the uncompressed checksums
# reprepro does not know it already processed those (it only saves the uncompressed
# checksums of the already processed files)

# As the checksums for the uncompressed files are not know, and the .lzma files
# not saved, the lzma files have to be downloaded again:
testout - -b . update codename2 3<<EOF
stderr
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename1/Release'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename1/Release'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/Release'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/Release'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/a/binary-x/Packages.lzma'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/a/binary-x/Packages.lzma'
-v2*=Uncompress './lists/base_codename2_a_x_Packages.lzma' into './lists/base_codename2_a_x_Packages' using '/usr/bin/unlzma'...
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/bb/binary-x/Packages.lzma'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/bb/binary-x/Packages.lzma'
-v2*=Uncompress './lists/base_codename2_bb_x_Packages.lzma' into './lists/base_codename2_bb_x_Packages' using '/usr/bin/unlzma'...
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/a/binary-yyyyyyyyyy/Packages.lzma'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/a/binary-yyyyyyyyyy/Packages.lzma'
-v2*=Uncompress './lists/base_codename2_a_yyyyyyyyyy_Packages.lzma' into './lists/base_codename2_a_yyyyyyyyyy_Packages' using '/usr/bin/unlzma'...
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/bb/binary-yyyyyyyyyy/Packages.lzma'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/bb/binary-yyyyyyyyyy/Packages.lzma'
-v2*=Uncompress './lists/base_codename2_bb_yyyyyyyyyy_Packages.lzma' into './lists/base_codename2_bb_yyyyyyyyyy_Packages' using '/usr/bin/unlzma'...
EOF
dodiff results2.expected results

# last time the .lzma files should have not been deleted, so no download
# but uncompress has still to be done...
testout - -b . update codename2 3<<EOF
stderr
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename1/Release'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename1/Release'
-v6*=aptmethod start 'copy:$WORKDIR/testsource/dists/codename2/Release'
-v1*=aptmethod got 'copy:$WORKDIR/testsource/dists/codename2/Release'
-v2*=Uncompress './lists/base_codename2_a_x_Packages.lzma' into './lists/base_codename2_a_x_Packages' using '/usr/bin/unlzma'...
-v2*=Uncompress './lists/base_codename2_bb_x_Packages.lzma' into './lists/base_codename2_bb_x_Packages' using '/usr/bin/unlzma'...
-v2*=Uncompress './lists/base_codename2_a_yyyyyyyyyy_Packages.lzma' into './lists/base_codename2_a_yyyyyyyyyy_Packages' using '/usr/bin/unlzma'...
-v2*=Uncompress './lists/base_codename2_bb_yyyyyyyyyy_Packages.lzma' into './lists/base_codename2_bb_yyyyyyyyyy_Packages' using '/usr/bin/unlzma'...
EOF
dodiff results2.expected results

rm -r -f db conf dists pool lists testsource
testsuccess
