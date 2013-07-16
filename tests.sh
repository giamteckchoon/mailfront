#!/bin/sh
src=`pwd`
tmp=$src/tests-tmp
rm -rf $tmp
mkdir -p $tmp
PATH="$src:/bin:/usr/bin:/usr/local/bin"
tests_failed=0
tests_count=0
_UID=`id -u`
_GID=`id -g`

usage() {
  echo "usage: sh $0 [-v]"
}

vecho() { :; }
while getopts v flag
do
  case $flag in
    v)      vecho() { echo "$*"; } ;;
	*)      usage; exit 1 ;;
  esac
done
sfecho() {
  $src/mailfront smtp echo "$@" 2>/dev/null \
  | grep -v '^220 local.host mailfront ESMTP'
}
pfauth() {
  $src/pop3front-auth "$@" echo Yes. 2>/dev/null \
  | tail -n +2
}
ifauth() {
  $src/imapfront-auth sh -c 'echo Yes: $IMAPLOGINTAG' 2>/dev/null \
  | grep -v '^\* OK imapfront ready.'
}
pfmaildir() {
  $src/pop3front-maildir "$@" 2>/dev/null \
  | tail -n +2
}
maildir=$tmp/Maildir
maildir() {
  rm -rf $maildir
  mkdir -p $maildir/cur
  mkdir -p $maildir/new
  mkdir -p $maildir/tmp
}
tstmsg() {
  fn=$1
  {
    echo "Header: foo"
    echo
    echo "body"
  } >$maildir/$fn
}

PROTO=TEST
TESTLOCALIP=1.2.3.4
TESTREMOTEIP=5.6.7.8
TESTLOCALHOST=local.host
TESTREMOTEHOST=remote.host
CVM_PWFILE_PATH=$tmp/pwfile
MODULE_PATH=$src
PLUGINS=accept

export PROTO TESTLOCALIP TESTREMOTEIP TESTLOCALHOST TESTREMOTEHOST
export MAILRULES DATABYTES MAXHOPS PATTERNS MAXNOTIMPL
export PLUGINS MODULE_PATH

run_compare_test() {
  local name=$1
  shift
  sed -e "s:@SOURCE@:$src:g"   	-e "s:@TMPDIR@:$tmp:g"   	-e "s:@UID@:$_UID:" 	-e "s:@GID@:$_GID:" 	>$tmp/expected
  ( runtest "$@" 2>&1 ) 2>&1 >$tmp/actual-raw
  cat -v $tmp/actual-raw >$tmp/actual
  if ! cmp $tmp/expected $tmp/actual >/dev/null 2>&1
  then
    echo "Test $name $* failed:"
	( cd $tmp; diff -U 9999 expected actual | tail -n +3; echo; )
	tests_failed=$(($tests_failed+1))
  fi
  rm -f $tmp/expected $tmp/actual
  tests_count=$(($tests_count+1))
}

##### Test tests/rules-negate #####

