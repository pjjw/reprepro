#!/bin/bash

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

dodo test ! -d db
testrun - -b . _versioncompare 0 1 3<<EOF
stdout
*='0' is smaller than '1'.
EOF
dodo test ! -d db
mkdir -p conf
cat > conf/distributions <<EOF
Codename: foo/updates
Components: a bb ccc dddd
UDebComponents: a dddd
Architectures: x source
EOF
testrun - -b . export foo/updates 3<<EOF
stderr
stdout
-v2*=Created directory "./db"
-v1*=Exporting foo/updates...
-v2*=Created directory "./dists"
-v2*=Created directory "./dists/foo"
-v2*=Created directory "./dists/foo/updates"
-v2*=Created directory "./dists/foo/updates/a"
-v2*=Created directory "./dists/foo/updates/a/binary-x"
-v6*= exporting 'foo/updates|a|x'...
-v6*=  creating './dists/foo/updates/a/binary-x/Packages' (uncompressed,gzipped)
-v2*=Created directory "./dists/foo/updates/a/debian-installer"
-v2*=Created directory "./dists/foo/updates/a/debian-installer/binary-x"
-v6*= exporting 'u|foo/updates|a|x'...
-v6*=  creating './dists/foo/updates/a/debian-installer/binary-x/Packages' (uncompressed,gzipped)
-v2*=Created directory "./dists/foo/updates/a/source"
-v6*= exporting 'foo/updates|a|source'...
-v6*=  creating './dists/foo/updates/a/source/Sources' (gzipped)
-v2*=Created directory "./dists/foo/updates/bb"
-v2*=Created directory "./dists/foo/updates/bb/binary-x"
-v6*= exporting 'foo/updates|bb|x'...
-v6*=  creating './dists/foo/updates/bb/binary-x/Packages' (uncompressed,gzipped)
-v2*=Created directory "./dists/foo/updates/bb/source"
-v6*= exporting 'foo/updates|bb|source'...
-v6*=  creating './dists/foo/updates/bb/source/Sources' (gzipped)
-v2*=Created directory "./dists/foo/updates/ccc"
-v2*=Created directory "./dists/foo/updates/ccc/binary-x"
-v6*= exporting 'foo/updates|ccc|x'...
-v6*=  creating './dists/foo/updates/ccc/binary-x/Packages' (uncompressed,gzipped)
-v2*=Created directory "./dists/foo/updates/ccc/source"
-v6*= exporting 'foo/updates|ccc|source'...
-v6*=  creating './dists/foo/updates/ccc/source/Sources' (gzipped)
-v2*=Created directory "./dists/foo/updates/dddd"
-v2*=Created directory "./dists/foo/updates/dddd/binary-x"
-v6*= exporting 'foo/updates|dddd|x'...
-v6*=  creating './dists/foo/updates/dddd/binary-x/Packages' (uncompressed,gzipped)
-v2*=Created directory "./dists/foo/updates/dddd/debian-installer"
-v2*=Created directory "./dists/foo/updates/dddd/debian-installer/binary-x"
-v6*= exporting 'u|foo/updates|dddd|x'...
-v6*=  creating './dists/foo/updates/dddd/debian-installer/binary-x/Packages' (uncompressed,gzipped)
-v2*=Created directory "./dists/foo/updates/dddd/source"
-v6*= exporting 'foo/updates|dddd|source'...
-v6*=  creating './dists/foo/updates/dddd/source/Sources' (gzipped)
EOF
cat > results.expected <<EOF
Codename: foo/updates
Date: unified
Architectures: x
Components: a bb ccc dddd
MD5Sum:
 $EMPTYMD5 a/binary-x/Packages
 $EMPTYGZMD5 a/binary-x/Packages.gz
 62d4df25a6de22ca443076ace929ec5b 29 a/binary-x/Release
 $EMPTYMD5 a/debian-installer/binary-x/Packages
 $EMPTYGZMD5 a/debian-installer/binary-x/Packages.gz
 $EMPTYMD5 a/source/Sources
 $EMPTYGZMD5 a/source/Sources.gz
 bc76dd633c41acb37f24e22bf755dc84 34 a/source/Release
 $EMPTYMD5 bb/binary-x/Packages
 $EMPTYGZMD5 bb/binary-x/Packages.gz
 6b882eefa465a6e3c43d512f7e8da6e4 30 bb/binary-x/Release
 $EMPTYMD5 bb/source/Sources
 $EMPTYGZMD5 bb/source/Sources.gz
 808be3988e695c1ef966f19641383275 35 bb/source/Release
 $EMPTYMD5 ccc/binary-x/Packages
 $EMPTYGZMD5 ccc/binary-x/Packages.gz
 dec38be5c92799814c9113335317a319 31 ccc/binary-x/Release
 $EMPTYMD5 ccc/source/Sources
 $EMPTYGZMD5 ccc/source/Sources.gz
 650f349d34e8e929dfc732abbf90c74e 36 ccc/source/Release
 $EMPTYMD5 dddd/binary-x/Packages
 $EMPTYGZMD5 dddd/binary-x/Packages.gz
 3e4c48246400818d451e65fb03e48f01 32 dddd/binary-x/Release
 $EMPTYMD5 dddd/debian-installer/binary-x/Packages
 $EMPTYGZMD5 dddd/debian-installer/binary-x/Packages.gz
 $EMPTYMD5 dddd/source/Sources
 $EMPTYGZMD5 dddd/source/Sources.gz
 bb7b15c091463b7ea884ccca385f1f0a 37 dddd/source/Release
