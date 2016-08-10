#! /usr/bin/perl --warning -I ..
#
# MySQL Database Server Tests via check_mailbox_healthdb
#
#
# These are the database permissions required for this test:
#  GRANT SELECT ON $db.* TO $user@$host INDENTIFIED BY '$password';
#  GRANT SUPER, REPLICATION CLIENT ON *.* TO $user@$host;
# Check with:
#  mailbox -u$user -p$password -h$host $db

use strict;
use Test::More;
use NPTest;
use POSIX ":sys_wait_h";

use vars qw($tests);

plan skip_all => "check_mailbox_health not compiled" unless (-x "../plugins-scripts/check_mailbox_health" || -x "plugins-scripts/check_mailbox_health");
#plan skip_all => "i need java to run the greenmail server simulator" unless 
$ENV{PATH} = "../plugins-scripts:".$ENV{PATH} if -x "../plugins-scripts/check_mailbox_health";
$ENV{PATH} = "plugins-scripts:".$ENV{PATH} if -x "plugins-scripts/check_mailbox_health";

plan tests => 16;

my $mailboxserver = "127.0.0.1";
my $mailbox_username = "test";
my $mailbox_password = "test%test";
my $mailbox_folder = "INBOX";

my $result;

my $pid_of_green = 0;

SKIP: {
  system("java -Dgreenmail.setup.test.all -Dgreenmail.users=test:test%test -jar greenmail-standalone-1.5.1.jar &");
}

SKIP: {
  diag("block2 ".$$);
  #$result = NPTest->testCmd("check_mailbox_health --hostname $mailboxserver --mode connection-time --username dummy --password dummy --timeout 5");
  #cmp_ok($result->return_code, '==', 2, "timeout");
  #like($result->output, "/CRITICAL - .*Access denied/", "Expected login failure message");
  #diag($result->output);
  $result = NPTest->testCmd("check_mailbox_health --hostname $mailboxserver --port 3143 --mode connection-time --username dummy --password dummy --timeout 5");
  cmp_ok($result->return_code, '==', 2, "user or password probably wrong");
  like($result->output, "/CRITICAL - .*user or password probably wrong/", "Expected login failure message");
  diag($result->output);
  $result = NPTest->testCmd("check_mailbox_health --hostname $mailboxserver --port 3143 --mode connection-time --username test --password test%test");
  cmp_ok($result->return_code, '==', 0, "Login ok");
  like($result->output, "/OK - \[\\d\\.\]+ seconds to connect as test/", "Expected login failure message");
  diag($result->output);
  $result = NPTest->testCmd("check_mailbox_health --hostname $mailboxserver --port 3993 --ssl --mode connection-time --username test --password test%test");
  cmp_ok($result->return_code, '==', 0, "Login ok");
  like($result->output, "/OK - \[\\d\\.\]+ seconds to connect as test/", "Expected login failure message");
  diag($result->output);
}

SKIP: {
  $result = NPTest->testCmd("check_mailbox_health --hostname $mailboxserver --port 3993 --ssl --mode count-mails --username test --password test%test");
  cmp_ok($result->return_code, '==', 0, "Count ok");
  like($result->output, "/OK - 0 mails in mailbox \| 'mails'=0;30;60;;/", "Expected mail count");
  diag($result->output);
}

SKIP: {
  eval "require Net::SMTP";
  skip "kein Net::SMTP" if $@;
  my $smtpserver = '127.0.0.1';
  my $smtpport = 3025;
  my $smtpuser   = 'test';
  my $smtppassword = 'test%test';

  my $smtp = Net::SMTP->new($smtpserver, Port=>$smtpport, Timeout => 10, Debug => 0);
  die "Could not connect to server!\n" unless $smtp;
  $smtp->auth($smtpuser, $smtppassword);
  $smtp->mail('test');
  $smtp->to('test');
  $smtp->data();
  $smtp->datasend("To: test\n");
  $smtp->datasend("Subject: huhu\n");
  $smtp->dataend();
  $smtp->quit;
}

SKIP: {
  $result = NPTest->testCmd("check_mailbox_health --hostname $mailboxserver --port 3993 --ssl --mode count-mails --username test --password test%test");
  cmp_ok($result->return_code, '==', 0, "Count ok");
  like($result->output, "/OK - 1 mails in mailbox \| 'mails'=0;30;60;;/", "Expected mail count");
  diag($result->output);
}

SKIP: {
  eval "require Net::SMTP";
  skip "kein Net::SMTP" if $@;
  my $smtpserver = '127.0.0.1';
  my $smtpport = 3025;
  my $smtpuser   = 'test';
  my $smtppassword = 'test%test';

  my $smtp = Net::SMTP->new($smtpserver, Port=>$smtpport, Timeout => 10, Debug => 0);
  die "Could not connect to server!\n" unless $smtp;
  $smtp->auth($smtpuser, $smtppassword);
  foreach (1..100) {
    $smtp->mail('test');
    $smtp->to('test');
    $smtp->data();
    $smtp->datasend("To: test\n");
    $smtp->datasend("Subject: huhu\n");
    $smtp->dataend();
  }
  foreach (1..10) {
    $smtp->mail('test');
    $smtp->to('test');
    $smtp->data();
    $smtp->datasend("To: test\n");
    $smtp->datasend("Subject: hihihuhu\n");
    $smtp->dataend();
  }
  $smtp->quit;
  diag("end of spam");
}

SKIP: {
  $result = NPTest->testCmd("check_mailbox_health --hostname $mailboxserver --port 3993 --ssl --mode count-mails --username test --password test%test");
  cmp_ok($result->return_code, '==', 2, "Count ok");
  like($result->output, "/CRITICAL - 111 mails in mailbox \| 'mails'=111;30;60;;/", "Expected mail count");
  diag($result->output);
  $result = NPTest->testCmd("check_mailbox_health --hostname $mailboxserver --port 3993 --ssl --mode count-mails --username test --password test%test --select subject=hihihuhu");
  cmp_ok($result->return_code, '==', 0, "Count ok");
  like($result->output, "/OK - 10 mails in mailbox \| 'mails'=10;30;60;;/", "Expected mail count");
  diag($result->output);
  $result = NPTest->testCmd("check_mailbox_health --hostname $mailboxserver --port 3993 --ssl --mode count-mails --username test --password test%test --select subject=hihi --regexp");
  cmp_ok($result->return_code, '==', 0, "Count ok");
  like($result->output, "/OK - 10 mails in mailbox \| 'mails'=10;30;60;;/", "Expected mail count");
  diag($result->output);
}
SKIP: {
    my $javapid = 0;
    if ($^O eq "cygwin") {
      my @pstree = `pstree -apn`;
      map {/^.+,(\d+)/ && kill 'KILL', $1; printf STDERR "i killed %d\n", $1; }  grep /Dgreenmail.setup.test.all/, @pstree;
    }
}

