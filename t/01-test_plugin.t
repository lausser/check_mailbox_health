#! /usr/bin/perl --warning -I ..
#
# check_mailbox_health
#
# NP_MAILBOX_SERVER=127.0.0.1 NP_MAILBOX_LOGIN_USERNAME=test NP_MAILBOX_LOGIN_PASSWORD='test%test' NP_MAILBOX_LOGIN_FOLDER="INBOX" PERL5LIB=$HOME/git/monitoring-plugins perl "-MExtUtils::Command::MM" "-e" "test_harness(1)" ../t/*.t

use strict;
use Test::More;
use NPTest;

use vars qw($tests);

plan skip_all => "check_mailbox_health not compiled" unless (-x "../plugins-scripts/check_mailbox_health" || -x "plugins-scripts/check_mailbox_health");
$ENV{PATH} = "../plugins-scripts:".$ENV{PATH} if -x "../plugins-scripts/check_mailbox_health";
$ENV{PATH} = "plugins-scripts:".$ENV{PATH} if -x "plugins-scripts/check_mailbox_health";
plan tests => 9;

my $result;
SKIP: {
	$result = NPTest->testCmd("check_mailbox_health -V");
	cmp_ok( $result->return_code, '==', 0, "expected result");
	like( $result->output, "/check_mailbox_health \\\$Revision: \\d+\\.\\d+/", "Expected message");

	$result = NPTest->testCmd("check_mailbox_health --help");
	cmp_ok( $result->return_code, '==', 0, "expected result");
        like( $result->output, "/connection-time/", "Expected message");
        like( $result->output, "/count-mails/", "Expected message");
        like( $result->output, "/mail-age/", "Expected message");
        like( $result->output, "/list-mails/", "Expected message");
}

SKIP: {
	$result = NPTest->testCmd("check_mailbox_health");
	cmp_ok( $result->return_code, "==", 3, "No mode defined" );
	like( $result->output, "/hostname.*username.*password/", "Correct error message");
}