SHA1:
 $EMPTYSHA1 a/binary-x/Packages
 $EMPTYGZSHA1 a/binary-x/Packages.gz
 f312c487ee55fc60c23e9117c6a664cbbd862ae6 29 a/binary-x/Release
 $EMPTYSHA1 a/debian-installer/binary-x/Packages
 $EMPTYGZSHA1 a/debian-installer/binary-x/Packages.gz
 $EMPTYSHA1 a/source/Sources
 $EMPTYGZSHA1 a/source/Sources.gz
 186977630f5f42744cd6ea6fcf8ea54960992a2f 34 a/source/Release
 $EMPTYSHA1 bb/binary-x/Packages
 $EMPTYGZSHA1 bb/binary-x/Packages.gz
 c4c6cb0f765a9f71682f3d1bfd02279e58609e6b 30 bb/binary-x/Release
 $EMPTYSHA1 bb/source/Sources
 $EMPTYGZSHA1 bb/source/Sources.gz
 59260e2f6e121943909241c125c57aed6fca09ad 35 bb/source/Release
 $EMPTYSHA1 ccc/binary-x/Packages
 $EMPTYGZSHA1 ccc/binary-x/Packages.gz
 7d1913a67637add61ce5ef1ba82eeeb8bc5fe8c6 31 ccc/binary-x/Release
 $EMPTYSHA1 ccc/source/Sources
 $EMPTYGZSHA1 ccc/source/Sources.gz
 a7df74b575289d0697214261e393bc390f428af9 36 ccc/source/Release
 $EMPTYSHA1 dddd/binary-x/Packages
 $EMPTYGZSHA1 dddd/binary-x/Packages.gz
 fc2ab0a76469f8fc81632aa904ceb9c1125ac2c5 32 dddd/binary-x/Release
 $EMPTYSHA1 dddd/debian-installer/binary-x/Packages
 $EMPTYGZSHA1 dddd/debian-installer/binary-x/Packages.gz
 $EMPTYSHA1 dddd/source/Sources
 $EMPTYGZSHA1 dddd/source/Sources.gz
 1d44f88f82a325658ee96dd7e7cee975ffa50e4d 37 dddd/source/Release
