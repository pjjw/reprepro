#!/bin/bash

set -e
if [ "x$TESTINCSETUP" != "xissetup" ] ; then
	source $(dirname $0)/test.inc
fi

# different tests to check the error messages when accessing
# architectures components or packagetypes...

mkdir conf
cat > conf/options <<EOF
export never
EOF

cat > conf/distributions <<EOF
Codename: codename
Architectures: te/st all source
Components: component
EOF

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 2, column 16: Malformed Architectures element 'te/st': '/' is not allowed
-v0*=There have been errors!
return 255
EOF

sed -i -e 's#te/st#test#' conf/distributions

testrun - -b . update 3<<EOF
*=Error: Distribution codename contains an architecture called 'all'.
-v0*=There have been errors!
return 255
EOF

sed -i -e 's#\<all\>#a|l#' conf/distributions

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 2, column 21: Malformed Architectures element 'a|l': '|' is not allowed
-v0*=There have been errors!
return 255
EOF

sed -i -e 's#\<a|l\>##' -e 's#component#compo|nent#' conf/distributions

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 3, column 13: Malformed Components element 'compo|nent': '|' is not allowed
-v0*=There have been errors!
return 255
EOF

sed -i -e 's#compo|nent#.#' conf/distributions

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 3, column 13: Malformed Components element '.': '.' is not allowed as directory part
-v0*=There have been errors!
return 255
EOF

sed -i -e 's# .$# ./test#' conf/distributions

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 3, column 13: Malformed Components element './test': '.' is not allowed as directory part
-v0*=There have been errors!
return 255
EOF

sed -i -e 's# ./test$# bla/./test#' conf/distributions

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 3, column 13: Malformed Components element 'bla/./test': '.' is not allowed as directory part
-v0*=There have been errors!
return 255
EOF

sed -i -e 's# bla/./test$# bla/../test#' conf/distributions

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 3, column 13: Malformed Components element 'bla/../test': '..' is not allowed as directory part
-v0*=There have been errors!
return 255
EOF

sed -i -e 's#/test$##' conf/distributions

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 3, column 13: Malformed Components element 'bla/..': '..' is not allowed as directory part
-v0*=There have been errors!
return 255
EOF

sed -i -e 's#bla/##' conf/distributions

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 3, column 13: Malformed Components element '..': '..' is not allowed as directory part
-v0*=There have been errors!
return 255
EOF

sed -i -e 's#\.\.#component#' -e 's#Components#UdebComponents#' conf/distributions

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 3, column 16:
*= A 'UDebComponents'-field is only allowed after a 'Components'-field.
-v0*=There have been errors!
return 255
EOF

ed -s conf/distributions <<EOF
/Codename/a
Components: test
.
w
q
EOF

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 4, column 17: 'component' not allowed in UDebComponents as it was not in Components.
-v0*=There have been errors!
return 255
EOF

sed -i -e 's#test$#test component#' conf/distributions
cat >> conf/distributions <<EOF
ContentsArchitectures: bla
EOF

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 5, column 24: 'bla' not allowed in ContentsArchitectures as it was not in Architectures.
-v0*=There have been errors!
return 255
EOF

sed -i -e 's#ContentsArchitectures#ContentsComponents#' conf/distributions

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 5, column 21: 'bla' not allowed in ContentsComponents as it was not in Components.
-v0*=There have been errors!
return 255
EOF

sed -i -e 's#ContentsComponents: bla#ContentsUComponents: test#' conf/distributions

testrun - -b . update 3<<EOF
*=Error parsing ./conf/distributions, line 5, column 22: 'test' not allowed in ContentsUComponents as it was not in UDebComponents.
-v0*=There have been errors!
return 255
EOF

sed -i -e 's#ContentsUComponents: test#ContentsUComponents: component#' conf/distributions

testrun - -b . -A test update 3<<EOF
*=Action 'update' cannot be restricted to an architecture!
*=neither --archiecture nor -A make sense here.
*=To ignore use --ignore=unusedoption.
-v0*=There have been errors!
return 255
EOF
testrun - -b . -C test update 3<<EOF
*=Action 'update' cannot be restricted to a component!
*=neither --component nor -C make sense here.
*=To ignore use --ignore=unusedoption.
-v0*=There have been errors!
return 255
EOF
testrun - -b . -T dsc update 3<<EOF
*=Action 'update' cannot be restricted to a packagetype!
*=neither --packagetype nor -T make sense here.
*=To ignore use --ignore=unusedoption.
-v0*=There have been errors!
return 255
EOF
mkdir db
testrun - -b . -A test remove codename nothing 3<<EOF
-v0*=Not removed as not found: nothing
EOF
testrun - -b . -A bla remove codename nothing 3<<EOF
*=Error: Architecture 'bla' as given to --architecture is not know.
*=(it does not appear as architecture in ./conf/distributions (did you mistype?))
-v0*=There have been errors!
returns 255
EOF

rm -r conf db
testsuccess
