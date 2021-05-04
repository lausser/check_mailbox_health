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
  if (! $self->opts->port && ! $self->opts->ssl) {
    $self->override_opt('port', 143);
  } elsif (! $self->opts->port) {
    $self->override_opt('port', 993);
  } else {
    $self->override_opt('hostname', $self->opts->hostname.':'.$self->opts->port);
  }
  my %options = ();
  $options{timeout} = $self->opts->timeout;
  $options{use_ssl} = 1 if $self->opts->ssl;
  $options{debug} = $self->opts->verbose if $self->opts->verbose > 10;
  $self->{session} = Net::IMAP::Simple->new(
      $self->opts->hostname, %options);
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

sub check_folder {
  my $self = shift;
  $self->{mails} = [];
  my $msgnums = $self->{session}->select($self->opts->folder);
  $msgnums = 0 if (! defined $msgnums || $msgnums eq "0E0");
  $self->{num_all_mails} = $msgnums;
  $self->debug(sprintf 'there are %d messages in folder %s',
      $msgnums, $self->opts->folder);
  if ($self->{session}->errstr()) {
    $self->debug(sprintf 'error is: %s', $self->{session}->errstr());
    $self->add_unknown($self->{session}->errstr());
    return;
  }
  return;
}

sub read_mails {
  my $self = shift;
}

sub filter_mails {
  my ($self) = @_;
  # --select subject='Anlieferung.+aktuell' --select attachments=text/pdf
  my @filters = ();
  if ($self->opts->select) {
    # Vorselektieren, aber mit Fingerspitzengefuehl, also auf newer/older_than
    # einen Tag zur Sicherheit draufzaehlen.
    # Das beschleunigt die Abfrage ungemein, entlastet das Monitoring
    # und laesst den IMAP-Server die Arbeit tun.
    foreach my $key (keys %{$self->opts->select}) {
      if (lc $key eq "newer_than" || lc $key eq "older_than") {
        my $when = $self->opts->select->{$key};
        if ($when =~ /^\d+$/) {
          if (lc $key eq "newer_than") {
            $when = sprintf "%d minutes ago", $when;
          } else {
            $when = sprintf "in %d minutes", $when;
          }
        }
        my $date = new Date::Manip::Date;
        my $stderrvar;
        my $parseerr;
        *SAVEERR = *STDERR;
        open OUT ,'>',\$stderrvar;
        *STDERR = *OUT;
        eval {
          $parseerr = $date->parse($when);
          my $security = new Date::Manip::Delta;
          if (lc $key eq "newer_than") {
            $security->parse('1 day ago');
          } else {
            $security->parse('in 1 day');
          }
          $date = $date->calc($security);
        };
        if ($@ || $stderrvar || $parseerr) {
          $self->add_unknown(sprintf "invalid date format \"%s\" (%s)",
              $self->opts->select->{$key}, $@ || $stderrvar || $parseerr);
        } else {
          if (lc $key eq "newer_than") {
            push(@filters, sprintf 'SINCE %s', $date->printf("%d-%b-%Y"));
          } else {
            push(@filters, sprintf 'BEFORE %s', $date->printf("%d-%b-%Y"));
          }
        }
        *STDERR = *SAVEERR;
      } elsif (lc $key eq "bigger_than") {
        my $size = $self->opts->select->{$key};
        $self->override_opt('units', 'MB') if ! $self->opts->units();
        if (lc $self->opts->units eq "kb") {
          $size *= 1024;
        } elsif (lc $self->opts->units eq "mb") {
          $size *= (1024 * 1024);
        } elsif (lc $self->opts->units eq "gb") {
          $size *= (1024 * 1024 * 1024);
        }
        push(@filters, sprintf 'LARGER %d', $size * 0.8);
      } elsif (lc $key eq "seen") {
        push(@filters, 'SEEN') if $self->opts->select->{$key} eq "yes";
        push(@filters, 'UNSEEN') if $self->opts->select->{$key} eq "no";
      }
    }
  }
  my @msgids = ();
  $self->getcapabilities();
  if (@filters and $self->can_sort()) {
    @msgids = ($self->{session}->search(join(" ", @filters), "ARRIVAL"));
  } else {
    @msgids = (1..$self->{num_all_mails});
  }
  foreach my $msgnum (@msgids) {
    my $seen = $self->{session}->seen($msgnum);
    my $mail = $self->{session}->get($msgnum);
    next if ! defined $mail; # notbremse, evt. wurde gerade eine mail geloescht
    $self->{session}->unsee($msgnum) if ! $seen;
    my $mailsig = "-new-";
    eval {
      my $mail = Classes::MAIL->new(join("", @{$mail}));
      $mail->{seen} = $seen;
      push(@{$self->{mails}}, $mail) if ! $mail->is_spam;
    };
    if ($@) {
      $self->add_unknown($@);
    }
  }
  $self->SUPER::filter_mails();
}
 
sub getcapabilities {
  my ($self) = @_;
  $self->{capabilities} = [];
  eval {
    my @lines;
    $self->{session}->_process_cmd(
        cmd => [ "CAPABILITY" ],
        final => sub {
            my $cap_line = join( ' ', @lines);
            my @caps = split(/\s+/, $cap_line);
            if ($caps[0] eq '*') { shift @caps; }
            $self->{capabilities} = \@caps;
        },
        process => sub {
            push @lines, @_;
        },
    );
  };
  $self->debug(sprintf "capabilities: %s", join(",", @{$self->{capabilities}}));
}

sub can_sort {
  my ($self) = @_;
  return (grep /^SORT/, @{$self->{capabilities}}) ? 1 : 0;
}