SHA256:
 $EMPTYSHA2 a/binary-x/Packages
 $EMPTYGZSHA2 a/binary-x/Packages.gz
 d5e5ba98f784efc26ac8f5ff1f293fab43f37878c92b3da0a7fce39c1da0b463 29 a/binary-x/Release
 $EMPTYSHA2 a/debian-installer/binary-x/Packages
 $EMPTYGZSHA2 a/debian-installer/binary-x/Packages.gz
 $EMPTYSHA2 a/source/Sources
 $EMPTYGZSHA2 a/source/Sources.gz
 edd9dad3b1239657da74dfbf45af401ab810b54236b12386189accc0fbc4befa 34 a/source/Release
 $EMPTYSHA2 bb/binary-x/Packages
 $EMPTYGZSHA2 bb/binary-x/Packages.gz
 2d578ea088ccb77f24a437c4657663e9f5a76939c8a23745f8df9f425cc4c137 30 bb/binary-x/Release
 $EMPTYSHA2 bb/source/Sources
 $EMPTYGZSHA2 bb/source/Sources.gz
 4653987e3d0be59da18afcc446e59a0118dd995a13e976162749017e95e6709a 35 bb/source/Release
 $EMPTYSHA2 ccc/binary-x/Packages
 $EMPTYGZSHA2 ccc/binary-x/Packages.gz
 e46b90afc77272a351bdde96253f57cba5852317546467fc61ae47d7696500a6 31 ccc/binary-x/Release
 $EMPTYSHA2 ccc/source/Sources
 $EMPTYGZSHA2 ccc/source/Sources.gz
 a6ef831ba0cc6044019e4d598c5f2483872cf047cb65949bb68c73c028864d76 36 ccc/source/Release
 $EMPTYSHA2 dddd/binary-x/Packages
 $EMPTYGZSHA2 dddd/binary-x/Packages.gz
 70a6c3a457abe60f107f63f0cdb29ab040a4494fefc55922fff0164c97c7a124 32 dddd/binary-x/Release
 $EMPTYSHA2 dddd/debian-installer/binary-x/Packages
 $EMPTYGZSHA2 dddd/debian-installer/binary-x/Packages.gz
 $EMPTYSHA2 dddd/source/Sources
 $EMPTYGZSHA2 dddd/source/Sources.gz
 504549b725951e79fb2e43149bb0cf42619286284890666b8e9fe5fb0787f306 37 dddd/source/Release
