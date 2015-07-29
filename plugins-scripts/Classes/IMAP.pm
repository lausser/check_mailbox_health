package Classes::IMAP;
our @ISA = qw(Classes::Mailserver);

use strict;
use Time::HiRes;
use IO::File;
use File::Copy 'cp';
use Data::Dumper;


sub check_connect_and_version {
  my $self = shift;
  $self->{tic} = time;
  $self->{session} = Net::IMAP::Simple->new(
      $self->opts->hostname, timeout => $self->opts->timeout,
      use_ssl => $self->opts->ssl ? 1 : 0,
      debug => $self->opts->verbose > 10 ? $self->opts->verbose : undef);
  #$self->{session}->starttls() if $self->opts->ssl;
  if (! $self->{session}) {
    $self->add_critical("imap server not available");
  } elsif (! $self->{session}->login(
      $self->opts->username, $self->opts->password)) {
    $self->add_critical("could not open imap3 mailbox (user or password probably wrong)");
  }
  $self->{tac} = time;
  if ($self->{tac} - $self->{tic} >= $self->opts->timeout) {
    $self->add_unknown("timeout");
  }
}

sub read_mails {
  my $self = shift;
  $self->{mails} = [];
  my $msgnums = $self->{session}->select($self->opts->folder);
  $msgnums = 0 if ($msgnums eq "0E0" || ! defined $msgnums);
  for (my $msgnum = 1; $msgnum <= $msgnums; $msgnum++) {
    my $mail = $self->{session}->get($msgnum);
    next if ! defined $mail; # notbremse, evt. wurde gerade eine mail geloescht
    my $mailsig = "-new-";
    eval {
      my $mail = Classes::MAIL->new(join("", @{$mail}));
      push(@{$self->{mails}}, $mail) if ! $mail->is_spam;
    };
    if ($@) {
      $self->add_unknown($@);
    }
  }
}

