#!/bin/bash

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

mkdir conf
cat > conf/options <<EOF
morguedir ./morgue
export never
EOF
cat > conf/distributions <<EOF
Codename: test
Architectures: source
Components: main
EOF
cat > fake.dsc <<EOF
Format: 1.0
Source: bla
Binary: bla
Architecture: all
Section: whatever
Priority: important
Version: 1.7
Maintainer: nobody <nobody@localhost>
Files:
EOF


testrun - -C main includedsc test fake.dsc 3<<EOF
stderr
=Data seems not to be signed trying to use directly...
*=Warning: database 'test|main|source' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-v2*=Created directory "./pool"
-v2*=Created directory "./pool/main"
-v2*=Created directory "./pool/main/b"
-v2*=Created directory "./pool/main/b/bla"
-v2*=Created directory "./db"
-d1*=db: 'pool/main/b/bla/bla_1.7.dsc' added to checksums.db(pool).
-d1*=db: 'bla' added to packages.db(test|main|source).
EOF

testrun - remove test bla 3<<EOF
stderr
*=Warning: database 'test|main|source' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-v1*=removing 'bla' from 'test|main|source'...
-d1*=db: 'bla' removed from packages.db(test|main|source).
-v0*=Deleting files no longer referenced...
-v1*=deleting and forgetting pool/main/b/bla/bla_1.7.dsc
-v2*=Created directory "./morgue"
-v2*=removed now empty directory ./pool/main/b/bla
-v2*=removed now empty directory ./pool/main/b
-v2*=removed now empty directory ./pool/main
-v2*=removed now empty directory ./pool
-d1*=db: 'pool/main/b/bla/bla_1.7.dsc' removed from checksums.db(pool).
EOF

ls -la morgue
dodo test -f morgue/bla_1.7.dsc
dodo test ! -e pool

rm -r morgue
# test what happens if one cannot write there:
mkdir morgue
chmod a-w morgue

testrun - -C main includedsc test fake.dsc 3<<EOF
stderr
=Data seems not to be signed trying to use directly...
*=Warning: database 'test|main|source' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-v2*=Created directory "./pool"
-v2*=Created directory "./pool/main"
-v2*=Created directory "./pool/main/b"
-v2*=Created directory "./pool/main/b/bla"
-d1*=db: 'pool/main/b/bla/bla_1.7.dsc' added to checksums.db(pool).
-d1*=db: 'bla' added to packages.db(test|main|source).
EOF

testrun - remove test bla 3<<EOF
stderr
*=Warning: database 'test|main|source' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-v1*=removing 'bla' from 'test|main|source'...
-d1*=db: 'bla' removed from packages.db(test|main|source).
-v0*=Deleting files no longer referenced...
-v1*=deleting and forgetting pool/main/b/bla/bla_1.7.dsc
stderr
*=error 13 creating morgue-file ./morgue/bla_1.7.dsc: Permission denied
-v0*=There have been errors!
returns 243
EOF

find morgue -mindepth 1 | sort > results
cat > results.expected <<EOF
EOF
dodiff results.expected results

# if it could not be moved to the morgue, it should stay in the pool:
testrun - dumpunreferenced 3<<EOF
stdout
*=pool/main/b/bla/bla_1.7.dsc
EOF

# and deleting it there of course fails again:
testrun - deleteunreferenced 3<<EOF
stdout
-v1*=deleting and forgetting pool/main/b/bla/bla_1.7.dsc
stderr
*=error 13 creating morgue-file ./morgue/bla_1.7.dsc: Permission denied
-v0*=There have been errors!
returns 243
EOF

# if it could not be moved to the morgue, it should stay in the pool:
testrun - dumpunreferenced 3<<EOF
stdout
*=pool/main/b/bla/bla_1.7.dsc
EOF

chmod u+w morgue

# now it should work:
testrun - deleteunreferenced 3<<EOF
stdout
-v1*=deleting and forgetting pool/main/b/bla/bla_1.7.dsc
-v2*=removed now empty directory ./pool/main/b/bla
-v2*=removed now empty directory ./pool/main/b
-v2*=removed now empty directory ./pool/main
-v2*=removed now empty directory ./pool
-d1*=db: 'pool/main/b/bla/bla_1.7.dsc' removed from checksums.db(pool).
EOF
find morgue -mindepth 1 | sort > results
cat > results.expected <<EOF
morgue/bla_1.7.dsc
EOF
dodiff results.expected results
# and be gone:
testrun empty dumpunreferenced



ls -la morgue
dodo test -f morgue/bla_1.7.dsc
dodo test ! -e pool

# Next test: what if the file is missing?

testrun - -C main includedsc test fake.dsc 3<<EOF
stderr
=Data seems not to be signed trying to use directly...
*=Warning: database 'test|main|source' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-v2*=Created directory "./pool"
-v2*=Created directory "./pool/main"
-v2*=Created directory "./pool/main/b"
-v2*=Created directory "./pool/main/b/bla"
-d1*=db: 'pool/main/b/bla/bla_1.7.dsc' added to checksums.db(pool).
-d1*=db: 'bla' added to packages.db(test|main|source).
EOF

dodo rm pool/main/b/bla/bla_1.7.dsc

testrun - remove test bla 3<<EOF
stderr
*=Warning: database 'test|main|source' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-v1*=removing 'bla' from 'test|main|source'...
-d1*=db: 'bla' removed from packages.db(test|main|source).
-v0*=Deleting files no longer referenced...
-v1*=deleting and forgetting pool/main/b/bla/bla_1.7.dsc
stderr
*=./pool/main/b/bla/bla_1.7.dsc not found, forgetting anyway
stdout
-d1*=db: 'pool/main/b/bla/bla_1.7.dsc' removed from checksums.db(pool).
EOF