EOF
sed -e 's/^Date: .*/Date: unified/' dists/foo/updates/Release > results
dodiff results.expected results
cat > conf/distributions <<EOF
Codename: foo/updates
Components: a bb ccc dddd
UDebComponents: a dddd
Architectures: x source
FakeComponentPrefix: updates
EOF
testrun - -b . export foo/updates 3<<EOF
stderr
stdout
-v1*=Exporting foo/updates...
-v6*= exporting 'foo/updates|a|x'...
-v6*=  replacing './dists/foo/updates/a/binary-x/Packages' (uncompressed,gzipped)
-v6*= exporting 'u|foo/updates|a|x'...
-v6*=  replacing './dists/foo/updates/a/debian-installer/binary-x/Packages' (uncompressed,gzipped)
-v6*= exporting 'foo/updates|a|source'...
-v6*=  replacing './dists/foo/updates/a/source/Sources' (gzipped)
-v6*= exporting 'foo/updates|bb|x'...
-v6*=  replacing './dists/foo/updates/bb/binary-x/Packages' (uncompressed,gzipped)
-v6*= exporting 'foo/updates|bb|source'...
-v6*=  replacing './dists/foo/updates/bb/source/Sources' (gzipped)
-v6*= exporting 'foo/updates|ccc|x'...
-v6*=  replacing './dists/foo/updates/ccc/binary-x/Packages' (uncompressed,gzipped)
-v6*= exporting 'foo/updates|ccc|source'...
-v6*=  replacing './dists/foo/updates/ccc/source/Sources' (gzipped)
-v6*= exporting 'foo/updates|dddd|x'...
-v6*=  replacing './dists/foo/updates/dddd/binary-x/Packages' (uncompressed,gzipped)
-v6*= exporting 'u|foo/updates|dddd|x'...
-v6*=  replacing './dists/foo/updates/dddd/debian-installer/binary-x/Packages' (uncompressed,gzipped)
-v6*= exporting 'foo/updates|dddd|source'...
-v6*=  replacing './dists/foo/updates/dddd/source/Sources' (gzipped)
EOF
cat > results.expected <<EOF
Codename: foo
Date: unified
Architectures: x
Components: updates/a updates/bb updates/ccc updates/dddd
MD5Sum:
 $EMPTYMD5 a/binary-x/Packages
 $EMPTYGZMD5 a/binary-x/Packages.gz
 62d4df25a6de22ca443076ace929ec5b 29 a/binary-x/Release
 $EMPTYMD5 a/debian-installer/binary-x/Packages
 $EMPTYGZMD5 a/debian-installer/binary-x/Packages.gz
 $EMPTYMD5 a/source/Sources
 $EMPTYGZMD5 a/source/Sources.gz
 bc76dd633c41acb37f24e22bf755dc84 34 a/source/Release
 $EMPTYMD5 bb/binary-x/Packages
 $EMPTYGZMD5 bb/binary-x/Packages.gz
 6b882eefa465a6e3c43d512f7e8da6e4 30 bb/binary-x/Release
 $EMPTYMD5 bb/source/Sources
 $EMPTYGZMD5 bb/source/Sources.gz
 808be3988e695c1ef966f19641383275 35 bb/source/Release
 $EMPTYMD5 ccc/binary-x/Packages
 $EMPTYGZMD5 ccc/binary-x/Packages.gz
 dec38be5c92799814c9113335317a319 31 ccc/binary-x/Release
 $EMPTYMD5 ccc/source/Sources
 $EMPTYGZMD5 ccc/source/Sources.gz
 650f349d34e8e929dfc732abbf90c74e 36 ccc/source/Release
 $EMPTYMD5 dddd/binary-x/Packages
 $EMPTYGZMD5 dddd/binary-x/Packages.gz
 3e4c48246400818d451e65fb03e48f01 32 dddd/binary-x/Release
 $EMPTYMD5 dddd/debian-installer/binary-x/Packages
 $EMPTYGZMD5 dddd/debian-installer/binary-x/Packages.gz
 $EMPTYMD5 dddd/source/Sources
 $EMPTYGZMD5 dddd/source/Sources.gz
 bb7b15c091463b7ea884ccca385f1f0a 37 dddd/source/Release
SHA1:
 $EMPTYSHA1 a/binary-x/Packages
 $EMPTYGZSHA1 a/binary-x/Packages.gz
 f312c487ee55fc60c23e9117c6a664cbbd862ae6 29 a/binary-x/Release
 $EMPTYSHA1 a/debian-installer/binary-x/Packages
 $EMPTYGZSHA1 a/debian-installer/binary-x/Packages.gz
 $EMPTYSHA1 a/source/Sources
 $EMPTYGZSHA1 a/source/Sources.gz
 186977630f5f42744cd6ea6fcf8ea54960992a2f 34 a/source/Release
 $EMPTYSHA1 bb/binary-x/Packages
 $EMPTYGZSHA1 bb/binary-x/Packages.gz
 c4c6cb0f765a9f71682f3d1bfd02279e58609e6b 30 bb/binary-x/Release
 $EMPTYSHA1 bb/source/Sources
 $EMPTYGZSHA1 bb/source/Sources.gz
 59260e2f6e121943909241c125c57aed6fca09ad 35 bb/source/Release
 $EMPTYSHA1 ccc/binary-x/Packages
 $EMPTYGZSHA1 ccc/binary-x/Packages.gz
 7d1913a67637add61ce5ef1ba82eeeb8bc5fe8c6 31 ccc/binary-x/Release
 $EMPTYSHA1 ccc/source/Sources
 $EMPTYGZSHA1 ccc/source/Sources.gz
 a7df74b575289d0697214261e393bc390f428af9 36 ccc/source/Release
 $EMPTYSHA1 dddd/binary-x/Packages
 $EMPTYGZSHA1 dddd/binary-x/Packages.gz
 fc2ab0a76469f8fc81632aa904ceb9c1125ac2c5 32 dddd/binary-x/Release
 $EMPTYSHA1 dddd/debian-installer/binary-x/Packages
 $EMPTYGZSHA1 dddd/debian-installer/binary-x/Packages.gz
 $EMPTYSHA1 dddd/source/Sources
 $EMPTYGZSHA1 dddd/source/Sources.gz
 1d44f88f82a325658ee96dd7e7cee975ffa50e4d 37 dddd/source/Release
