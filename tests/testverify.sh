#!/bin/bash

set -e

if test "${MAINTESTOPTIONS+set}" != set ; then
	source $(dirname $0)/test.inc
	STANDALONE="true"
else
	STANDALONE=""
fi

mkdir gpgtestdir
chmod go-rwx gpgtestdir
export GNUPGHOME="`pwd`/gpgtestdir"
gpg --import $SRCDIR/tests/good.key $SRCDIR/tests/evil.key $SRCDIR/tests/expired.key $SRCDIR/tests/revoked.key $SRCDIR/tests/expiredwithsubkey-working.key $SRCDIR/tests/withsubkeys-works.key

CURDATE="$(date +"%Y-%m-%d")"

mkdir conf lists
cat > conf/distributions <<CONFEND
Codename: Test
Architectures: source
Components: everything
Update: rule otherrule
CONFEND
cat > conf/updates <<CONFEND
Name: commonbase
Method: file:$WORKDIR/test
VerifyRelease: 111
Suite: test

Name: rule
From: commonbase

Name: otherrule
From: commonbase
CONFEND

testrun - -b . update Test 3<<EOF
return 255
stdout
-v2*=Created directory "./db"
stderr
*=Error: Too short key id '111' in VerifyRelease condition '111'!
-v0*=There have been errors!
EOF

cat > conf/updates <<CONFEND
Name: commonbase
Method: file:$WORKDIR/test
VerifyRelease: 11111111 22222222
Suite: test

Name: rule
From: commonbase

Name: otherrule
From: commonbase
CONFEND

testrun - -b . update Test 3<<EOF
return 255
stdout
stderr
*=Error: Space separated key-ids in VerifyRelease condition '11111111 22222222'!
*=(Alternate keys can be separated with '|'. Do not put spaces in key-ids.)
-v0*=There have been errors!
EOF

cat > conf/updates <<CONFEND
Name: commonbase
Method: file:$WORKDIR/test
VerifyRelease: 11111111
Suite: test

Name: rule
From: commonbase

Name: otherrule
From: commonbase
CONFEND

testrun - -b . update Test 3<<EOF
return 249
stdout
stderr
*=Error: unknown key '11111111'!
-v0*=There have been errors!
EOF

cat > conf/updates <<CONFEND
Name: commonbase
Method: file:$WORKDIR/test
VerifyRelease: 11111111

Name: rule
From: commonbase
VerifyRelease: DC3C29B8|685AF714
Suite: test

Name: otherrule
From: commonbase
VerifyRelease: 685AF714|D04DD3D6
Suite: test
CONFEND

mkdir test
mkdir test/dists
mkdir test/dists/test
cat > test/dists/test/Release <<EOF
Codename: test
Components: everything
Architectures: coal
EOF

gpg --list-secret-keys
gpg --expert --sign -b -u 60DDED5B -u D7A5D887 -u revoked@nowhere.tld --output test/dists/test/Release.gpg test/dists/test/Release
gpg --expert --sign -b -u 60DDED5B -u D7A5D887 -u good@nowhere.tld --output test/dists/test/Release.gpg.good test/dists/test/Release
gpg --expert -a --sign -b -u evil@nowhere.tld --output test/dists/test/Release.gpg.evil test/dists/test/Release

rm -r gpgtestdir
mkdir gpgtestdir
chmod go-rwx gpgtestdir
gpg --import $SRCDIR/tests/good.key $SRCDIR/tests/evil.key $SRCDIR/tests/expired.key $SRCDIR/tests/revoked.key $SRCDIR/tests/revoked.pkey $SRCDIR/tests/expiredwithsubkey.key $SRCDIR/tests/withsubkeys.key
gpg --list-keys

testrun - -b . update Test 3<<EOF
return 255
stderr
*=VerifyRelease condition 'DC3C29B8|685AF714' lists revoked key '72F1D61F685AF714'.
*=(To use it anyway, append it with a '!' to force usage).
-v0*=There have been errors!
stdout
EOF

sed -e 's/685AF714/&!/' -i conf/updates

testrun - -b . update Test 3<<EOF
return 255
stderr
*=VerifyRelease condition '685AF714!|D04DD3D6' lists expired key '894FA29DD04DD3D6'.
*=(To use it anyway, append it with a '!' to force usage).
-v0*=There have been errors!
stdout
EOF

sed -e 's/D04DD3D6/&!/' -i conf/updates

