#!/bin/bash

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

dodo test ! -d db
mkdir -p conf
echo "export never" > conf/options
cat > conf/distributions <<EOF
Codename: breakme
Components: something
Architectures: $FAKEARCHITECTURE coal source
Tracking: all
EOF

DISTRI=breakme PACKAGE=aa EPOCH="" VERSION=1 REVISION=-1 SECTION="base" genpackage.sh -sa

testrun - include breakme test.changes 3<<EOF
stderr
=Data seems not to be signed trying to use directly...
=Warning: database 'breakme|something|abacus' was modified but no index file was exported.
=Warning: database 'breakme|something|coal' was modified but no index file was exported.
=Warning: database 'breakme|something|source' was modified but no index file was exported.
=Changes will only be visible after the next 'export'!
stdout
-v2*=Created directory "./db"
-v2*=Created directory "./pool"
-v2*=Created directory "./pool/something"
-v2*=Created directory "./pool/something/a"
-v2*=Created directory "./pool/something/a/aa"
-d1*=db: 'pool/something/a/aa/aa-addons_1-1_all.deb' added to checksums.db(pool).
-d1*=db: 'pool/something/a/aa/aa_1-1_${FAKEARCHITECTURE}.deb' added to checksums.db(pool).
-d1*=db: 'pool/something/a/aa/aa_1-1.tar.gz' added to checksums.db(pool).
-d1*=db: 'pool/something/a/aa/aa_1-1.dsc' added to checksums.db(pool).
-d1*=db: 'aa-addons' added to packages.db(breakme|something|${FAKEARCHITECTURE}).
-d1*=db: 'aa-addons' added to packages.db(breakme|something|coal).
-d1*=db: 'aa' added to packages.db(breakme|something|${FAKEARCHITECTURE}).
-d1*=db: 'aa' added to packages.db(breakme|something|source).
-d1*=db: 'aa' added to tracking.db(breakme).
EOF
rm aa_* aa-addons* test.changes

dodo mv db/tracking.db .

testrun - removesrc  breakme aa 3<<EOF
stderr
*=Nothing about source package 'aa' found in the tracking data of 'breakme'!
*=This either means nothing from this source in this version is there,
*=or the tracking information might be out of date.
EOF

testrun - --keepunreferenced remove breakme aa aa-addons 3<<EOF
stderr
*=Could not found tracking data for aa_1-1 in breakme to remove old files from it.
*=Warning: database 'breakme|something|abacus' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
*=Warning: database 'breakme|something|coal' was modified but no index file was exported.
*=Warning: database 'breakme|something|source' was modified but no index file was exported.
stdout
-v1*=removing 'aa' from 'breakme|something|abacus'...
-d1*=db: 'aa' removed from packages.db(breakme|something|abacus).
-v1*=removing 'aa-addons' from 'breakme|something|abacus'...
-d1*=db: 'aa-addons' removed from packages.db(breakme|something|abacus).
-v1*=removing 'aa-addons' from 'breakme|something|coal'...
-d1*=db: 'aa-addons' removed from packages.db(breakme|something|coal).
-v1*=removing 'aa' from 'breakme|something|source'...
-d1*=db: 'aa' removed from packages.db(breakme|something|source).
EOF

dodo mv tracking.db db/

testrun - --keepunreferenced removesrc breakme aa 3<<EOF
stderr
*=Warning: tracking data might be incosistent:
*=cannot find 'aa' in 'breakme|something|abacus', but 'pool/something/a/aa/aa_1-1_abacus.deb' should be there.
*=cannot find 'aa' in 'breakme|something|source', but 'pool/something/a/aa/aa_1-1.dsc' should be there.
*=There was an inconsistency in the tracking data of 'breakme':
*='pool/something/a/aa/aa-addons_1-1_all.deb' has refcount > 0, but was nowhere found.
*='pool/something/a/aa/aa_1-1_abacus.deb' has refcount > 0, but was nowhere found.
*='pool/something/a/aa/aa_1-1.dsc' has refcount > 0, but was nowhere found.
*='pool/something/a/aa/aa_1-1.tar.gz' has refcount > 0, but was nowhere found.
stdout
-d1*=db: 'aa' '1-1' removed from tracking.db(breakme).
-v1*=4 files lost their last reference.
-v1*=(dumpunreferenced lists such files, use deleteunreferenced to delete them.)
EOF

testrun - retrack breakme 3<<EOF
stderr
stdout
-v1*=Retracking breakme...
EOF

rm -r db conf pool
testsuccess