SHA256:
 $EMPTYSHA2 a/binary-x/Packages
 $EMPTYGZSHA2 a/binary-x/Packages.gz
 d5e5ba98f784efc26ac8f5ff1f293fab43f37878c92b3da0a7fce39c1da0b463 29 a/binary-x/Release
 $EMPTYSHA2 a/debian-installer/binary-x/Packages
 $EMPTYGZSHA2 a/debian-installer/binary-x/Packages.gz
 $EMPTYSHA2 a/source/Sources
 $EMPTYGZSHA2 a/source/Sources.gz
 edd9dad3b1239657da74dfbf45af401ab810b54236b12386189accc0fbc4befa 34 a/source/Release
 $EMPTYSHA2 bb/binary-x/Packages
 $EMPTYGZSHA2 bb/binary-x/Packages.gz
 2d578ea088ccb77f24a437c4657663e9f5a76939c8a23745f8df9f425cc4c137 30 bb/binary-x/Release
 $EMPTYSHA2 bb/source/Sources
 $EMPTYGZSHA2 bb/source/Sources.gz
 4653987e3d0be59da18afcc446e59a0118dd995a13e976162749017e95e6709a 35 bb/source/Release
 $EMPTYSHA2 ccc/binary-x/Packages
 $EMPTYGZSHA2 ccc/binary-x/Packages.gz
 e46b90afc77272a351bdde96253f57cba5852317546467fc61ae47d7696500a6 31 ccc/binary-x/Release
 $EMPTYSHA2 ccc/source/Sources
 $EMPTYGZSHA2 ccc/source/Sources.gz
 a6ef831ba0cc6044019e4d598c5f2483872cf047cb65949bb68c73c028864d76 36 ccc/source/Release
 $EMPTYSHA2 dddd/binary-x/Packages
 $EMPTYGZSHA2 dddd/binary-x/Packages.gz
 70a6c3a457abe60f107f63f0cdb29ab040a4494fefc55922fff0164c97c7a124 32 dddd/binary-x/Release
 $EMPTYSHA2 dddd/debian-installer/binary-x/Packages
 $EMPTYGZSHA2 dddd/debian-installer/binary-x/Packages.gz
 $EMPTYSHA2 dddd/source/Sources
 $EMPTYGZSHA2 dddd/source/Sources.gz
 504549b725951e79fb2e43149bb0cf42619286284890666b8e9fe5fb0787f306 37 dddd/source/Release