testrun - -b . update Test 3<<EOF
return 250
stderr
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release' to './lists/commonbase_test_Release'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release.gpg'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release.gpg' to './lists/commonbase_test_Release.gpg'...
*=Not accepting valid signature in './lists/commonbase_test_Release.gpg' with REVOKED '12D6C95C8C737389EAAF535972F1D61F685AF714'
*=(To ignore it append a ! to the key and run reprepro with --ignore=revokedkey)
*=ERROR: Condition '685AF714!|D04DD3D6!' not fullfilled for './lists/commonbase_test_Release.gpg'.
*=Signatures in './lists/commonbase_test_Release.gpg':
*='DCAD3A286F5178E2F4B09330A573FEB160DDED5B' (signed ${CURDATE}): valid
*='236B4B98B5087AF4B621CB14D8A28B7FD7A5D887' (signed ${CURDATE}): valid
*='12D6C95C8C737389EAAF535972F1D61F685AF714' (signed ${CURDATE}): key revoced
*=Error: Not enough signatures found for remote repository commonbase (file:${WORKDIR}/test test)!
-v0*=There have been errors!
stdout
EOF

testrun - --ignore=revokedkey -b . update Test 3<<EOF
return 255
stderr
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release' to './lists/commonbase_test_Release'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release.gpg'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release.gpg' to './lists/commonbase_test_Release.gpg'...
*=WARNING: valid signature in './lists/commonbase_test_Release.gpg' with revoked '12D6C95C8C737389EAAF535972F1D61F685AF714' is accepted as requested!
*=Missing checksums in Release file './lists/commonbase_test_Release'!
-v0*=There have been errors!
stdout
EOF

cp test/dists/test/Release.gpg.good test/dists/test/Release.gpg

testrun - -b . update Test 3<<EOF
return 250
stderr
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release' to './lists/commonbase_test_Release'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release.gpg'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release.gpg' to './lists/commonbase_test_Release.gpg'...
*=ERROR: Condition '685AF714!|D04DD3D6!' not fullfilled for './lists/commonbase_test_Release.gpg'.
*=Signatures in './lists/commonbase_test_Release.gpg':
*='DCAD3A286F5178E2F4B09330A573FEB160DDED5B' (signed ${CURDATE}): valid
*='236B4B98B5087AF4B621CB14D8A28B7FD7A5D887' (signed ${CURDATE}): valid
*='12E94E82B6D7A883AF6EC8E980F4C43EDC3C29B8' (signed ${CURDATE}): valid
*=Error: Not enough signatures found for remote repository commonbase (file:${WORKDIR}/test test)!
-v0*=There have been errors!
stdout
EOF

# different order
cat > conf/updates <<CONFEND
Name: commonbase
Method: file:$WORKDIR/test
VerifyRelease: 11111111

Name: rule
From: commonbase
VerifyRelease: 685AF714!|D04DD3D6!
Suite: test

Name: otherrule
From: commonbase
VerifyRelease: DC3C29B8|685AF714!
Suite: test
CONFEND

testrun - -b . update Test 3<<EOF
return 250
stderr
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release' to './lists/commonbase_test_Release'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release.gpg'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release.gpg' to './lists/commonbase_test_Release.gpg'...
*=ERROR: Condition '685AF714!|D04DD3D6!' not fullfilled for './lists/commonbase_test_Release.gpg'.
*=Signatures in './lists/commonbase_test_Release.gpg':
*='DCAD3A286F5178E2F4B09330A573FEB160DDED5B' (signed ${CURDATE}): valid
*='236B4B98B5087AF4B621CB14D8A28B7FD7A5D887' (signed ${CURDATE}): valid
*='12E94E82B6D7A883AF6EC8E980F4C43EDC3C29B8' (signed ${CURDATE}): valid
*=Error: Not enough signatures found for remote repository commonbase (file:${WORKDIR}/test test)!
-v0*=There have been errors!
stdout
EOF

# now subkeys:
cat > conf/updates <<CONFEND
Name: commonbase
Method: file:$WORKDIR/test
VerifyRelease: F62C6D3B

Name: rule
From: commonbase
VerifyRelease: D7A5D887
Suite: test

Name: otherrule
From: commonbase
Suite: test
CONFEND

