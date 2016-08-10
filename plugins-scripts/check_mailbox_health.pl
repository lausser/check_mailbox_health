#! /usr/bin/perl

use strict;

eval {
  if ( ! grep /AUTOLOAD/, keys %Monitoring::GLPlugin::) {
    require Monitoring::GLPlugin;
    require Monitoring::GLPlugin::SNMP;
  }
};
if ($@) {
  printf "UNKNOWN - module Monitoring::GLPlugin was not found. Either build a standalone version of this plugin or set PERL5LIB\n";
  printf "%s\n", $@;
  exit 3;
}

my $plugin = Classes::Device->new(
    shortname => '',
    usage => '%s [-v] [-t <timeout>] '.
        '--hostname=<mailserver hostname> [--port <port>] '.
        '--username=<username> --password=<password> '.
        '--mode=<mode> '.
        '...',
    version => '$Revision: #PACKAGE_VERSION# $',
    blurb => 'This plugin checks mailboxes ',
    url => 'http://labs.consol.de/nagios/check_mailbox_health',
    timeout => 60,
);
$plugin->add_mode(
    internal => 'server::connectiontime',
    spec => 'connection-time',
    alias => undef,
    help => 'Time to connect to the server',
);
$plugin->add_mode(
    internal => 'mails::age',
    spec => 'mail-age',
    alias => undef,
    help => 'alert if mails are older than n minutes',
);
$plugin->add_mode(
    internal => 'mails::count',
    spec => 'count-mails',
    alias => undef,
    help => 'count mails which satisfy certain criteria',
);
$plugin->add_mode(
    internal => 'mails::list',
    spec => 'list-mails',
    alias => undef,
    help => 'convenience function which lists all mails',
);
$plugin->add_default_args();
$plugin->add_arg(
    spec => 'hostname=s',
    help => "--hostname
   the mail server",
    required => 0,
);
$plugin->add_arg(
    spec => 'username=s',
    help => "--username
   the mailbox user",
    required => 0,
);
$plugin->add_arg(
    spec => 'password=s',
    help => "--password
   the mailbox user's password",
    required => 0,
);
$plugin->add_arg(
    spec => 'folder=s',
    default => 'INBOX',
    help => "--folder
   the name of a non-default folder",
    required => 0,
);
$plugin->add_arg(
    spec => 'port=i',
    help => "--port
   the mailserver's port",
    required => 0,
);
$plugin->add_arg(
    spec => 'ssl',
    default => 0,
    help => "--ssl
",
    required => 0,
);
$plugin->add_arg(
    spec => 'protocol=s',
    default => 'imap',
    help => "--protocol
   The client protocol (imap)",
    required => 0,
);
$plugin->add_arg(
    spec => 'select=s%',
    help => "--select
   Only select mails with specific criteria
   e.g. --select subject='Anlieferung.+aktuell' --select attachments=text/pdf",
    required => 0,
);

$plugin->getopts();
$plugin->classify();
$plugin->validate_args();


if (! $plugin->check_messages()) {
  $plugin->init();
  if (! $plugin->check_messages()) {
    $plugin->add_ok($plugin->get_summary())
        if $plugin->get_summary();
    $plugin->add_ok($plugin->get_extendedinfo(" "))
        if $plugin->get_extendedinfo();
  }
} else {
#  $plugin->add_critical('wrong device');
}
my ($code, $message) = $plugin->opts->multiline ?
    $plugin->check_messages(join => "\n", join_all => ', ') :
    $plugin->check_messages(join => ', ', join_all => ', ');
$message .= sprintf "\n%s\n", $plugin->get_info("\n")
    if $plugin->opts->verbose >= 1;
#printf "%s\n", Data::Dumper::Dumper($plugin);
$plugin->nagios_exit($code, $message);