EOF
sed -e 's/^Date: .*/Date: unified/' dists/foo/updates/Release > results
dodiff results.expected results
# Now try with suite
cat > conf/distributions <<EOF
Codename: foo/updates
Suite: bla/updates
Components: a bb ccc dddd
UDebComponents: a dddd
Architectures: x source
FakeComponentPrefix: updates
EOF
testrun - -b . export foo/updates 3<<EOF
stderr
stdout
-v1*=Exporting foo/updates...
-v6*= exporting 'foo/updates|a|x'...
-v6*=  replacing './dists/foo/updates/a/binary-x/Packages' (uncompressed,gzipped)
-v6*= exporting 'u|foo/updates|a|x'...
-v6*=  replacing './dists/foo/updates/a/debian-installer/binary-x/Packages' (uncompressed,gzipped)
-v6*= exporting 'foo/updates|a|source'...
-v6*=  replacing './dists/foo/updates/a/source/Sources' (gzipped)
-v6*= exporting 'foo/updates|bb|x'...
-v6*=  replacing './dists/foo/updates/bb/binary-x/Packages' (uncompressed,gzipped)
-v6*= exporting 'foo/updates|bb|source'...
-v6*=  replacing './dists/foo/updates/bb/source/Sources' (gzipped)
-v6*= exporting 'foo/updates|ccc|x'...
-v6*=  replacing './dists/foo/updates/ccc/binary-x/Packages' (uncompressed,gzipped)
-v6*= exporting 'foo/updates|ccc|source'...
-v6*=  replacing './dists/foo/updates/ccc/source/Sources' (gzipped)
-v6*= exporting 'foo/updates|dddd|x'...
-v6*=  replacing './dists/foo/updates/dddd/binary-x/Packages' (uncompressed,gzipped)
-v6*= exporting 'u|foo/updates|dddd|x'...
-v6*=  replacing './dists/foo/updates/dddd/debian-installer/binary-x/Packages' (uncompressed,gzipped)
-v6*= exporting 'foo/updates|dddd|source'...
-v6*=  replacing './dists/foo/updates/dddd/source/Sources' (gzipped)
EOF
cat > results.expected <<EOF
Suite: bla
Codename: foo
Date: unified
Architectures: x
Components: updates/a updates/bb updates/ccc updates/dddd
MD5Sum:
 $EMPTYMD5 a/binary-x/Packages
 $EMPTYGZMD5 a/binary-x/Packages.gz
 $(md5releaseline foo/updates a/binary-x/Release)
 $EMPTYMD5 a/debian-installer/binary-x/Packages
 $EMPTYGZMD5 a/debian-installer/binary-x/Packages.gz
 $EMPTYMD5 a/source/Sources
 $EMPTYGZMD5 a/source/Sources.gz
 $(md5releaseline foo/updates a/source/Release)
 $EMPTYMD5 bb/binary-x/Packages
 $EMPTYGZMD5 bb/binary-x/Packages.gz
 $(md5releaseline foo/updates bb/binary-x/Release)
 $EMPTYMD5 bb/source/Sources
 $EMPTYGZMD5 bb/source/Sources.gz
 $(md5releaseline foo/updates bb/source/Release)
 $EMPTYMD5 ccc/binary-x/Packages
 $EMPTYGZMD5 ccc/binary-x/Packages.gz
 $(md5releaseline foo/updates ccc/binary-x/Release)
 $EMPTYMD5 ccc/source/Sources
 $EMPTYGZMD5 ccc/source/Sources.gz
 $(md5releaseline foo/updates ccc/source/Release)
 $EMPTYMD5 dddd/binary-x/Packages
 $EMPTYGZMD5 dddd/binary-x/Packages.gz
 $(md5releaseline foo/updates dddd/binary-x/Release)
 $EMPTYMD5 dddd/debian-installer/binary-x/Packages
 $EMPTYGZMD5 dddd/debian-installer/binary-x/Packages.gz
 $EMPTYMD5 dddd/source/Sources
 $EMPTYGZMD5 dddd/source/Sources.gz
 $(md5releaseline foo/updates dddd/source/Release)