testrun - -b . update Test 3<<EOF
return 250
stderr
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release' to './lists/commonbase_test_Release'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release.gpg'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release.gpg' to './lists/commonbase_test_Release.gpg'...
*=ERROR: Condition 'F62C6D3B' not fullfilled for './lists/commonbase_test_Release.gpg'.
*=Signatures in './lists/commonbase_test_Release.gpg':
*='DCAD3A286F5178E2F4B09330A573FEB160DDED5B' (signed ${CURDATE}): valid
*='236B4B98B5087AF4B621CB14D8A28B7FD7A5D887' (signed ${CURDATE}): valid
*='12E94E82B6D7A883AF6EC8E980F4C43EDC3C29B8' (signed ${CURDATE}): valid
*=Error: Not enough signatures found for remote repository commonbase (file:${WORKDIR}/test test)!
-v0*=There have been errors!
stdout
EOF

sed -e 's/F62C6D3B/F62C6D3B+/' -i conf/updates

testrun - -b . update Test 3<<EOF
return 255
stderr
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release' to './lists/commonbase_test_Release'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release.gpg'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release.gpg' to './lists/commonbase_test_Release.gpg'...
*=Missing checksums in Release file './lists/commonbase_test_Release'!
-v0*=There have been errors!
stdout
EOF

# now subkey of an expired key
cat > conf/updates <<CONFEND
Name: commonbase
Method: file:$WORKDIR/test
VerifyRelease: 60DDED5B!

Name: rule
From: commonbase
Suite: test

Name: otherrule
From: commonbase
Suite: test
CONFEND

testrun - -b . update Test 3<<EOF
return 250
stderr
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release' to './lists/commonbase_test_Release'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release.gpg'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release.gpg' to './lists/commonbase_test_Release.gpg'...
*=Not accepting valid signature in './lists/commonbase_test_Release.gpg' with parent-EXPIRED 'DCAD3A286F5178E2F4B09330A573FEB160DDED5B'
*=(To ignore it append a ! to the key and run reprepro with --ignore=expiredkey)
*=ERROR: Condition '60DDED5B!' not fullfilled for './lists/commonbase_test_Release.gpg'.
*=Signatures in './lists/commonbase_test_Release.gpg':
*='DCAD3A286F5178E2F4B09330A573FEB160DDED5B' (signed ${CURDATE}): valid
*='236B4B98B5087AF4B621CB14D8A28B7FD7A5D887' (signed ${CURDATE}): valid
*='12E94E82B6D7A883AF6EC8E980F4C43EDC3C29B8' (signed ${CURDATE}): valid
*=Error: Not enough signatures found for remote repository commonbase (file:${WORKDIR}/test test)!
-v0*=There have been errors!
stdout
EOF

# now listing the expired key, of which we use an non-expired subkey
cat > conf/updates <<CONFEND
Name: commonbase
Method: file:$WORKDIR/test
VerifyRelease: A260449A!+

Name: rule
From: commonbase
Suite: test

Name: otherrule
From: commonbase
Suite: test
CONFEND

testrun - -b . update Test 3<<EOF
return 250
stderr
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release' to './lists/commonbase_test_Release'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release.gpg'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release.gpg' to './lists/commonbase_test_Release.gpg'...
*=Not accepting valid signature in './lists/commonbase_test_Release.gpg' with parent-EXPIRED 'DCAD3A286F5178E2F4B09330A573FEB160DDED5B'
*=(To ignore it append a ! to the key and run reprepro with --ignore=expiredkey)
*=ERROR: Condition 'A260449A!+' not fullfilled for './lists/commonbase_test_Release.gpg'.
*=Signatures in './lists/commonbase_test_Release.gpg':
*='DCAD3A286F5178E2F4B09330A573FEB160DDED5B' (signed ${CURDATE}): valid
*='236B4B98B5087AF4B621CB14D8A28B7FD7A5D887' (signed ${CURDATE}): valid
*='12E94E82B6D7A883AF6EC8E980F4C43EDC3C29B8' (signed ${CURDATE}): valid
*=Error: Not enough signatures found for remote repository commonbase (file:${WORKDIR}/test test)!
-v0*=There have been errors!
stdout
EOF

# Now testing what happens when only signed with a totally different key:
cp test/dists/test/Release.gpg.evil test/dists/test/Release.gpg

testrun - -b . update Test 3<<EOF
return 250
stderr
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release' to './lists/commonbase_test_Release'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release.gpg'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release.gpg' to './lists/commonbase_test_Release.gpg'...
*=ERROR: Condition 'A260449A!+' not fullfilled for './lists/commonbase_test_Release.gpg'.
*=Signatures in './lists/commonbase_test_Release.gpg':
*='FDC7D039CCC83CC4921112A09FA943670C672A4A' (signed ${CURDATE}): valid
*=Error: Not enough signatures found for remote repository commonbase (file:${WORKDIR}/test test)!
-v0*=There have been errors!
stdout
EOF

