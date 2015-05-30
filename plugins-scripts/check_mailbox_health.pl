# /usr/bin/perl -w

use strict;
use File::Basename;


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
    plugin => basename($0),
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
    spec => 'mail-count',
    alias => undef,
    help => 'count mails which satisfy certain criteria',
);
$plugin->add_mode(
    internal => 'mails::list',
    spec => 'list-mails',
    alias => undef,
    help => 'convenience function which lists all mails',
);
$plugin->add_arg(
    spec => 'debug|d',
    help => "--debug
",
    required => 0,);
$plugin->add_arg(
    spec => 'hostname=s',
    help => "--hostname
   the database server",
    required => 0,);
$plugin->add_arg(
    spec => 'username=s',
    help => "--username
   the mailbox user",
    required => 0,);
$plugin->add_arg(
    spec => 'password=s',
    help => "--password
   the mailbox user's password",
    required => 0,);
$plugin->add_arg(
    spec => 'folder=s',
    default => 'INBOX',
    help => "--folder
   the name of a non-default folder",
    required => 0,);
$plugin->add_arg(
    spec => 'port=i',
    default => 143,
    help => "--port
   the mailserver's port",
    required => 0,);
$plugin->add_arg(
    spec => 'ssl',
    default => 0,
    help => "--ssl
",
    required => 0,);
$plugin->add_arg(
    spec => 'mode|m=s',
    help => "--mode
   the mode of the plugin. select one of the following keywords:",
    required => 1,);
$plugin->add_arg(
    spec => 'select=s%',
    help => "--select
   Only select mails with specific criteria
   e.g. --select subject='Anlieferung.+aktuell' --select attachments=text/pdf",
    required => 0,);
$plugin->add_arg(
    spec => 'name=s',
    help => "--name
   the name of the database etc depending on the mode",
    required => 0,);
$plugin->add_arg(
    spec => 'drecksptkdb=s',
    help => "--drecksptkdb
   This parameter must be used instead of --name, because Devel::ptkdb is stealing the latter from the command line",
    aliasfor => "name",
    required => 0,
);
$plugin->add_arg(
    spec => 'regexp',
    help => "--regexp
   if this parameter is used, name will be interpreted as a 
   regular expression",
    required => 0,);
$plugin->add_arg(
    spec => 'warning=s',
    help => "--warning
_tobedone_",
    required => 0,);
$plugin->add_arg(
    spec => 'critical=s',
    help => "--critical
_tobedone_",
    required => 0,);
$plugin->add_arg(
    spec => 'warningx=s%',
    help => '--warningx
   The extended warning thresholds
   e.g. --warningx db_msdb_free_pct=6: to override the threshold for a
   specific item ',
    required => 0,
);
$plugin->add_arg(
    spec => 'criticalx=s%',
    help => '--criticalx
   The extended critical thresholds',
    required => 0,
);
$plugin->add_arg(
    spec => 'environment|e=s%',
    help => "--environment
_tobedone_",
    required => 0,);
$plugin->add_arg(
    spec => 'negate=s%',
    help => "--negate
_tobedone_",
    required => 0,);
$plugin->add_arg(
    spec => 'protocol=s',
    default => 'imap',
    help => "--protocol
   The client protocol (imap)",
    required => 0,);
$plugin->add_arg(
    spec => 'with-mymodules-dyn-dir=s',
    help => "--with-mymodules-dyn-dir
_tobedone_",
    required => 0,);
$plugin->add_arg(
    spec => 'morphmessage=s%',
    help => '--morphmessage
   Modify the final output message',
    required => 0,
);
$plugin->add_arg(
    spec => 'multiline',
    help => '--multiline
   Multiline output',
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