SHA1:
 $EMPTYSHA1 a/binary-x/Packages
 $EMPTYGZSHA1 a/binary-x/Packages.gz
 $(sha1releaseline foo/updates a/binary-x/Release)
 $EMPTYSHA1 a/debian-installer/binary-x/Packages
 $EMPTYGZSHA1 a/debian-installer/binary-x/Packages.gz
 $EMPTYSHA1 a/source/Sources
 $EMPTYGZSHA1 a/source/Sources.gz
 $(sha1releaseline foo/updates a/source/Release)
 $EMPTYSHA1 bb/binary-x/Packages
 $EMPTYGZSHA1 bb/binary-x/Packages.gz
 $(sha1releaseline foo/updates bb/binary-x/Release)
 $EMPTYSHA1 bb/source/Sources
 $EMPTYGZSHA1 bb/source/Sources.gz
 $(sha1releaseline foo/updates bb/source/Release)
 $EMPTYSHA1 ccc/binary-x/Packages
 $EMPTYGZSHA1 ccc/binary-x/Packages.gz
 $(sha1releaseline foo/updates ccc/binary-x/Release)
 $EMPTYSHA1 ccc/source/Sources
 $EMPTYGZSHA1 ccc/source/Sources.gz
 $(sha1releaseline foo/updates ccc/source/Release)
 $EMPTYSHA1 dddd/binary-x/Packages
 $EMPTYGZSHA1 dddd/binary-x/Packages.gz
 $(sha1releaseline foo/updates dddd/binary-x/Release)
 $EMPTYSHA1 dddd/debian-installer/binary-x/Packages
 $EMPTYGZSHA1 dddd/debian-installer/binary-x/Packages.gz
 $EMPTYSHA1 dddd/source/Sources
 $EMPTYGZSHA1 dddd/source/Sources.gz
 $(sha1releaseline foo/updates dddd/source/Release)
SHA256:
 $EMPTYSHA2 a/binary-x/Packages
 $EMPTYGZSHA2 a/binary-x/Packages.gz
 $(sha2releaseline foo/updates a/binary-x/Release)
 $EMPTYSHA2 a/debian-installer/binary-x/Packages
 $EMPTYGZSHA2 a/debian-installer/binary-x/Packages.gz
 $EMPTYSHA2 a/source/Sources
 $EMPTYGZSHA2 a/source/Sources.gz
 $(sha2releaseline foo/updates a/source/Release)
 $EMPTYSHA2 bb/binary-x/Packages
 $EMPTYGZSHA2 bb/binary-x/Packages.gz
 $(sha2releaseline foo/updates bb/binary-x/Release)
 $EMPTYSHA2 bb/source/Sources
 $EMPTYGZSHA2 bb/source/Sources.gz
 $(sha2releaseline foo/updates bb/source/Release)
 $EMPTYSHA2 ccc/binary-x/Packages
 $EMPTYGZSHA2 ccc/binary-x/Packages.gz
 $(sha2releaseline foo/updates ccc/binary-x/Release)
 $EMPTYSHA2 ccc/source/Sources
 $EMPTYGZSHA2 ccc/source/Sources.gz
 $(sha2releaseline foo/updates ccc/source/Release)
 $EMPTYSHA2 dddd/binary-x/Packages
 $EMPTYGZSHA2 dddd/binary-x/Packages.gz
 $(sha2releaseline foo/updates dddd/binary-x/Release)
 $EMPTYSHA2 dddd/debian-installer/binary-x/Packages
 $EMPTYGZSHA2 dddd/debian-installer/binary-x/Packages.gz
 $EMPTYSHA2 dddd/source/Sources
 $EMPTYGZSHA2 dddd/source/Sources.gz
 $(sha2releaseline foo/updates dddd/source/Release)
EOF
sed -e 's/^Date: .*/Date: unified/' dists/foo/updates/Release > results
dodiff results.expected results
testrun - -b . createsymlinks 3<<EOF
stderr
-v0*=Creating symlinks with '/' in them is not yet supported:
-v0*=Not creating 'bla/updates' -> 'foo/updates' because of '/'.
stdout
EOF
cat >> conf/distributions <<EOF

Codename: foo
Suite: bla
Architectures: ooooooooooooooooooooooooooooooooooooooooo source
Components:
 x a