find morgue -mindepth 1 | sort > results
cat > results.expected <<EOF
morgue/bla_1.7.dsc
EOF
dodiff results.expected results

# Next test: file cannot be moved

testrun - -C main includedsc test fake.dsc 3<<EOF
stderr
=Data seems not to be signed trying to use directly...
*=Warning: database 'test|main|source' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-d1*=db: 'pool/main/b/bla/bla_1.7.dsc' added to checksums.db(pool).
-d1*=db: 'bla' added to packages.db(test|main|source).
EOF

dodo chmod a-w pool/main/b/bla

testrun - remove test bla 3<<EOF
stderr
*=Warning: database 'test|main|source' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-v1*=removing 'bla' from 'test|main|source'...
-d1*=db: 'bla' removed from packages.db(test|main|source).
-v0*=Deleting files no longer referenced...
-v1*=deleting and forgetting pool/main/b/bla/bla_1.7.dsc
stderr
*=error 13 while unlinking ./pool/main/b/bla/bla_1.7.dsc: Permission denied
-v0*=There have been errors!
returns 243
EOF

dodo chmod u+w pool/main/b/bla

find morgue -mindepth 1 | sort > results
cat > results.expected <<EOF
morgue/bla_1.7.dsc
EOF
dodiff results.expected results
testrun - dumpunreferenced 3<<EOF
stdout
*=pool/main/b/bla/bla_1.7.dsc
EOF

# now it should work:
testrun - deleteunreferenced 3<<EOF
stdout
-v1*=deleting and forgetting pool/main/b/bla/bla_1.7.dsc
-v2*=removed now empty directory ./pool/main/b/bla
-v2*=removed now empty directory ./pool/main/b
-v2*=removed now empty directory ./pool/main
-v2*=removed now empty directory ./pool
-d1*=db: 'pool/main/b/bla/bla_1.7.dsc' removed from checksums.db(pool).
EOF
find morgue -mindepth 1 | sort > results
cat > results.expected <<EOF
morgue/bla_1.7.dsc
morgue/bla_1.7.dsc-1
EOF
dodiff results.expected results
# and be gone:
testrun empty dumpunreferenced

# Test symbolic link:
testrun - -C main includedsc test fake.dsc 3<<EOF
stderr
=Data seems not to be signed trying to use directly...
*=Warning: database 'test|main|source' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-v2*=Created directory "./pool"
-v2*=Created directory "./pool/main"
-v2*=Created directory "./pool/main/b"
-v2*=Created directory "./pool/main/b/bla"
-d1*=db: 'pool/main/b/bla/bla_1.7.dsc' added to checksums.db(pool).
-d1*=db: 'bla' added to packages.db(test|main|source).
EOF

dodo mv pool/main/b/bla/bla_1.7.dsc pool/main/b/bla/bla_1.7.dscc
dodo ln -s bla_1.7.dscc pool/main/b/bla/bla_1.7.dsc

testrun - remove test bla 3<<EOF
stderr
*=Warning: database 'test|main|source' was modified but no index file was exported.
*=Changes will only be visible after the next 'export'!
stdout
-v1*=removing 'bla' from 'test|main|source'...
-d1*=db: 'bla' removed from packages.db(test|main|source).
-v0*=Deleting files no longer referenced...
-v1*=deleting and forgetting pool/main/b/bla/bla_1.7.dsc
-d1*=db: 'pool/main/b/bla/bla_1.7.dsc' removed from checksums.db(pool).
EOF

ls -l morgue
find morgue -mindepth 1 | sort > results
cat > results.expected <<EOF
morgue/bla_1.7.dsc
morgue/bla_1.7.dsc-1
EOF
dodiff results.expected results

dodo mv pool/main/b/bla/bla_1.7.dscc pool/main/b/bla/bla_1.7.dsc
testrun - _detect pool/main/b/bla/bla_1.7.dsc 3<<EOF
stdout
-d1*=db: 'pool/main/b/bla/bla_1.7.dsc' added to checksums.db(pool).
-v0*=1 files were added but not used.
-v0*=The next deleteunreferenced call will delete them.
EOF

dodo chmod a-r pool/main/b/bla/bla_1.7.dsc
testrun - deleteunreferenced 3<<EOF
stdout
-v1*=deleting and forgetting pool/main/b/bla/bla_1.7.dsc
-d1*=db: 'pool/main/b/bla/bla_1.7.dsc' removed from checksums.db(pool).
-v2*=removed now empty directory ./pool/main/b/bla
-v2*=removed now empty directory ./pool/main/b
-v2*=removed now empty directory ./pool/main
-v2*=removed now empty directory ./pool
EOF
ls -l morgue
find morgue -mindepth 1 | sort > results
cat > results.expected <<EOF
morgue/bla_1.7.dsc
morgue/bla_1.7.dsc-1
morgue/bla_1.7.dsc-2
EOF
dodiff results.expected results

# TODO: is there a way to check if failing copying is handled correctly?
# that needs a file not readable, not renameable to morgue, but can be unlinked...

# TODO: check if things like a failed include work correctly
# (they should only copy things to the morgue that were in the pool previously)

dodo test ! -e pool
rm -r db morgue fake.dsc conf results results.expected
testsuccess