# Now testing an expired signature:
cat > conf/updates <<CONFEND
Name: commonbase
Method: file:$WORKDIR/test
VerifyRelease: F62C6D3B+

Name: rule
From: commonbase
VerifyRelease: F62C6D3B
Suite: test

Name: otherrule
From: commonbase
Suite: test
CONFEND

# expired signatures are not that easy to fake, to cat it:
cat > test/dists/test/Release.gpg <<'EOF'
-----BEGIN PGP SIGNATURE-----
Version: GnuPG v1.4.9 (GNU/Linux)

iKIEAAECAAwFAknjKV8FgwABUYAACgkQFU9je/YsbTvOMwQAhyMjhSCosJtdvMSV
l3OUSmHplKZZizJDO9YqO/018I2iSWgpnRxsEX4kmf07qwHjUOYXF3ezaEYWoK1H
B5rLqWuju5lwXpPjOF1b1X/0lzyBmLT380gbMa9Nkgjxq2viX/eP9UJKeKKidmrg
zWLyB0i6AbOlZw4eE+RCQyUqheI=
=1UvF
-----END PGP SIGNATURE-----
EOF

testrun - -b . update Test 3<<EOF
return 250
stderr
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release' to './lists/commonbase_test_Release'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release.gpg'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release.gpg' to './lists/commonbase_test_Release.gpg'...
*=Not accepting valid but EXPIRED signature in './lists/commonbase_test_Release.gpg' with '2938A0D8CD4E20437CAE9CE4154F637BF62C6D3B'
*=(To ignore it append a ! to the key and run reprepro with --ignore=expiredsignature)
*=ERROR: Condition 'F62C6D3B+' not fullfilled for './lists/commonbase_test_Release.gpg'.
*=Signatures in './lists/commonbase_test_Release.gpg':
*='2938A0D8CD4E20437CAE9CE4154F637BF62C6D3B' (signed 2009-04-13): expired signature (since 2009-04-14)
*=Error: Not enough signatures found for remote repository commonbase (file:${WORKDIR}/test test)!
-v0*=There have been errors!
stdout
EOF

testrun - --ignore=expiredsignature -b . update Test 3<<EOF
return 250
stderr
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release' to './lists/commonbase_test_Release'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release.gpg'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release.gpg' to './lists/commonbase_test_Release.gpg'...
*=Not accepting valid but EXPIRED signature in './lists/commonbase_test_Release.gpg' with '2938A0D8CD4E20437CAE9CE4154F637BF62C6D3B'
*=(To ignore it append a ! to the key and run reprepro with --ignore=expiredsignature)
*=ERROR: Condition 'F62C6D3B+' not fullfilled for './lists/commonbase_test_Release.gpg'.
*=Signatures in './lists/commonbase_test_Release.gpg':
*='2938A0D8CD4E20437CAE9CE4154F637BF62C6D3B' (signed 2009-04-13): expired signature (since 2009-04-14)
*=Error: Not enough signatures found for remote repository commonbase (file:${WORKDIR}/test test)!
-v0*=There have been errors!
stdout
EOF

sed -e 's/F62C6D3B/&!/' -i conf/updates

testrun - --ignore=expiredsignature -b . update Test 3<<EOF
return 255
stderr
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release' to './lists/commonbase_test_Release'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release.gpg'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release.gpg' to './lists/commonbase_test_Release.gpg'...
*=WARNING: valid but expired signature in './lists/commonbase_test_Release.gpg' with '2938A0D8CD4E20437CAE9CE4154F637BF62C6D3B' is accepted as requested!
*=Missing checksums in Release file './lists/commonbase_test_Release'!
-v0*=There have been errors!
stdout
EOF

#empty file:
cat > test/dists/test/Release.gpg <<EOF
EOF

testrun - -b . update Test 3<<EOF
return 251
stderr
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release' to './lists/commonbase_test_Release'...
-v1*=aptmethod got 'file:${WORKDIR}/test/dists/test/Release.gpg'
-v2*=Copy file '${WORKDIR}/test/dists/test/Release.gpg' to './lists/commonbase_test_Release.gpg'...
*=Error verifying './lists/commonbase_test_Release.gpg':
*=gpgme gave error GPGME:58:  No data
-v0*=There have been errors!
stdout
EOF

rm -rf db conf gpgtestdir gpgtestdir lists test

if test x$STANDALONE = xtrue ; then
	set +v +x
	echo
	echo "If the script is still running to show this,"
	echo "all tested cases seem to work. (Though writing some tests more can never harm)."
fi
exit 0