EOF
testrun - -b . createsymlinks 3<<EOF
stderr
-v2*=Not creating 'bla/updates' -> 'foo/updates' because of the '/' in it.
-v2*=Hopefully something else will link 'bla' -> 'foo' then this is not needed.
stdout
-v1*=Created ./dists/bla->foo
EOF
# check a .dsc with nothing in it:
cat > test.dsc <<EOF

EOF
testrun - -b . includedsc foo test.dsc 3<<EOF
return 255
stderr
*=Could only find spaces within 'test.dsc'!
-v0*=There have been errors!
stdout
EOF
cat > test.dsc <<EOF
Format: 0.0
Source: test
Version: 0
Maintainer: me <guess@who>
Section: section
Priority: priority
Files:
EOF
testrun - -C a -b . includedsc foo test.dsc 3<<EOF
stderr
-v0=Data seems not to be signed trying to use directly...
stdout
-v2*=Created directory "./pool"
-v2*=Created directory "./pool/a"
-v2*=Created directory "./pool/a/t"
-v2*=Created directory "./pool/a/t/test"
-d1*=db: 'pool/a/t/test/test_0.dsc' added to checksums.db(pool).
-d1*=db: 'test' added to packages.db(foo|a|source).
-v0*=Exporting indices...
-v2*=Created directory "./dists/foo/x"
-v2*=Created directory "./dists/foo/x/binary-ooooooooooooooooooooooooooooooooooooooooo"
-v6*= looking for changes in 'foo|x|ooooooooooooooooooooooooooooooooooooooooo'...
-v6*=  creating './dists/foo/x/binary-ooooooooooooooooooooooooooooooooooooooooo/Packages' (uncompressed,gzipped)
-v2*=Created directory "./dists/foo/x/source"
-v6*= looking for changes in 'foo|x|source'...
-v6*=  creating './dists/foo/x/source/Sources' (gzipped)
-v2*=Created directory "./dists/foo/a"
-v2*=Created directory "./dists/foo/a/binary-ooooooooooooooooooooooooooooooooooooooooo"
-v6*= looking for changes in 'foo|a|ooooooooooooooooooooooooooooooooooooooooo'...
-v6*=  creating './dists/foo/a/binary-ooooooooooooooooooooooooooooooooooooooooo/Packages' (uncompressed,gzipped)
-v2*=Created directory "./dists/foo/a/source"
-v6*= looking for changes in 'foo|a|source'...
-v6*=  creating './dists/foo/a/source/Sources' (gzipped)
EOF
testrun - -b . copy foo/updates foo test test test test 3<<EOF
stderr
-v0*=Hint: 'test' was listed multiple times, ignoring all but first!
stdout
-v3*=Not looking into 'foo|x|ooooooooooooooooooooooooooooooooooooooooo' as no matching target in 'foo/updates'!
-v3*=Not looking into 'foo|x|source' as no matching target in 'foo/updates'!
-v3*=Not looking into 'foo|a|ooooooooooooooooooooooooooooooooooooooooo' as no matching target in 'foo/updates'!
-v1*=Adding 'test' '0' to 'foo/updates|a|source'.
-d1*=db: 'test' added to packages.db(foo/updates|a|source).
-v*=Exporting indices...
-v6*= looking for changes in 'foo/updates|a|x'...
-v6*= looking for changes in 'u|foo/updates|a|x'...
-v6*= looking for changes in 'foo/updates|a|source'...
-v6*=  replacing './dists/foo/updates/a/source/Sources' (gzipped)
-v6*= looking for changes in 'foo/updates|bb|x'...
-v6*= looking for changes in 'foo/updates|bb|source'...
-v6*= looking for changes in 'foo/updates|ccc|x'...
-v6*= looking for changes in 'foo/updates|ccc|source'...
-v6*= looking for changes in 'foo/updates|dddd|x'...
-v6*= looking for changes in 'u|foo/updates|dddd|x'...
-v6*= looking for changes in 'foo/updates|dddd|source'...
EOF
rm -r -f db conf dists pool
testsuccess