runtest() {
PLUGINS=mailrules:accept

cat >$tmp/rules <<EOF
k!a@example.com:*:A
k!!a@example.com:*:B
EOF

MAILRULES=$tmp/rules

sfecho <<EOF
MAIL FROM:<a@example.com>
MAIL FROM:<b@example.net>
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-negate "
run_compare_test tests/rules-negate  <<END_OF_TEST_RESULTS
250 B^M
250 A^M
END_OF_TEST_RESULTS


##### Test tests/patterns-after #####

runtest() {
PLUGINS=patterns:accept

cat >$tmp/patterns <<EOF
\after
EOF

PATTERNS=$tmp/patterns
export PATTERNS

sfecho <<EOF
MAIL FROM:<>
RCPT TO:<nobody@example.com>
DATA
before

after
.
EOF

echo

cat >$tmp/patterns <<EOF
\before
EOF

sfecho <<EOF
MAIL FROM:<>
RCPT TO:<nobody@example.com>
DATA
before

after
.
EOF

rm -f $tmp/patterns
}
vecho "Running test tests/patterns-after "
run_compare_test tests/patterns-after  <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
554 This message contains prohibited content^M

250 Sender=''.^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 14 bytes.^M
END_OF_TEST_RESULTS


##### Test tests/smtpfront-bad-bounce #####

runtest() {
# Note: this test no longer tests anything significant.

sfecho <<EOF
MAIL FROM:<notbounce@example.com>
RCPT TO:<addr1@example.com>
RCPT TO:<addr2@example.com>
DATA
.
EOF

sfecho <<EOF
MAIL FROM:<>
RCPT TO:<addr1@example.com>
DATA
.
EOF

sfecho <<EOF
MAIL FROM:<>
RCPT TO:<addr1@example.com>
RCPT TO:<addr2@example.com>
DATA
.
EOF
}
vecho "Running test tests/smtpfront-bad-bounce "
run_compare_test tests/smtpfront-bad-bounce  <<END_OF_TEST_RESULTS
250 Sender='notbounce@example.com'.^M
250 Recipient='addr1@example.com'.^M
250 Recipient='addr2@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 0 bytes.^M
250 Sender=''.^M
250 Recipient='addr1@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 0 bytes.^M
250 Sender=''.^M
250 Recipient='addr1@example.com'.^M
250 Recipient='addr2@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 0 bytes.^M
END_OF_TEST_RESULTS


##### Test tests/plugin-cvm-auth-caps #####

runtest() {
PLUGINS=cvm-authenticate:relayclient:accept-sender

sfecho <<EOF
EHLO
EOF

export CVM_SASL_LOGIN=test
sfecho <<EOF
EHLO
EOF

export CVM_SASL_PLAIN=test
sfecho <<EOF
EHLO
EOF

unset CVM_SASL_LOGIN
sfecho <<EOF
EHLO
EOF

unset CVM_SASL_PLAIN
}
vecho "Running test tests/plugin-cvm-auth-caps "
run_compare_test tests/plugin-cvm-auth-caps  <<END_OF_TEST_RESULTS
250-local.host^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
250-local.host^M
250-AUTH LOGIN^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
250-local.host^M
250-AUTH LOGIN PLAIN^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
250-local.host^M
250-AUTH LOGIN PLAIN^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
END_OF_TEST_RESULTS


##### Test tests/pop3front-maildir-state #####

runtest() {
local quit="$1"
local command="$2"
maildir
tstmsg new/1
tstmsg new/this.is.a.very.long.filename.that.should.get.truncated.after.the.X...XBUGBUGBUGBUG
(
  echo $command
  if $quit; then echo QUIT; fi
) | pfmaildir $maildir
( cd $maildir && find new cur -type f | sort )
}
vecho "Running test tests/pop3front-maildir-state 'false' 'UIDL'"
run_compare_test tests/pop3front-maildir-state 'false' 'UIDL' <<END_OF_TEST_RESULTS
+OK ^M
1 1^M
2 this.is.a.very.long.filename.that.should.get.truncated.after.the.X...X^M
.^M
new/1
new/this.is.a.very.long.filename.that.should.get.truncated.after.the.X...XBUGBUGBUGBUG
END_OF_TEST_RESULTS

vecho "Running test tests/pop3front-maildir-state 'false' 'TOP 1 0'"
run_compare_test tests/pop3front-maildir-state 'false' 'TOP 1 0' <<END_OF_TEST_RESULTS
+OK ^M
Header: foo^M
^M
^M
.^M
new/1
new/this.is.a.very.long.filename.that.should.get.truncated.after.the.X...XBUGBUGBUGBUG
END_OF_TEST_RESULTS

vecho "Running test tests/pop3front-maildir-state 'false' 'RETR 1'"
run_compare_test tests/pop3front-maildir-state 'false' 'RETR 1' <<END_OF_TEST_RESULTS
+OK ^M
Header: foo^M
^M
body^M
^M
.^M
new/1
new/this.is.a.very.long.filename.that.should.get.truncated.after.the.X...XBUGBUGBUGBUG
END_OF_TEST_RESULTS

vecho "Running test tests/pop3front-maildir-state 'true' 'UIDL'"
run_compare_test tests/pop3front-maildir-state 'true' 'UIDL' <<END_OF_TEST_RESULTS
+OK ^M
1 1^M
2 this.is.a.very.long.filename.that.should.get.truncated.after.the.X...X^M
.^M
+OK ^M
cur/1
cur/this.is.a.very.long.filename.that.should.get.truncated.after.the.X...XBUGBUGBUGBUG
END_OF_TEST_RESULTS

vecho "Running test tests/pop3front-maildir-state 'true' 'TOP 1 0'"
run_compare_test tests/pop3front-maildir-state 'true' 'TOP 1 0' <<END_OF_TEST_RESULTS
+OK ^M
Header: foo^M
^M
^M
.^M
+OK ^M
cur/1
cur/this.is.a.very.long.filename.that.should.get.truncated.after.the.X...XBUGBUGBUGBUG
END_OF_TEST_RESULTS

vecho "Running test tests/pop3front-maildir-state 'true' 'RETR 1'"
run_compare_test tests/pop3front-maildir-state 'true' 'RETR 1' <<END_OF_TEST_RESULTS
+OK ^M
Header: foo^M
^M
body^M
^M
.^M
+OK ^M
cur/1:2,S
cur/this.is.a.very.long.filename.that.should.get.truncated.after.the.X...XBUGBUGBUGBUG
END_OF_TEST_RESULTS


##### Test tests/plugin-reject #####

runtest() {
local msg="$1"
PLUGINS=reject:accept

env SMTPREJECT="$msg" $src/mailfront smtp echo 2>/dev/null <<EOF
HELO nobody
EHLO somebody
MAIL FROM:<somewhere>
RCPT TO:<elsewhere>
EOF
}
vecho "Running test tests/plugin-reject 'rej'"
run_compare_test tests/plugin-reject 'rej' <<END_OF_TEST_RESULTS
220 local.host mailfront ESMTP^M
250 local.host^M
250-local.host^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
451 rej^M
503 5.5.1 You must send MAIL FROM: first^M
END_OF_TEST_RESULTS

vecho "Running test tests/plugin-reject '-rej'"
run_compare_test tests/plugin-reject '-rej' <<END_OF_TEST_RESULTS
220 local.host mailfront ESMTP^M
250 local.host^M
250-local.host^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
553 rej^M
503 5.5.1 You must send MAIL FROM: first^M
END_OF_TEST_RESULTS


##### Test tests/plugin-counters-looping-received #####

runtest() {
PLUGINS=counters:accept

MAXHOPS=1

sfecho <<EOF
MAIL FROM:<somebody@example.com>
RCPT TO:<nobody@example.org>
DATA
Received: foo
.
EOF

echo

sfecho <<EOF
MAIL FROM:<somebody@example.com>
RCPT TO:<nobody@example.org>
DATA
Received: foo
Received: foo
.
EOF
}
vecho "Running test tests/plugin-counters-looping-received "
run_compare_test tests/plugin-counters-looping-received  <<END_OF_TEST_RESULTS
250 Sender='somebody@example.com'.^M
250 Recipient='nobody@example.org'.^M
354 End your message with a period on a line by itself.^M
250 Received 14 bytes.^M

250 Sender='somebody@example.com'.^M
250 Recipient='nobody@example.org'.^M
354 End your message with a period on a line by itself.^M
554 5.6.0 This message is looping, too many hops.^M
END_OF_TEST_RESULTS


##### Test tests/pop3front-maildir-size #####

runtest() {
maildir
tstmsg new/1000000000.12345.here
tstmsg new/1000000001.12345.here,S=1234
tstmsg new/1000000002.12345.here,W=1234
tstmsg new/1000000003.12345.here,S=1234,W=2345

echo UIDL | pfmaildir $maildir
echo LIST | pfmaildir $maildir
(
  echo RETR 1
  echo RETR 2
  echo RETR 3
  echo RETR 4
  echo QUIT
) | pfmaildir $maildir >/dev/null

ls $maildir/cur
ls $maildir/new
echo UIDL | pfmaildir $maildir
echo LIST | pfmaildir $maildir
}
vecho "Running test tests/pop3front-maildir-size "
run_compare_test tests/pop3front-maildir-size  <<END_OF_TEST_RESULTS
+OK ^M
1 1000000000.12345.here^M
2 1000000001.12345.here^M
3 1000000002.12345.here^M
4 1000000003.12345.here^M
.^M
+OK ^M
1 18^M
2 1234^M
3 1234^M
4 2345^M
.^M
1000000000.12345.here:2,S
1000000001.12345.here,S=1234:2,S
1000000002.12345.here,W=1234:2,S
1000000003.12345.here,S=1234,W=2345:2,S
+OK ^M
1 1000000000.12345.here^M
2 1000000001.12345.here^M
3 1000000002.12345.here^M
4 1000000003.12345.here^M
.^M
+OK ^M
1 18^M
2 1234^M
3 1234^M
4 2345^M
.^M
END_OF_TEST_RESULTS


##### Test tests/smtpfront-quotes #####

runtest() {
sfecho <<EOF
MAIL FROM:<"me, myself, and I"@example.net>
RCPT TO:<"you, yourself, and you"@example.com>
RCPT TO:<him\,himself@example.com>
RCPT TO:<@somewhere,@elsewhere:two@example.com>
EOF
}
vecho "Running test tests/smtpfront-quotes "
run_compare_test tests/smtpfront-quotes  <<END_OF_TEST_RESULTS
250 Sender='me, myself, and I@example.net'.^M
250 Recipient='you, yourself, and you@example.com'.^M
250 Recipient='him,himself@example.com'.^M
250 Recipient='two@example.com'.^M
END_OF_TEST_RESULTS


##### Test tests/patterns-header #####

runtest() {
PLUGINS=patterns:accept

cat >$tmp/patterns <<EOF
:header2:*field*
EOF

PATTERNS=$tmp/patterns

sfecho <<EOF
MAIL FROM:<>
RCPT TO:<nobody@example.com>
DATA
header1: data
header2: another field

not

also
.
EOF

echo

cat >$tmp/patterns <<EOF
:not
:also
EOF

sfecho <<EOF
MAIL FROM:<>
RCPT TO:<nobody@example.com>
DATA
header

not

also
.
EOF

rm -f $tmp/patterns
}
vecho "Running test tests/patterns-header "
run_compare_test tests/patterns-header  <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
554 This message contains prohibited content^M

250 Sender=''.^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 18 bytes.^M
END_OF_TEST_RESULTS


##### Test tests/imapfront-auth-login #####

runtest() {
export CVM_SASL_PLAIN=$src/testcvm

ifauth false <<EOF
1 AUTHENTICATE LOGIN
dGVzdHVzZXI=
dGVzdHBhc3x=
2 AUTHENTICATE LOGIN
dGVzdHVzZXI=
dGVzdHBhc3M=
EOF

ifauth false <<EOF
3 AUTHENTICATE LOGIN dGVzdHVzZXI=
dGVzdHBhc3M=
EOF

ifauth false <<EOF
4 AUTHENTICATE LOGIN
dGVzdHVzZXI=
*
EOF

unset CVM_SASL_PLAIN
}
vecho "Running test tests/imapfront-auth-login "
run_compare_test tests/imapfront-auth-login  <<END_OF_TEST_RESULTS
+ VXNlcm5hbWU6^M
+ UGFzc3dvcmQ6^M
1 NO AUTHENTICATE failed: Authentication failed.^M
+ VXNlcm5hbWU6^M
+ UGFzc3dvcmQ6^M
Yes: 2
+ UGFzc3dvcmQ6^M
Yes: 3
+ VXNlcm5hbWU6^M
+ UGFzc3dvcmQ6^M
4 NO AUTHENTICATE failed: Authentication failed.^M
END_OF_TEST_RESULTS


##### Test tests/rules-empty #####

runtest() {
PLUGINS=mailrules:accept

cat >$tmp/rules <<EOF
k:*:K1
k*:*:K2
EOF

MAILRULES=$tmp/rules

sfecho <<EOF
MAIL FROM:<>
MAIL FROM:<foo@example.com>
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-empty "
run_compare_test tests/rules-empty  <<END_OF_TEST_RESULTS
250 K1^M
250 K2^M
END_OF_TEST_RESULTS


##### Test tests/rules-sender #####

runtest() {
PLUGINS=mailrules:accept

cat >$tmp/rules <<EOF
kone@one.example.com:*:KK
dtwo@two.example.com:*:DD
zthree@three.example.com:*:ZZ
zfour@four.example.com:one@one.example.com:ZZ
pfive@five.example.com:*:PP
EOF

MAILRULES=$tmp/rules

sfecho <<EOF
MAIL FROM:<>
MAIL FROM:<one@one.example.com>
MAIL FROM:<two@two.example.com>
MAIL FROM:<three@three.example.com>
MAIL FROM:<four@four.example.com>
MAIL FROM:<five@five.example.com>
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-sender "
run_compare_test tests/rules-sender  <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 KK^M
553 DD^M
451 ZZ^M
250 Sender='four@four.example.com'.^M
250 Sender='five@five.example.com'.^M
END_OF_TEST_RESULTS


##### Test tests/plugin-lua #####

runtest() {
export LUA_SCRIPT=script.lua
doit() {
    cat > script.lua
    echo
    sfecho lua add-received counters <<EOF
HELO helohost
MAIL FROM:<sender> SIZE=13
RCPT TO:<recip1>
RCPT TO:<recip2>
DATA
Header: one
.
EOF
}

doit <<EOF
return 555,"init failed"
EOF

doit <<EOF
function reset()
  return 253,'reset'
end

function sender(a)
  return 251,'Lua sender='..a
end

function recipient(a)
  return 252,'Lua recip='..a
end

function data_start(fd)
  return 354
end
EOF

doit <<EOF
function data_start(fd)
  return 421,'start fd='..fd
end
EOF

doit <<EOF
setstr('helo_domain', '01234567890123456789012345678901234567890123456789')
EOF

doit <<EOF
setnum('maxdatabytes', 1)
EOF

doit <<EOF
function recipient(s)
  setnum('maxdatabytes', 1)
end
EOF

doit <<EOF
count=0
function recipient(s)
  count = count + 1
  return 252,'recipient #'..count
end
function data_start(fd)
  bytes = 0
end
function data_block(s)
  bytes = bytes + ( # s )
end
function message_end(fd)
  return 450,bytes .. ' bytes, ' .. count .. ' recipients, ' .. (bytes*count) .. ' total'
end
EOF
rm -f $LUA_SCRIPT
unset LUA_SCRIPT
}
vecho "Running test tests/plugin-lua "
run_compare_test tests/plugin-lua  <<END_OF_TEST_RESULTS

555 init failed^M

250 local.host^M
251 Lua sender=sender^M
252 Lua recip=recip1^M
252 Lua recip=recip2^M
354 End your message with a period on a line by itself.^M
250 Received 137 bytes.^M

250 local.host^M
250 Sender='sender'. [SIZE=13]^M
250 Recipient='recip1'.^M
250 Recipient='recip2'.^M
421 start fd=-1^M
500 5.5.1 Not implemented.^M
500 5.5.1 Not implemented.^M

250 local.host^M
250 Sender='sender'. [SIZE=13]^M
250 Recipient='recip1'.^M
250 Recipient='recip2'.^M
354 End your message with a period on a line by itself.^M
250 Received 179 bytes.^M

250 local.host^M
552 5.2.3 The message would exceed the maximum message size.^M
503 5.5.1 You must send MAIL FROM: first^M
503 5.5.1 You must send MAIL FROM: first^M
503 5.5.1 You must send MAIL FROM: first^M
500 5.5.1 Not implemented.^M
500 5.5.1 Not implemented.^M

250 local.host^M
250 Sender='sender'. [SIZE=13]^M
250 Recipient='recip1'.^M
250 Recipient='recip2'.^M
354 End your message with a period on a line by itself.^M
552 5.2.3 Sorry, that message exceeds the maximum message length.^M

250 local.host^M
250 Sender='sender'. [SIZE=13]^M
252 recipient #1^M
252 recipient #2^M
354 End your message with a period on a line by itself.^M
450 12 bytes, 2 recipients, 24 total^M
END_OF_TEST_RESULTS


##### Test tests/plugin-check-fqdn #####

runtest() {
local defaultdomain="$1"
local defaulthost="$2"

PLUGINS=check-fqdn:accept
if [ -n "$defaultdomain" ]; then
  DEFAULTDOMAIN=$defaultdomain
  export DEFAULTDOMAIN
fi
if [ -n "$defaulthost" ]; then
  DEFAULTHOST=$defaulthost
  export DEFAULTHOST
fi

sfecho <<EOF
MAIL FROM:<>
MAIL FROM:<foo>
MAIL FROM:<foo@bar>
MAIL FROM:<foo@bar.baz>
RCPT TO:<>
RCPT TO:<foo>
RCPT TO:<foo@bar>
RCPT TO:<foo@bar.baz>
EOF

unset DEFAULTDOMAIN DEFAULTHOST
}
vecho "Running test tests/plugin-check-fqdn '' ''"
run_compare_test tests/plugin-check-fqdn '' '' <<END_OF_TEST_RESULTS
250 Sender=''.^M
554 5.1.2 Address is missing a domain name^M
554 5.1.2 Address does not contain a fully qualified domain name^M
250 Sender='foo@bar.baz'.^M
554 5.1.2 Recipient address may not be empty^M
554 5.1.2 Address is missing a domain name^M
554 5.1.2 Address does not contain a fully qualified domain name^M
250 Recipient='foo@bar.baz'.^M
END_OF_TEST_RESULTS

vecho "Running test tests/plugin-check-fqdn '' 'local.example.com'"
run_compare_test tests/plugin-check-fqdn '' 'local.example.com' <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Sender='foo@local.example.com'.^M
554 5.1.2 Address does not contain a fully qualified domain name^M
250 Sender='foo@bar.baz'.^M
554 5.1.2 Recipient address may not be empty^M
250 Recipient='foo@local.example.com'.^M
554 5.1.2 Address does not contain a fully qualified domain name^M
250 Recipient='foo@bar.baz'.^M
END_OF_TEST_RESULTS

vecho "Running test tests/plugin-check-fqdn 'example.com' ''"
run_compare_test tests/plugin-check-fqdn 'example.com' '' <<END_OF_TEST_RESULTS
250 Sender=''.^M
554 5.1.2 Address is missing a domain name^M
250 Sender='foo@bar.example.com'.^M
250 Sender='foo@bar.baz'.^M
554 5.1.2 Recipient address may not be empty^M
554 5.1.2 Address is missing a domain name^M
250 Recipient='foo@bar.example.com'.^M
250 Recipient='foo@bar.baz'.^M
END_OF_TEST_RESULTS

vecho "Running test tests/plugin-check-fqdn 'example.com' 'local.example.com'"
run_compare_test tests/plugin-check-fqdn 'example.com' 'local.example.com' <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Sender='foo@local.example.com'.^M
250 Sender='foo@bar.example.com'.^M
250 Sender='foo@bar.baz'.^M
554 5.1.2 Recipient address may not be empty^M
250 Recipient='foo@local.example.com'.^M
250 Recipient='foo@bar.example.com'.^M
250 Recipient='foo@bar.baz'.^M
END_OF_TEST_RESULTS


##### Test tests/plugins-remove #####

runtest() {
local remove="$1"

env \
PLUGINS="reject:-$remove:accept" \
REJECT="reject" \
$src/mailfront smtp echo 2>/dev/null <<EOF
MAIL FROM:<somewhere>
RCPT TO:<elsewhere>
EOF
}
vecho "Running test tests/plugins-remove 'reject'"
run_compare_test tests/plugins-remove 'reject' <<END_OF_TEST_RESULTS
220 local.host mailfront ESMTP^M
250 Sender='somewhere'.^M
250 Recipient='elsewhere'.^M
END_OF_TEST_RESULTS

vecho "Running test tests/plugins-remove 'other'"
run_compare_test tests/plugins-remove 'other' <<END_OF_TEST_RESULTS
220 local.host mailfront ESMTP^M
451 reject^M
503 5.5.1 You must send MAIL FROM: first^M
END_OF_TEST_RESULTS

vecho "Running test tests/plugins-remove '*'"
run_compare_test tests/plugins-remove '*' <<END_OF_TEST_RESULTS
220 local.host mailfront ESMTP^M
250 Sender='somewhere'.^M
250 Recipient='elsewhere'.^M
END_OF_TEST_RESULTS


##### Test tests/rules-cdb #####

runtest() {
PLUGINS=mailrules:accept

cat >$tmp/rules <<EOF
k[[$tmp/list.cdb]]:*:LIST
k[[@$tmp/atlist.cdb]]:*:ATLIST
d*:*:DD
EOF

cat <<EOF | cdbmake $tmp/list.cdb $tmp/list.tmp
+13,0:a@example.net->
+12,0:@example.com->

EOF

cat <<EOF | cdbmake $tmp/atlist.cdb $tmp/atlist.tmp
+11,0:example.org->

EOF

MAILRULES=$tmp/rules

sfecho <<EOF
MAIL FROM:<a@example.net>
MAIL FROM:<b@example.net>
MAIL FROM:<a@example.org>
MAIL FROM:<b@Example.ORG>
MAIL FROM:<c@example.com>
MAIL FROM:<c@Example.COM>
MAIL FROM:<d@example.biz>
EOF

rm -f $tmp/rules $tmp/list.cdb $tmp/atlist.cdb
}
vecho "Running test tests/rules-cdb "
run_compare_test tests/rules-cdb  <<END_OF_TEST_RESULTS
250 LIST^M
553 DD^M
250 ATLIST^M
250 ATLIST^M
250 LIST^M
250 LIST^M
553 DD^M
END_OF_TEST_RESULTS


##### Test tests/plugins-prepend #####

runtest() {
env \
PLUGINS=accept:+reject \
REJECT=reject \
$src/mailfront smtp echo 2>/dev/null <<EOF
MAIL FROM:<somewhere>
RCPT TO:<elsewhere>
EOF
}
vecho "Running test tests/plugins-prepend "
run_compare_test tests/plugins-prepend  <<END_OF_TEST_RESULTS
220 local.host mailfront ESMTP^M
451 reject^M
503 5.5.1 You must send MAIL FROM: first^M
END_OF_TEST_RESULTS


##### Test tests/rules-selector #####

runtest() {
PLUGINS=mailrules:accept

cat >$tmp/rules <<EOF
# This selector forces what would normally be a recipient rule to be
# applied only to the sender.
:sender
kone@example.com:two@example.net:A
# This selector forces what would normally be a sender rule to be
# applied only to recipients.
:recipient
ktwo@example.net:*:B
EOF

MAILRULES=$tmp/rules

sfecho <<EOF
MAIL FROM:<one@example.com>
RCPT TO:<three@example.org>
RCPT TO:<four@example.biz>
MAIL FROM:<two@example.net>
RCPT TO:<three@example.org>
RCPT TO:<four@example.biz>
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-selector "
run_compare_test tests/rules-selector  <<END_OF_TEST_RESULTS
250 A^M
250 Recipient='three@example.org'.^M
250 Recipient='four@example.biz'.^M
250 Sender='two@example.net'.^M
250 B^M
250 B^M
END_OF_TEST_RESULTS


##### Test tests/pop3front-capa #####

runtest() {
pfauth $src/testcvm <<EOF
CAPA
EOF

export CVM_SASL_PLAIN=$src/testcvm
pfauth $src/testcvm <<EOF
CAPA
EOF

unset CVM_SASL_PLAIN
pfmaildir $maildir <<EOF
CAPA
EOF

export CVM_SASL_PLAIN=$src/testcvm
pfauth $src/testcvm <<EOF
CAPA
EOF

unset CVM_SASL_PLAIN
}
vecho "Running test tests/pop3front-capa "
run_compare_test tests/pop3front-capa  <<END_OF_TEST_RESULTS
+OK ^M
PIPELINING^M
TOP^M
UIDL^M
USER^M
.^M
+OK ^M
SASL LOGIN PLAIN^M
PIPELINING^M
TOP^M
UIDL^M
USER^M
.^M
+OK ^M
PIPELINING^M
TOP^M
UIDL^M
USER^M
.^M
+OK ^M
SASL LOGIN PLAIN^M
PIPELINING^M
TOP^M
UIDL^M
USER^M
.^M
END_OF_TEST_RESULTS


##### Test tests/rules-databytes #####

runtest() {
PLUGINS=mailrules:counters:accept

cat >$tmp/rules <<EOF
ka@example.com:*::123
EOF

MAILRULES=$tmp/rules

sfecho <<EOF
EHLO hostname
MAIL FROM:<a@example.com>
MAIL FROM:<a@example.com> SIZE
MAIL FROM:<a@example.com> SIZE=
MAIL FROM:<a@example.com> SIZE=100
MAIL FROM:<a@example.com> SIZE=123
MAIL FROM:<a@example.com> SIZE=124
RCPT TO:<nobody@example.net>
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-databytes "
run_compare_test tests/rules-databytes  <<END_OF_TEST_RESULTS
250-local.host^M
250-SIZE 0^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
250 OK^M
250 OK^M
250 OK^M
250 OK^M
250 OK^M
552 5.2.3 The message would exceed the maximum message size.^M
503 5.5.1 You must send MAIL FROM: first^M
END_OF_TEST_RESULTS


##### Test tests/plugin-check-fqdn-domains #####

runtest() {
PLUGINS=check-fqdn:accept

SENDER_DOMAINS=example1.com:example2.com
export SENDER_DOMAINS

sfecho <<EOF
MAIL FROM:<>
MAIL FROM:<foo@example1.co>
MAIL FROM:<foo@example1.com>
MAIL FROM:<foo@example1.comm>
MAIL FROM:<foo@example2.co>
MAIL FROM:<foo@example2.com>
MAIL FROM:<foo@example2.comm>
EOF

unset SENDER_DOMAINS
}
vecho "Running test tests/plugin-check-fqdn-domains "
run_compare_test tests/plugin-check-fqdn-domains  <<END_OF_TEST_RESULTS
554 5.1.2 Empty sender address prohibited^M
554 5.1.2 Sender contains a disallowed domain^M
250 Sender='foo@example1.com'.^M
554 5.1.2 Sender contains a disallowed domain^M
554 5.1.2 Sender contains a disallowed domain^M
250 Sender='foo@example2.com'.^M
554 5.1.2 Sender contains a disallowed domain^M
END_OF_TEST_RESULTS


##### Test tests/rules-asterisk #####

runtest() {
PLUGINS=mailrules:accept

cat >$tmp/rules <<EOF
ka@example.com:*:K1
k*@example.com:*:K2
kc@*:*:K3
k*:*:K4
EOF

MAILRULES=$tmp/rules
export MAILRULES

sfecho <<EOF
MAIL FROM:<a@example.com>
MAIL FROM:<b@example.com>
MAIL FROM:<c@example.net>
MAIL FROM:<d@example.org>
MAIL FROM:<>
MAIL FROM:<1@2@example.com@example.com>
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-asterisk "
run_compare_test tests/rules-asterisk  <<END_OF_TEST_RESULTS
250 K1^M
250 K2^M
250 K3^M
250 K4^M
250 K4^M
250 K2^M
END_OF_TEST_RESULTS


##### Test tests/plugin-qmail-validate #####

runtest() {
PLUGINS=qmail-validate

QMAILHOME=$tmp/@notthere@
export QMAILHOME
sfecho <<EOF
EOF

QMAILHOME=$tmp/qmail
export QMAILHOME
mkdir -p $QMAILHOME/control
echo badfrom@example.com >$QMAILHOME/control/badmailfrom
echo @badfrom.com >>$QMAILHOME/control/badmailfrom
echo rcpthost.com >$QMAILHOME/control/rcpthosts
echo .subrcpthost.com >>$QMAILHOME/control/rcpthosts
echo badrcpt@example.com >$QMAILHOME/control/badrcptto
echo @badrcpt.com >>$QMAILHOME/control/badrcptto
cdbmake $QMAILHOME/control/morercpthosts.cdb $QMAILHOME/tmp <<EOF
+16,0:morercpthost.com->
+20,0:.submorercpthost.com->

EOF

sfecho <<EOF
MAIL FROM:<badfrom@example.com>
MAIL FROM:<somebody@badfrom.com>
MAIL FROM:<goodfrom@example.com>
RCPT TO:<badrcpt@example.com>
RCPT TO:<somebody@badrcpt.com>
RCPT TO:<nobody@nowhere>
RCPT TO:<somebody@rcpthost.com>
RCPT TO:<somebody@else.subrcpthost.com>
RCPT TO:<somebody@morercpthost.com>
RCPT TO:<somebody@else.submorercpthost.com>
EOF

rm -r $QMAILHOME
unset QMAILHOME
}
vecho "Running test tests/plugin-qmail-validate "
run_compare_test tests/plugin-qmail-validate  <<END_OF_TEST_RESULTS
451 4.3.0 Could not change to the qmail directory.^M
553 5.1.0 Sorry, your envelope sender is in my badmailfrom list.^M
553 5.1.0 Sorry, your envelope sender is in my badmailfrom list.^M
250 Sender='goodfrom@example.com'.^M
553 5.1.1 Sorry, that address is in my badrcptto list.^M
553 5.1.1 Sorry, that address is in my badrcptto list.^M
550 5.1.0 Mail system is not configured to accept that recipient^M
250 Recipient='somebody@rcpthost.com'.^M
250 Recipient='somebody@else.subrcpthost.com'.^M
250 Recipient='somebody@morercpthost.com'.^M
250 Recipient='somebody@else.submorercpthost.com'.^M
END_OF_TEST_RESULTS


##### Test tests/pop3front-auth-plain #####

runtest() {
pfauth false <<EOF
AUTH PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3M=
EOF

export CVM_SASL_PLAIN=$src/testcvm

pfauth false <<EOF
AUTH PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3x=
AUTH PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3M=
EOF

pfauth false <<EOF
AUTH PLAIN
dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3M=
EOF

pfauth false <<EOF
AUTH PLAIN
*
EOF

unset CVM_SASL_PLAIN
}
vecho "Running test tests/pop3front-auth-plain "
run_compare_test tests/pop3front-auth-plain  <<END_OF_TEST_RESULTS
-ERR Unrecognized authentication mechanism.^M
-ERR Authentication failed.^M
Yes.
+ ^M
Yes.
+ ^M
-ERR Authentication failed.^M
END_OF_TEST_RESULTS


##### Test tests/pop3front-maildir-flags #####

runtest() {
pftest() {
  (
    for line in "$@"; do
      echo $line
    done
  ) | pfmaildir $maildir
  ( cd $maildir && ls -1 */* )
}

# Does it properly parse existing v2 flags
maildir
tstmsg new/1000000000.12345.here:2,FX
pftest 'RETR 1' QUIT

# Does it properly ignore non-v2 flags
maildir
tstmsg new/1000000000.12345.here:1fsd
pftest 'RETR 1' QUIT
}
vecho "Running test tests/pop3front-maildir-flags "
run_compare_test tests/pop3front-maildir-flags  <<END_OF_TEST_RESULTS
+OK ^M
Header: foo^M
^M
body^M
^M
.^M
+OK ^M
cur/1000000000.12345.here:2,FXS
+OK ^M
Header: foo^M
^M
body^M
^M
.^M
+OK ^M
cur/1000000000.12345.here:1fsd
END_OF_TEST_RESULTS


##### Test tests/imapfront-auth-toomany #####

runtest() {
local limit="$1"
export MAXAUTHFAIL=$limit
export CVM_SASL_PLAIN=$src/testcvm

ifauth <<EOF
1 AUTHENTICATE PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3x=
2 AUTHENTICATE PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3x=
3 AUTHENTICATE PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3x=
4 AUTHENTICATE PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3x=
EOF

echo

ifauth <<EOF
1 LOGIN A B
2 LOGIN A B
3 LOGIN A B
4 LOGIN A B
EOF
unset CVM_SASL_PLAIN
unset MAXAUTHFAIL
}
vecho "Running test tests/imapfront-auth-toomany '0'"
run_compare_test tests/imapfront-auth-toomany '0' <<END_OF_TEST_RESULTS
1 NO AUTHENTICATE failed: Authentication failed.^M
2 NO AUTHENTICATE failed: Authentication failed.^M
3 NO AUTHENTICATE failed: Authentication failed.^M
4 NO AUTHENTICATE failed: Authentication failed.^M

1 NO LOGIN failed^M
2 NO LOGIN failed^M
3 NO LOGIN failed^M
4 NO LOGIN failed^M
END_OF_TEST_RESULTS

vecho "Running test tests/imapfront-auth-toomany '2'"
run_compare_test tests/imapfront-auth-toomany '2' <<END_OF_TEST_RESULTS
1 NO AUTHENTICATE failed: Authentication failed.^M
2 NO AUTHENTICATE failed: Authentication failed.^M

1 NO LOGIN failed^M
2 NO LOGIN failed^M
END_OF_TEST_RESULTS


##### Test tests/imapfront-capability #####

runtest() {
CVM_SASL_PLAIN=$src/testcvm
export CVM_SASL_PLAIN

ifauth <<EOF
0 CAPABILITY
1 CAPABILITY SASL
EOF

export CAPABILITY="CAPS3"
ifauth <<EOF
2 CAPABILITY
EOF

export CAPABILITY="IMAP4rev1 CAPS4"
ifauth <<EOF
3 CAPABILITY
EOF

unset CAPABILITY
export IMAP_ACL=0
ifauth <<EOF
4 CAPABILITY
EOF

export IMAP_ACL=1
ifauth <<EOF
5 CAPABILITY
EOF

unset IMAP_ACL
export OUTBOX=
ifauth <<EOF
6 CAPABILITY
EOF

export OUTBOX=.SOMEBOX
ifauth <<EOF
7 CAPABILITY
EOF

unset OUTBOX
export IMAP_MOVE_EXPUNGE_TO_TRASH=0
ifauth <<EOF
8 CAPABILITY
EOF

export IMAP_MOVE_EXPUNGE_TO_TRASH=1
ifauth <<EOF
9 CAPABILITY
EOF

unset IMAP_MOVE_EXPUNGE_TO_TRASH
unset CVM_SASL_PLAIN
}
vecho "Running test tests/imapfront-capability "
run_compare_test tests/imapfront-capability  <<END_OF_TEST_RESULTS
* CAPABILITY IMAP4rev1^M
0 OK CAPABILITY completed^M
1 BAD Syntax error: command requires no arguments^M
* CAPABILITY IMAP4rev1 CAPS3^M
2 OK CAPABILITY completed^M
* CAPABILITY IMAP4rev1 CAPS4^M
3 OK CAPABILITY completed^M
* CAPABILITY IMAP4rev1^M
4 OK CAPABILITY completed^M
* CAPABILITY IMAP4rev1 ACL ACL2=UNION^M
5 OK CAPABILITY completed^M
* CAPABILITY IMAP4rev1^M
6 OK CAPABILITY completed^M
* CAPABILITY IMAP4rev1 XCOURIEROUTBOX=INBOX.SOMEBOX^M
7 OK CAPABILITY completed^M
* CAPABILITY IMAP4rev1^M
8 OK CAPABILITY completed^M
* CAPABILITY IMAP4rev1 XMAGICTRASH^M
9 OK CAPABILITY completed^M
END_OF_TEST_RESULTS


##### Test tests/plugin-counters-databytes #####

runtest() {
PLUGINS=counters:accept

unset DATABYTES
sfecho <<EOF
EHLO hostname
MAIL FROM:<a@example.com>
MAIL FROM:<a@example.com> SIZE
MAIL FROM:<a@example.com> SIZE=
MAIL FROM:<a@example.com> SIZE=100
EOF

DATABYTES=123
export DATABYTES

sfecho <<EOF
EHLO hostname
MAIL FROM:<a@example.com>
MAIL FROM:<a@example.com> SIZE
MAIL FROM:<a@example.com> SIZE=
MAIL FROM:<a@example.com> SIZE=100
MAIL FROM:<a@example.com> SIZE=123
MAIL FROM:<a@example.com> SIZE=124
RCPT TO:<nobody@nowhere>
EOF
}
vecho "Running test tests/plugin-counters-databytes "
run_compare_test tests/plugin-counters-databytes  <<END_OF_TEST_RESULTS
250-local.host^M
250-SIZE 0^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
250 Sender='a@example.com'.^M
250 Sender='a@example.com'. [SIZE]^M
250 Sender='a@example.com'. [SIZE=]^M
250 Sender='a@example.com'. [SIZE=100]^M
250-local.host^M
250-SIZE 123^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
250 Sender='a@example.com'.^M
250 Sender='a@example.com'. [SIZE]^M
250 Sender='a@example.com'. [SIZE=]^M
250 Sender='a@example.com'. [SIZE=100]^M
250 Sender='a@example.com'. [SIZE=123]^M
552 5.2.3 The message would exceed the maximum message size.^M
503 5.5.1 You must send MAIL FROM: first^M
END_OF_TEST_RESULTS


##### Test tests/imapfront-auth-plain #####

runtest() {
export CVM_SASL_PLAIN=$src/testcvm

ifauth <<EOF
1 AUTHENTICATE PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3x=
2 AUTHENTICATE PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3M=
EOF

ifauth <<EOF
3 AUTHENTICATE PLAIN
dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3M=
EOF

ifauth <<EOF
4 AUTHENTICATE PLAIN
*
EOF

unset CVM_SASL_PLAIN
}
vecho "Running test tests/imapfront-auth-plain "
run_compare_test tests/imapfront-auth-plain  <<END_OF_TEST_RESULTS
1 NO AUTHENTICATE failed: Authentication failed.^M
Yes: 2
+ ^M
Yes: 3
+ ^M
4 NO AUTHENTICATE failed: Authentication failed.^M
END_OF_TEST_RESULTS


##### Test tests/smtpfront-content #####

runtest() {
RELAYCLIENT= sfecho <<EOF
MAIL FROM:<user@example.net>
RCPT TO:<user@example.com>
DATA
Subject: test

foo
..
bar
.
MAIL FROM:<user@example.net>
RCPT TO:<user@example.com>
DATA
Subject: test

foo
..
bar

.
EOF
}
vecho "Running test tests/smtpfront-content "
run_compare_test tests/smtpfront-content  <<END_OF_TEST_RESULTS
250 Sender='user@example.net'.^M
250 Recipient='user@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 25 bytes.^M
250 Sender='user@example.net'.^M
250 Recipient='user@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 26 bytes.^M
END_OF_TEST_RESULTS


##### Test tests/plugin-cvm-validate #####

runtest() {
PLUGINS=cvm-validate:accept
CVM_LOOKUP=$src/testcvm
export CVM_LOOKUP

sfecho <<EOF
MAIL FROM:<somewhere>
RCPT TO:<testuser@here>
RCPT TO:<testxser@here>
EOF

CVM_LOOKUP_SECRET=test
export CVM_LOOKUP_SECRET

echo
sfecho <<EOF
MAIL FROM:<somewhere>
RCPT TO:<testuser@here>
RCPT TO:<testxser@here>
EOF

unset CVM_LOOKUP CVM_LOOKUP_SECRET
}
vecho "Running test tests/plugin-cvm-validate "
run_compare_test tests/plugin-cvm-validate  <<END_OF_TEST_RESULTS
250 Sender='somewhere'.^M
250 Recipient='testuser@here'.^M
553 5.1.1 Sorry, that recipient does not exist.^M

250 Sender='somewhere'.^M
250 Recipient='testuser@here'.^M
553 5.1.1 Sorry, that recipient does not exist.^M
END_OF_TEST_RESULTS


##### Test tests/plugin-cvm-auth-login #####

runtest() {
PLUGINS=cvm-authenticate:relayclient:accept-sender

sfecho <<EOF
AUTH LOGIN
EOF

export CVM_SASL_LOGIN=$src/testcvm

sfecho <<EOF
MAIL FROM: <user@example.com>
RCPT TO: <user@example.com>
AUTH LOGIN
dGVzdHVzZXI=
dGVzdHBhc3x=
AUTH LOGIN
dGVzdHVzZXI=
dGVzdHBhc3M=
AUTH LOGIN
MAIL FROM: <user@example.com>
RCPT TO: <user@example.com>
EOF

sfecho << EOF
AUTH LOGIN dGVzdHVzZXI=
dGVzdHBhc3M=
EOF

sfecho <<EOF
AUTH LOGIN
dGVzdHVzZXI=
*
MAIL FROM: <user@example.com>
RCPT TO: <user@example.com>
EOF

unset CVM_SASL_PLAIN
}
vecho "Running test tests/plugin-cvm-auth-login "
run_compare_test tests/plugin-cvm-auth-login  <<END_OF_TEST_RESULTS
500 5.5.1 Not implemented.^M
250 Sender='user@example.com'.^M
550 5.1.0 Mail system is not configured to accept that recipient^M
334 VXNlcm5hbWU6^M
334 UGFzc3dvcmQ6^M
501 Authentication failed.^M
334 VXNlcm5hbWU6^M
334 UGFzc3dvcmQ6^M
235 2.7.0 Authentication succeeded.^M
503 5.5.1 You are already authenticated.^M
250 Sender='user@example.com'.^M
250 Recipient='user@example.com'.^M
334 UGFzc3dvcmQ6^M
235 2.7.0 Authentication succeeded.^M
334 VXNlcm5hbWU6^M
334 UGFzc3dvcmQ6^M
501 Authentication failed.^M
250 Sender='user@example.com'.^M
550 5.1.0 Mail system is not configured to accept that recipient^M
END_OF_TEST_RESULTS


##### Test tests/received #####

runtest() {
local remotehost="$1"
local remoteip="$2"
local localhost="$3"
local localip="$4"
local helo="$5"

PLUGINS=add-received:accept
TESTLOCALHOST="$localhost"
TESTLOCALIP="$localip"
TESTREMOTEHOST="$remotehost"
TESTREMOTEIP="$remoteip"

$src/mailfront smtp echo 2>&1 >/dev/null <<EOF | \
	sed -n -e 's/^.* Received: //p'
$helo
MAIL FROM:<>
RCPT TO:<test@example.com>
DATA
.
EOF
}
vecho "Running test tests/received '' '' '' '' ''"
run_compare_test tests/received '' '' '' '' '' <<END_OF_TEST_RESULTS
from unknown  by unknown
END_OF_TEST_RESULTS

vecho "Running test tests/received '' '' '' '' 'EHLO hh'"
run_compare_test tests/received '' '' '' '' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh  by unknown
END_OF_TEST_RESULTS

vecho "Running test tests/received '' '' '' 'li' ''"
run_compare_test tests/received '' '' '' 'li' '' <<END_OF_TEST_RESULTS
from unknown  by li ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received '' '' '' 'li' 'EHLO hh'"
run_compare_test tests/received '' '' '' 'li' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh  by li ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received '' '' 'lh' '' ''"
run_compare_test tests/received '' '' 'lh' '' '' <<END_OF_TEST_RESULTS
from unknown  by lh
END_OF_TEST_RESULTS

vecho "Running test tests/received '' '' 'lh' '' 'EHLO hh'"
run_compare_test tests/received '' '' 'lh' '' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh  by lh
END_OF_TEST_RESULTS

vecho "Running test tests/received '' '' 'lh' 'li' ''"
run_compare_test tests/received '' '' 'lh' 'li' '' <<END_OF_TEST_RESULTS
from unknown  by lh ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received '' '' 'lh' 'li' 'EHLO hh'"
run_compare_test tests/received '' '' 'lh' 'li' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh  by lh ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received '' 'ri' '' '' ''"
run_compare_test tests/received '' 'ri' '' '' '' <<END_OF_TEST_RESULTS
from ri ([ri])  by unknown
END_OF_TEST_RESULTS

vecho "Running test tests/received '' 'ri' '' '' 'EHLO hh'"
run_compare_test tests/received '' 'ri' '' '' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh ([ri])  by unknown
END_OF_TEST_RESULTS

vecho "Running test tests/received '' 'ri' '' 'li' ''"
run_compare_test tests/received '' 'ri' '' 'li' '' <<END_OF_TEST_RESULTS
from ri ([ri])  by li ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received '' 'ri' '' 'li' 'EHLO hh'"
run_compare_test tests/received '' 'ri' '' 'li' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh ([ri])  by li ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received '' 'ri' 'lh' '' ''"
run_compare_test tests/received '' 'ri' 'lh' '' '' <<END_OF_TEST_RESULTS
from ri ([ri])  by lh
END_OF_TEST_RESULTS

vecho "Running test tests/received '' 'ri' 'lh' '' 'EHLO hh'"
run_compare_test tests/received '' 'ri' 'lh' '' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh ([ri])  by lh
END_OF_TEST_RESULTS

vecho "Running test tests/received '' 'ri' 'lh' 'li' ''"
run_compare_test tests/received '' 'ri' 'lh' 'li' '' <<END_OF_TEST_RESULTS
from ri ([ri])  by lh ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received '' 'ri' 'lh' 'li' 'EHLO hh'"
run_compare_test tests/received '' 'ri' 'lh' 'li' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh ([ri])  by lh ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' '' '' '' ''"
run_compare_test tests/received 'rh' '' '' '' '' <<END_OF_TEST_RESULTS
from rh (rh)  by unknown
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' '' '' '' 'EHLO hh'"
run_compare_test tests/received 'rh' '' '' '' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh (rh)  by unknown
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' '' '' 'li' ''"
run_compare_test tests/received 'rh' '' '' 'li' '' <<END_OF_TEST_RESULTS
from rh (rh)  by li ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' '' '' 'li' 'EHLO hh'"
run_compare_test tests/received 'rh' '' '' 'li' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh (rh)  by li ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' '' 'lh' '' ''"
run_compare_test tests/received 'rh' '' 'lh' '' '' <<END_OF_TEST_RESULTS
from rh (rh)  by lh
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' '' 'lh' '' 'EHLO hh'"
run_compare_test tests/received 'rh' '' 'lh' '' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh (rh)  by lh
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' '' 'lh' 'li' ''"
run_compare_test tests/received 'rh' '' 'lh' 'li' '' <<END_OF_TEST_RESULTS
from rh (rh)  by lh ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' '' 'lh' 'li' 'EHLO hh'"
run_compare_test tests/received 'rh' '' 'lh' 'li' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh (rh)  by lh ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' 'ri' '' '' ''"
run_compare_test tests/received 'rh' 'ri' '' '' '' <<END_OF_TEST_RESULTS
from rh (rh [ri])  by unknown
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' 'ri' '' '' 'EHLO hh'"
run_compare_test tests/received 'rh' 'ri' '' '' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh (rh [ri])  by unknown
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' 'ri' '' 'li' ''"
run_compare_test tests/received 'rh' 'ri' '' 'li' '' <<END_OF_TEST_RESULTS
from rh (rh [ri])  by li ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' 'ri' '' 'li' 'EHLO hh'"
run_compare_test tests/received 'rh' 'ri' '' 'li' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh (rh [ri])  by li ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' 'ri' 'lh' '' ''"
run_compare_test tests/received 'rh' 'ri' 'lh' '' '' <<END_OF_TEST_RESULTS
from rh (rh [ri])  by lh
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' 'ri' 'lh' '' 'EHLO hh'"
run_compare_test tests/received 'rh' 'ri' 'lh' '' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh (rh [ri])  by lh
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' 'ri' 'lh' 'li' ''"
run_compare_test tests/received 'rh' 'ri' 'lh' 'li' '' <<END_OF_TEST_RESULTS
from rh (rh [ri])  by lh ([li])
END_OF_TEST_RESULTS

vecho "Running test tests/received 'rh' 'ri' 'lh' 'li' 'EHLO hh'"
run_compare_test tests/received 'rh' 'ri' 'lh' 'li' 'EHLO hh' <<END_OF_TEST_RESULTS
from hh (rh [ri])  by lh ([li])
END_OF_TEST_RESULTS


##### Test tests/pop3front-auth #####

runtest() {
$src/pop3front-auth false echo Yes. <<EOF 2>/dev/null
QUIT NO
QUIT
QUIT AGAIN
EOF
}
vecho "Running test tests/pop3front-auth "
run_compare_test tests/pop3front-auth  <<END_OF_TEST_RESULTS
+OK ^M
-ERR Syntax error^M
+OK ^M
END_OF_TEST_RESULTS


##### Test tests/qmtpfront-echo #####

runtest() {
printf '6:\ntest\n,13:a@example.com,17:13:b@example.com,,' \
| $src/mailfront qmtp echo 2>/dev/null
echo
}
vecho "Running test tests/qmtpfront-echo "
run_compare_test tests/qmtpfront-echo  <<END_OF_TEST_RESULTS
18:KReceived 5 bytes.,
END_OF_TEST_RESULTS


##### Test tests/pop3front-auth-userpass #####

runtest() {
# Should fix this and the others to actually check the stderr output too.
pfauth $src/testcvm <<EOF 2>/dev/null
USER testuser
PASS testpass
EOF
pfauth $src/testcvm <<EOF 2>/dev/null
USER testuser
PASS testpasx
EOF
}
vecho "Running test tests/pop3front-auth-userpass "
run_compare_test tests/pop3front-auth-userpass  <<END_OF_TEST_RESULTS
+OK ^M
Yes.
+OK ^M
-ERR Authentication failed^M
END_OF_TEST_RESULTS


##### Test tests/plugin-force-file #####

runtest() {
local tmpdir="$1"
local plugins="$2"

PLUGINS=${plugins}:add-received:accept
TMPDIR=$tmpdir 
export TMPDIR

sfecho <<EOF
MAIL FROM:<>
RCPT TO:<test@example.com>
DATA
.
EOF

unset TMPDIR
}
vecho "Running test tests/plugin-force-file '/tmp' ''"
run_compare_test tests/plugin-force-file '/tmp' '' <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='test@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 128 bytes.^M
END_OF_TEST_RESULTS

vecho "Running test tests/plugin-force-file '/tmp' 'force-file'"
run_compare_test tests/plugin-force-file '/tmp' 'force-file' <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='test@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 128 bytes.^M
END_OF_TEST_RESULTS

vecho "Running test tests/plugin-force-file '/@notmp@' ''"
run_compare_test tests/plugin-force-file '/@notmp@' '' <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='test@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 128 bytes.^M
END_OF_TEST_RESULTS

vecho "Running test tests/plugin-force-file '/@notmp@' 'force-file'"
run_compare_test tests/plugin-force-file '/@notmp@' 'force-file' <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='test@example.com'.^M
451 4.3.0 Internal error.^M
500 5.5.1 Not implemented.^M
END_OF_TEST_RESULTS


##### Test tests/pop3front-auth-login #####

runtest() {
pfauth false <<EOF
AUTH LOGIN
EOF

export CVM_SASL_LOGIN=$src/testcvm

pfauth false <<EOF
AUTH LOGIN
dGVzdHVzZXI=
dGVzdHBhc3x=
AUTH LOGIN
dGVzdHVzZXI=
dGVzdHBhc3M=
EOF

pfauth false <<EOF
AUTH LOGIN dGVzdHVzZXI=
dGVzdHBhc3M=
EOF

pfauth false <<EOF
AUTH LOGIN
dGVzdHVzZXI=
*
EOF

unset CVM_SASL_PLAIN
}
vecho "Running test tests/pop3front-auth-login "
run_compare_test tests/pop3front-auth-login  <<END_OF_TEST_RESULTS
-ERR Unrecognized authentication mechanism.^M
+ VXNlcm5hbWU6^M
+ UGFzc3dvcmQ6^M
-ERR Authentication failed.^M
+ VXNlcm5hbWU6^M
+ UGFzc3dvcmQ6^M
Yes.
+ UGFzc3dvcmQ6^M
Yes.
+ VXNlcm5hbWU6^M
+ UGFzc3dvcmQ6^M
-ERR Authentication failed.^M
END_OF_TEST_RESULTS


##### Test tests/pop3front-auth-none #####

runtest() {
pfauth false <<EOF
AUTH
EOF

export CVM_SASL_PLAIN=$src/testcvm

pfauth false <<EOF
AUTH
EOF

unset CVM_SASL_PLAIN
}
vecho "Running test tests/pop3front-auth-none "
run_compare_test tests/pop3front-auth-none  <<END_OF_TEST_RESULTS
+OK ^M
.^M
+OK ^M
LOGIN^M
PLAIN^M
.^M
END_OF_TEST_RESULTS


##### Test tests/rules-header-add #####

runtest() {
PLUGINS=mailrules:accept

cat >$tmp/rules <<EOF
ka@example.com:b@example.com:K1:::HEADER_ADD="X-Header: testing!!!"
EOF

MAILRULES=$tmp/rules

sfecho <<EOF
MAIL FROM:<a@example.com>
RCPT TO:<b@example.com>
DATA
.
EOF

sfecho <<EOF
MAIL FROM:<a@example.com>
RCPT TO:<c@example.com>
DATA
.
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-header-add "
run_compare_test tests/rules-header-add  <<END_OF_TEST_RESULTS
250 Sender='a@example.com'.^M
250 K1^M
354 End your message with a period on a line by itself.^M
250 Received 0 bytes.^M
250 Sender='a@example.com'.^M
250 Recipient='c@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 0 bytes.^M
END_OF_TEST_RESULTS


##### Test tests/pop3front-maildir-sort #####

runtest() {
maildir
tstmsg new/99
tstmsg cur/100
tstmsg new/101
tstmsg cur/98

echo UIDL | pfmaildir $maildir
}
vecho "Running test tests/pop3front-maildir-sort "
run_compare_test tests/pop3front-maildir-sort  <<END_OF_TEST_RESULTS
+OK ^M
1 98^M
2 99^M
3 100^M
4 101^M
.^M
END_OF_TEST_RESULTS


##### Test tests/imapfront-auth #####

runtest() {
CVM_SASL_PLAIN=$src/testcvm
export CVM_SASL_PLAIN

ifauth <<EOF
1 LOGIN
2 LOGIN A
3 LOGIN A B C
4 LoGiN A B
5 LOGIN testuser testpass
EOF

ifauth <<EOF
6 login "testuser" "testpass"
EOF

ifauth <<EOF
7 login {8}
testuser{8}
testpass
EOF

unset CVM_SASL_PLAIN
}
vecho "Running test tests/imapfront-auth "
run_compare_test tests/imapfront-auth  <<END_OF_TEST_RESULTS
1 BAD Syntax error: command requires arguments^M
2 BAD LOGIN command requires exactly two arguments^M
3 BAD LOGIN command requires exactly two arguments^M
4 NO LOGIN failed^M
Yes: 5
Yes: 6
+ OK^M
+ OK^M
Yes: 7
END_OF_TEST_RESULTS


##### Test tests/smtpgreeting #####

runtest() {
env SMTPGREETING='hostname hello' $src/mailfront smtp echo 2>/dev/null </dev/null
}
vecho "Running test tests/smtpgreeting "
run_compare_test tests/smtpgreeting  <<END_OF_TEST_RESULTS
220 hostname hello ESMTP^M
END_OF_TEST_RESULTS


##### Test tests/rules-databytes3 #####

runtest() {
PLUGINS=mailrules:counters:accept
DATABYTES=1000
export DATABYTES

cat >$tmp/rules <<EOF
ka@example.com:*::123
EOF

MAILRULES=$tmp/rules

sfecho <<EOF
EHLO hostname
MAIL FROM:<a@example.com>
MAIL FROM:<a@example.com> SIZE
MAIL FROM:<a@example.com> SIZE=
MAIL FROM:<a@example.com> SIZE=100
MAIL FROM:<a@example.com> SIZE=123
MAIL FROM:<a@example.com> SIZE=124
RCPT TO:<nobody@example.net>
MAIL FROM:<a@example.com>
RCPT TO:<nobody@example.com>
DATA
datadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadata
datadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadata
datadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadata
datadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadata
.
EHLO hostname
MAIL FROM:<b@example.com>
RCPT TO:<nobody@example.com>
DATA
datadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadata
datadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadata
datadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadata
datadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadatadata
.
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-databytes3 "
run_compare_test tests/rules-databytes3  <<END_OF_TEST_RESULTS
250-local.host^M
250-SIZE 1000^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
250 OK^M
250 OK^M
250 OK^M
250 OK^M
250 OK^M
552 5.2.3 The message would exceed the maximum message size.^M
503 5.5.1 You must send MAIL FROM: first^M
250 OK^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
552 5.2.3 Sorry, that message exceeds the maximum message length.^M
250-local.host^M
250-SIZE 1000^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
250 Sender='b@example.com'.^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 308 bytes.^M
END_OF_TEST_RESULTS


##### Test tests/pop3front-maildir-numbers #####

runtest() {
maildir
cat > $maildir/new/1.2.3 <<EOF
header

body
EOF

pfmaildir $maildir <<EOF
RETR -1
RETR 0
RETR 1
RETR 2
TOP 1 -1
TOP 1 0
TOP 1 1
UIDL -1
UIDL 0
UIDL 1
UIDL 2
LIST -1
LIST 0
LIST 1
LIST 2
DELE -1
DELE 0
DELE 1
DELE 2
DELE 1
EOF
}
vecho "Running test tests/pop3front-maildir-numbers "
run_compare_test tests/pop3front-maildir-numbers  <<END_OF_TEST_RESULTS
-ERR Syntax error^M
-ERR Message number out of range^M
+OK ^M
header^M
^M
body^M
^M
.^M
-ERR Message number out of range^M
-ERR Syntax error^M
+OK ^M
header^M
^M
^M
.^M
+OK ^M
header^M
^M
body^M
^M
.^M
-ERR Syntax error^M
-ERR Message number out of range^M
+OK 1 1.2.3^M
-ERR Message number out of range^M
-ERR Syntax error^M
-ERR Message number out of range^M
+OK 1 13^M
-ERR Message number out of range^M
-ERR Syntax error^M
-ERR Message number out of range^M
+OK ^M
-ERR Message number out of range^M
-ERR Message was deleted^M
END_OF_TEST_RESULTS


##### Test tests/plugin-require-auth #####

runtest() {
PLUGINS=cvm-authenticate:require-auth:relayclient:accept

export CVM_SASL_PLAIN=$src/testcvm

sfecho <<EOF
MAIL FROM: <user@example.net>
RCPT TO: <user@example.net>
AUTH PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3M=
MAIL FROM: <user@example.net>
RCPT TO: <user@example.net>
EOF

unset CVM_SASL_PLAIN
unset REQUIRE_AUTH
}
vecho "Running test tests/plugin-require-auth "
run_compare_test tests/plugin-require-auth  <<END_OF_TEST_RESULTS
530 5.7.1 You must authenticate first.^M
503 5.5.1 You must send MAIL FROM: first^M
235 2.7.0 Authentication succeeded.^M
250 Sender='user@example.net'.^M
250 Recipient='user@example.net'.^M
END_OF_TEST_RESULTS


##### Test tests/patterns-normal #####

runtest() {
PLUGINS=patterns:accept

cat >$tmp/patterns <<EOF
# comment

/before
# comment
EOF

PATTERNS=$tmp/patterns

sfecho <<EOF
MAIL FROM:<>
RCPT TO:<nobody@example.com>
DATA
before

after
.
EOF

rm -f $tmp/patterns
}
vecho "Running test tests/patterns-normal "
run_compare_test tests/patterns-normal  <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
554 This message contains prohibited content^M
END_OF_TEST_RESULTS


##### Test tests/plugin-counters-looping-delivered-to #####

runtest() {
PLUGINS=counters:accept

MAXHOPS=1
export MAXHOPS

sfecho <<EOF
MAIL FROM:<somebody@example.com>
RCPT TO:<nobody@example.org>
DATA
Delivered-To: foo
.
EOF

echo

sfecho <<EOF
MAIL FROM:<somebody@example.com>
RCPT TO:<nobody@example.org>
DATA
Delivered-To: foo
Delivered-To: foo
.
EOF
}
vecho "Running test tests/plugin-counters-looping-delivered-to "
run_compare_test tests/plugin-counters-looping-delivered-to  <<END_OF_TEST_RESULTS
250 Sender='somebody@example.com'.^M
250 Recipient='nobody@example.org'.^M
354 End your message with a period on a line by itself.^M
250 Received 18 bytes.^M

250 Sender='somebody@example.com'.^M
250 Recipient='nobody@example.org'.^M
354 End your message with a period on a line by itself.^M
554 5.6.0 This message is looping, too many hops.^M
END_OF_TEST_RESULTS


##### Test tests/smtpfront-addrfail #####

runtest() {
sfecho <<EOF
MAIL FROM
MAIL FROM 
MAIL FROM:
MAIL FROM<
MAIL FROM>
EOF
}
vecho "Running test tests/smtpfront-addrfail "
run_compare_test tests/smtpfront-addrfail  <<END_OF_TEST_RESULTS
501 5.5.2 Syntax error in address parameter.^M
501 5.5.2 Syntax error in address parameter.^M
501 5.5.2 Syntax error in address parameter.^M
501 5.5.2 Syntax error in address parameter.^M
501 5.5.2 Syntax error in address parameter.^M
END_OF_TEST_RESULTS


##### Test tests/plugin-counters-maxrcpts #####

runtest() {
PLUGINS=counters:accept

MAXRCPTS=2
export MAXRCPTS

sfecho <<EOF
MAIL FROM:<notbounce@example.com>
RCPT TO:<addr1@example.net>
RCPT TO:<addr2@example.net>
RCPT TO:<addr3@example.net>
RCPT TO:<addr4@example.net>
DATA
.
EOF

MAXRCPTS_REJECT=1
export MAXRCPTS_REJECT

sfecho <<EOF
MAIL FROM:<notbounce@example.com>
RCPT TO:<addr1@example.net>
RCPT TO:<addr2@example.net>
RCPT TO:<addr3@example.net>
RCPT TO:<addr4@example.net>
DATA
.
EOF

unset MAXRCPTS
unset MAXRCPTS_REJECT
}
vecho "Running test tests/plugin-counters-maxrcpts "
run_compare_test tests/plugin-counters-maxrcpts  <<END_OF_TEST_RESULTS
250 Sender='notbounce@example.com'.^M
250 Recipient='addr1@example.net'.^M
250 Recipient='addr2@example.net'.^M
550 5.5.3 Too many recipients^M
550 5.5.3 Too many recipients^M
354 End your message with a period on a line by itself.^M
250 Received 0 bytes.^M
250 Sender='notbounce@example.com'.^M
250 Recipient='addr1@example.net'.^M
250 Recipient='addr2@example.net'.^M
550 5.5.3 Too many recipients^M
550 5.5.3 Too many recipients^M
550 5.5.3 Too many recipients^M
500 5.5.1 Not implemented.^M
END_OF_TEST_RESULTS


##### Test tests/qmqpfront-echo #####

runtest() {
printf '42:5:test\n,13:a@example.com,13:b@example.com,,' \
| $src/mailfront qmqp echo 2>/dev/null
echo
}
vecho "Running test tests/qmqpfront-echo "
run_compare_test tests/qmqpfront-echo  <<END_OF_TEST_RESULTS
18:KReceived 5 bytes.,
END_OF_TEST_RESULTS


##### Test tests/imapfront-mailenv #####

runtest() {
CVM_SASL_PLAIN=$src/testcvm
export CVM_SASL_PLAIN

$src/imapfront-auth sh -c 'echo MAIL=$MAIL MAILBOX=$MAILBOX MAILDIR=$MAILDIR' 2>/dev/null << EOF \
| grep -v '^\* OK imapfront ready.'
1 login testuser testpass
EOF

env SETUP_ENV=dovecot \
$src/imapfront-auth sh -c 'echo MAIL=$MAIL' 2>/dev/null << EOF \
| grep -v '^\* OK imapfront ready.'
1 login testuser testpass
EOF

mkdir "$tmp"/mail:box

env SETUP_ENV=dovecot \
$src/imapfront-auth sh -c 'echo MAIL=$MAIL' 2>/dev/null << EOF \
| grep -v '^\* OK imapfront ready.'
1 login testuser testpass
EOF

rmdir "$tmp"/mail:box
}
vecho "Running test tests/imapfront-mailenv "
run_compare_test tests/imapfront-mailenv  <<END_OF_TEST_RESULTS
MAIL=@TMPDIR@/mail:box MAILBOX=@TMPDIR@/mail:box MAILDIR=@TMPDIR@/mail:box
MAIL=mbox:@TMPDIR@/mail::box
MAIL=maildir:@TMPDIR@/mail::box
END_OF_TEST_RESULTS


##### Test tests/pop3front-auth-split #####

runtest() {
pfauth $src/testcvm <<EOF
USER testuser@adomain
PASS testpass
EOF
pfauth $src/testcvm <<EOF
USER testuser@adomain
PASS testpasx
EOF
}
vecho "Running test tests/pop3front-auth-split "
run_compare_test tests/pop3front-auth-split  <<END_OF_TEST_RESULTS
+OK ^M
Yes.
+OK ^M
-ERR Authentication failed^M
END_OF_TEST_RESULTS


##### Test tests/rules-list #####

runtest() {
PLUGINS=mailrules:accept

cat >$tmp/rules <<EOF
k[[$tmp/list]]:*:LIST
k[[@$tmp/atlist]]:*:ATLIST
d*:*:DD
EOF

cat >$tmp/list <<EOF
a@example.net
@example.com
EOF

cat >$tmp/atlist <<EOF
example.biz
EOF

MAILRULES=$tmp/rules

sfecho <<EOF
MAIL FROM:<>
MAIL FROM:<a@example.net>
MAIL FROM:<b@example.net>
MAIL FROM:<a@example.biz>
MAIL FROM:<b@Example.BIZ>
MAIL FROM:<c@example.com>
MAIL FROM:<c@Example.COM>
MAIL FROM:<d@example.org>
EOF

rm -f $tmp/rules $tmp/list $tmp/atlist
}
vecho "Running test tests/rules-list "
run_compare_test tests/rules-list  <<END_OF_TEST_RESULTS
553 DD^M
250 LIST^M
553 DD^M
250 ATLIST^M
250 ATLIST^M
250 LIST^M
250 LIST^M
553 DD^M
END_OF_TEST_RESULTS


##### Test tests/plugin-counters-maxmsgs #####

runtest() {
PLUGINS=counters:accept

MAXMSGS=1
export MAXMSGS

sfecho <<EOF
MAIL FROM:<notbounce@example.com>
RCPT TO:<addr@example.net>
DATA
.
MAIL FROM:<notbounce@example.com>
RCPT TO:<addr@example.net>
DATA
.
EOF

unset MAXMSGS
}
vecho "Running test tests/plugin-counters-maxmsgs "
run_compare_test tests/plugin-counters-maxmsgs  <<END_OF_TEST_RESULTS
250 Sender='notbounce@example.com'.^M
250 Recipient='addr@example.net'.^M
354 End your message with a period on a line by itself.^M
250 Received 0 bytes.^M
550 5.5.0 Too many messages^M
503 5.5.1 You must send MAIL FROM: first^M
503 5.5.1 You must send MAIL FROM: first^M
500 5.5.1 Not implemented.^M
END_OF_TEST_RESULTS


##### Test tests/rules-multiline #####

runtest() {
PLUGINS=mailrules:accept

cat >$tmp/rules <<EOF
ka@example.com:*:ONE\nTWO
ka@example.net:*:ONE\:TWO
ka@example.org:*:ONE\\\\TWO:
EOF

MAILRULES=$tmp/rules
export MAILRULES

sfecho <<EOF
MAIL FROM:<a@example.com>
MAIL FROM:<a@example.net>
MAIL FROM:<a@example.org>
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-multiline "
run_compare_test tests/rules-multiline  <<END_OF_TEST_RESULTS
250-ONE^M
250 TWO^M
250 ONE:TWO^M
250 ONE\TWO^M
END_OF_TEST_RESULTS


##### Test tests/rules-databytes2 #####

runtest() {
PLUGINS=mailrules:counters:accept

cat >$tmp/rules <<EOF
k*:a@example.com::9999
k*:b@example.com::1
k*:c@example.com::
EOF

MAILRULES=$tmp/rules

sfecho <<EOF
EHLO hostname
MAIL FROM:<somebody@example.net> SIZE=10000
RCPT TO:<a@example.com>
DATA
testing
.
EHLO hostname
MAIL FROM:<somebody@example.net> SIZE=10000
RCPT TO:<a@example.com>
RCPT TO:<b@example.com>
DATA
testing
.
EHLO hostname
MAIL FROM:<somebody@example.net> SIZE=10000
RCPT TO:<a@example.com>
RCPT TO:<b@example.com>
RCPT TO:<c@example.com>
DATA
testing
.
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-databytes2 "
run_compare_test tests/rules-databytes2  <<END_OF_TEST_RESULTS
250-local.host^M
250-SIZE 0^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
250 Sender='somebody@example.net'. [SIZE=10000]^M
250 OK^M
354 End your message with a period on a line by itself.^M
250 Received 8 bytes.^M
250-local.host^M
250-SIZE 0^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
250 Sender='somebody@example.net'. [SIZE=10000]^M
250 OK^M
250 OK^M
354 End your message with a period on a line by itself.^M
552 5.2.3 Sorry, that message exceeds the maximum message length.^M
250-local.host^M
250-SIZE 0^M
250-8BITMIME^M
250-ENHANCEDSTATUSCODES^M
250 PIPELINING^M
250 Sender='somebody@example.net'. [SIZE=10000]^M
250 OK^M
250 OK^M
250 OK^M
354 End your message with a period on a line by itself.^M
552 5.2.3 Sorry, that message exceeds the maximum message length.^M
END_OF_TEST_RESULTS


##### Test tests/smtpfront-maxnotimpl #####

runtest() {
MAXNOTIMPL=1

sfecho <<EOF
a
b
c
d
EOF

MAXNOTIMPL=0

sfecho <<EOF
a
b
c
d
EOF
}
vecho "Running test tests/smtpfront-maxnotimpl "
run_compare_test tests/smtpfront-maxnotimpl  <<END_OF_TEST_RESULTS
500 5.5.1 Not implemented.^M
503-5.5.0 Too many unimplemented commands.^M
503 5.5.0 Closing connection.^M
500 5.5.1 Not implemented.^M
500 5.5.1 Not implemented.^M
500 5.5.1 Not implemented.^M
500 5.5.1 Not implemented.^M
END_OF_TEST_RESULTS


##### Test tests/rules-noop #####

runtest() {
PLUGINS=mailrules:relayclient:accept

cat >$tmp/rules <<EOF
n*:*:Do not see this:::RELAYCLIENT=@rc
EOF

MAILRULES=$tmp/rules

sfecho <<EOF
MAIL FROM:<a@example.com>
RCPT TO:<b@example.net>
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-noop "
run_compare_test tests/rules-noop  <<END_OF_TEST_RESULTS
250 Sender='a@example.com'.^M
250 Recipient='b@example.net@rc'.^M
END_OF_TEST_RESULTS


##### Test tests/rules-recip #####

runtest() {
PLUGINS=mailrules:accept

cat >$tmp/rules <<EOF
k*:one@one.example.com:KK
d*:two@two.example.com:DD
z*:three@three.example.com:ZZ
zx@y:four@four.example.com:ZZZ
p*:five@five.example.com:PP
EOF

MAILRULES=$tmp/rules

sfecho <<EOF
MAIL FROM:<nobody@example.net>
RCPT TO:<one@one.example.com>
RCPT TO:<two@two.example.com>
RCPT TO:<three@three.example.com>
RCPT TO:<four@four.example.com>
RCPT TO:<five@five.example.com>
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-recip "
run_compare_test tests/rules-recip  <<END_OF_TEST_RESULTS
250 Sender='nobody@example.net'.^M
250 KK^M
553 DD^M
451 ZZ^M
250 Recipient='four@four.example.com'.^M
250 Recipient='five@five.example.com'.^M
END_OF_TEST_RESULTS


##### Test tests/rules-rcptlist #####

runtest() {
PLUGINS=mailrules:accept

cat >$tmp/rules <<EOF
:r
k*:[[$tmp/list]]:LIST
k*:[[@$tmp/atlist]]:ATLIST
d*:*:DD
EOF

cat >$tmp/list <<EOF
a@example.net
@example.com
EOF

cat >$tmp/atlist <<EOF
example.org
EOF

MAILRULES=$tmp/rules $src/mailfront smtp echo <<EOF 2>/dev/null | tail -n +2
MAIL FROM:<nobody@example.com>
RCPT TO:<a@example.net>
RCPT TO:<b@example.net>
RCPT TO:<a@example.org>
RCPT TO:<b@example.org>
RCPT TO:<c@example.com>
RCPT TO:<c@Example.COM>
RCPT TO:<d@example.biz>
EOF

rm -f $tmp/rules $tmp/list $tmp/atlist
}
vecho "Running test tests/rules-rcptlist "
run_compare_test tests/rules-rcptlist  <<END_OF_TEST_RESULTS
250 Sender='nobody@example.com'.^M
250 LIST^M
553 DD^M
250 ATLIST^M
250 ATLIST^M
250 LIST^M
250 LIST^M
553 DD^M
END_OF_TEST_RESULTS


##### Test tests/received-ipv6 #####

runtest() {
PLUGINS=add-received:accept
PROTO=TCP6
TCP6LOCALHOST="localhost"
TCP6LOCALIP="localip"
TCP6REMOTEHOST="remotehost"
TCP6REMOTEIP="remoteip"

export TCP6LOCALHOST TCP6LOCALIP TCP6REMOTEHOST TCP6REMOTEIP

$src/mailfront smtp echo 2>&1 >/dev/null <<EOF | \
	sed -n -e 's/^.* Received: //p'
$helo
MAIL FROM:<>
RCPT TO:<test@example.com>
DATA
.
EOF

PROTO=TEST
unset TCP6LOCALHOST TCP6LOCALIP TCP6REMOTEHOST TCP6REMOTEIP
}
vecho "Running test tests/received-ipv6 "
run_compare_test tests/received-ipv6  <<END_OF_TEST_RESULTS
from remotehost (remotehost [IPv6:remoteip])  by localhost ([IPv6:localip])
END_OF_TEST_RESULTS


##### Test tests/rules-both #####

runtest() {
PLUGINS=mailrules:accept

cat >$tmp/rules <<EOF
ka@example.net:a@example.com:K1
ka@example.net:b@example.com:K2
kb@example.net:a@example.com:K3
kb@example.net:b@example.com:K4
EOF

MAILRULES=$tmp/rules

sfecho <<EOF
MAIL FROM:<>
RCPT TO:<a@example.com>
MAIL FROM:<a@example.net>
RCPT TO:<a@example.com>
RCPT TO:<b@example.com>
MAIL FROM:<b@example.net>
RCPT TO:<a@example.com>
RCPT TO:<b@example.com>
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-both "
run_compare_test tests/rules-both  <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='a@example.com'.^M
250 Sender='a@example.net'.^M
250 K1^M
250 K2^M
250 Sender='b@example.net'.^M
250 K3^M
250 K4^M
END_OF_TEST_RESULTS


##### Test tests/pop3front-maildir-last #####

runtest() {
pflast() { echo LAST | pfmaildir $maildir; }
maildir
tstmsg new/1
tstmsg new/2
pflast
mv $maildir/new/1 $maildir/cur/1
pflast
mv $maildir/cur/1 $maildir/cur/1:2,S
pflast
mv $maildir/new/2 $maildir/cur/2:2,S
pflast
mv $maildir/cur/1:2,S $maildir/new/1
pflast
}
vecho "Running test tests/pop3front-maildir-last "
run_compare_test tests/pop3front-maildir-last  <<END_OF_TEST_RESULTS
+OK 0^M
+OK 0^M
+OK 1^M
+OK 2^M
+OK 2^M
END_OF_TEST_RESULTS


##### Test tests/patterns-general #####

runtest() {
local subject="$1"
PLUGINS=patterns:accept

cat >$tmp/patterns <<EOF
/Subject: *word*
EOF

PATTERNS=$tmp/patterns

sfecho <<EOF
MAIL FROM:<>
RCPT TO:<nobody@example.com>
DATA
Subject: $subject
.
EOF

rm -f $tmp/patterns
}
vecho "Running test tests/patterns-general 'xwordx'"
run_compare_test tests/patterns-general 'xwordx' <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
554 This message contains prohibited content^M
END_OF_TEST_RESULTS

vecho "Running test tests/patterns-general 'word at the beginning'"
run_compare_test tests/patterns-general 'word at the beginning' <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
554 This message contains prohibited content^M
END_OF_TEST_RESULTS

vecho "Running test tests/patterns-general 'last word'"
run_compare_test tests/patterns-general 'last word' <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
554 This message contains prohibited content^M
END_OF_TEST_RESULTS

vecho "Running test tests/patterns-general 'middle word middle'"
run_compare_test tests/patterns-general 'middle word middle' <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
554 This message contains prohibited content^M
END_OF_TEST_RESULTS

vecho "Running test tests/patterns-general 'word'"
run_compare_test tests/patterns-general 'word' <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
554 This message contains prohibited content^M
END_OF_TEST_RESULTS

vecho "Running test tests/patterns-general 'xord'"
run_compare_test tests/patterns-general 'xord' <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 14 bytes.^M
END_OF_TEST_RESULTS


##### Test tests/pop3front-auth-toomany #####

runtest() {
local limit="$1"
export MAXUSERCMD=$limit
export MAXAUTHFAIL=$limit

pfauth $src/testcvm <<EOF
USER a
USER b
USER c
USER d
EOF

echo
pfauth $src/testcvm <<EOF
USER a
PASS a
USER b
PASS b
USER c
PASS c
USER d
PASS d
EOF

export CVM_SASL_PLAIN=$src/testcvm

echo
pfauth $src/testcvm <<EOF
AUTH PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBxc3M=
AUTH PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBxc3M=
AUTH PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBxc3M=
AUTH PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBxc3M=
EOF

unset MAXUSERCMD MAXAUTHFAIL CVM_SASL_PLAIN
}
vecho "Running test tests/pop3front-auth-toomany '0'"
run_compare_test tests/pop3front-auth-toomany '0' <<END_OF_TEST_RESULTS
+OK ^M
+OK ^M
+OK ^M
+OK ^M

+OK ^M
-ERR Authentication failed^M
+OK ^M
-ERR Authentication failed^M
+OK ^M
-ERR Authentication failed^M
+OK ^M
-ERR Authentication failed^M

-ERR Authentication failed.^M
-ERR Authentication failed.^M
-ERR Authentication failed.^M
-ERR Authentication failed.^M
END_OF_TEST_RESULTS

vecho "Running test tests/pop3front-auth-toomany '2'"
run_compare_test tests/pop3front-auth-toomany '2' <<END_OF_TEST_RESULTS
+OK ^M
+OK ^M
-ERR Too many USER commands issued^M

+OK ^M
-ERR Authentication failed^M
+OK ^M
-ERR Authentication failed^M

-ERR Authentication failed.^M
-ERR Authentication failed.^M
END_OF_TEST_RESULTS


##### Test tests/rules-maxhops #####

runtest() {
PLUGINS=mailrules:counters:accept

cat >$tmp/rules <<EOF
ka@example.com:b@example.com:K1:::MAXHOPS=1
EOF

MAILRULES=$tmp/rules
export MAILRULES

sfecho <<EOF
MAIL FROM:<a@example.com>
RCPT TO:<b@example.com>
DATA
Received: hop1
Received: hop2
.
EOF
MAILRULES=$tmp/rules sfecho <<EOF
MAIL FROM:<a@example.com>
RCPT TO:<c@example.com>
DATA
Received: hop1
Received: hop1
.
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-maxhops "
run_compare_test tests/rules-maxhops  <<END_OF_TEST_RESULTS
250 Sender='a@example.com'.^M
250 K1^M
354 End your message with a period on a line by itself.^M
554 5.6.0 This message is looping, too many hops.^M
250 Sender='a@example.com'.^M
250 Recipient='c@example.com'.^M
354 End your message with a period on a line by itself.^M
250 Received 30 bytes.^M
END_OF_TEST_RESULTS


##### Test tests/plugin-cvm-auth-plain #####

runtest() {
PLUGINS=cvm-authenticate:relayclient:accept-sender

sfecho <<EOF
AUTH PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3M=
EOF

export CVM_SASL_PLAIN=$src/testcvm

sfecho <<EOF
MAIL FROM: <user@example.com>
RCPT TO: <user@example.com>
AUTH PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3x=
AUTH PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3M=
AUTH PLAIN dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3M=
MAIL FROM: <user@example.com>
RCPT TO: <user@example.com>
EOF

sfecho << EOF
AUTH PLAIN
dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3M=
EOF

sfecho <<EOF
AUTH PLAIN
*
MAIL FROM: <user@example.com>
RCPT TO: <user@example.com>
EOF

sfecho << EOF
AUTH PLAIN XXXXdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3M=
EOF

unset CVM_SASL_PLAIN
}
vecho "Running test tests/plugin-cvm-auth-plain "
run_compare_test tests/plugin-cvm-auth-plain  <<END_OF_TEST_RESULTS
500 5.5.1 Not implemented.^M
250 Sender='user@example.com'.^M
550 5.1.0 Mail system is not configured to accept that recipient^M
501 Authentication failed.^M
235 2.7.0 Authentication succeeded.^M
503 5.5.1 You are already authenticated.^M
250 Sender='user@example.com'.^M
250 Recipient='user@example.com'.^M
334 ^M
235 2.7.0 Authentication succeeded.^M
334 ^M
501 Authentication failed.^M
250 Sender='user@example.com'.^M
550 5.1.0 Mail system is not configured to accept that recipient^M
235 2.7.0 Authentication succeeded.^M
END_OF_TEST_RESULTS


##### Test tests/rules-defaultmsg #####

runtest() {
PLUGINS=mailrules:accept

cat >$tmp/rules <<EOF
dd@example.com:*
zz@example.com:*
kk@example.com:*
d*:d@example.com
z*:z@example.com
k*:k@example.com
EOF

MAILRULES=$tmp/rules

sfecho <<EOF
MAIL FROM:<d@example.com>
MAIL FROM:<z@example.com>
MAIL FROM:<k@example.com>
RCPT TO:<d@example.com>
RCPT TO:<z@example.com>
RCPT TO:<k@example.com>
EOF

rm -f $tmp/rules
}
vecho "Running test tests/rules-defaultmsg "
run_compare_test tests/rules-defaultmsg  <<END_OF_TEST_RESULTS
553 Rejected^M
451 Deferred^M
250 OK^M
553 Rejected^M
451 Deferred^M
250 OK^M
END_OF_TEST_RESULTS


##### Test tests/patterns-message #####

runtest() {
PLUGINS=patterns:accept

cat >$tmp/patterns <<EOF
=response 1
=response 2
/*
=response 3
EOF

PATTERNS=$tmp/patterns

sfecho <<EOF
MAIL FROM:<>
RCPT TO:<nobody@example.com>
DATA
before

after
.
EOF

rm -f $tmp/patterns
}
vecho "Running test tests/patterns-message "
run_compare_test tests/patterns-message  <<END_OF_TEST_RESULTS
250 Sender=''.^M
250 Recipient='nobody@example.com'.^M
354 End your message with a period on a line by itself.^M
554 response 2^M
END_OF_TEST_RESULTS


rm -rf $tmp
echo $tests_count tests executed, $tests_failed failures
if [ $tests_failed != 0 ]; then exit 1; fi
