package Classes::Mailserver;
our @ISA = qw(Classes::Device);

use strict;

sub init {
  my $self = shift;
  if ($self->mode =~ /^server::connectiontime/) {
    $self->{connection_time} = $self->{tac} - $self->{tic};
  } elsif ($self->mode =~ /^mails::/) {
    $self->read_mails();
    $self->{num_all_mails} = scalar(@{$self->{mails}});
    $self->filter_mails();
    $self->{num_mails} = scalar(@{$self->{mails}});
    if ($self->mode =~ /^mails::age/) {
      $self->{max_mail_age} = 0;
      $self->{num_old_mails} = 0;
      map {
        $self->{max_mail_age} = $_->age_minutes if $_->age_minutes > $self->{max_mail_age};
      } @{$self->{mails}};
    }
  } else {
    $self->no_such_mode();
  }
  $self->check();
}

sub check {
  my $self = shift;
  if ($self->mode =~ /^server::connectiontime/) {
    $self->set_thresholds(warning => 1, critical => 5);
    $self->add_message($self->check_thresholds($self->{connection_time}),
         sprintf "%.2f seconds to connect as %s",
              $self->{connection_time}, $self->opts->username,);
    $self->add_perfdata(
        label => 'connection_time',
        value => $self->{connection_time},
    );
  } elsif ($self->mode =~ /^mails::list/) {
    foreach (@{$self->{mails}}) {
      printf "%s\n", $_->signature;
    }
  } elsif ($self->mode =~ /^mails::/) {
    if ($self->opts->select) {
      if (grep /attachments/, keys %{$self->opts->select}) {
        $self->add_info(sprintf "%d mails with attachments selected (%d total in mailbox)", $self->{num_mails}, $self->{num_all_mails});
      } else {
        $self->add_info(sprintf "%d mails selected (%d total in mailbox)", $self->{num_mails}, $self->{num_all_mails});
      }
    } else {
      $self->add_info(sprintf "%d mails in mailbox", $self->{num_mails});
    }
    if ($self->mode =~ /^mails::age/) {
      $self->add_ok(); # statusmeldung von da oben
      $self->set_thresholds(metric => 'max_age', warning => 30, critical => 60);
      if ($self->{num_mails}) {
        # alle selektierten mails, unter diesen wurde max_mail_age ermittelt
        if ($self->check_thresholds(metric => 'max_age', value => $self->{max_mail_age})) {
          # wenn die aelteste mail zu alt ist
          @{$self->{mails}} = sort {
            $a->age_minutes <=> $b->age_minutes;
          } @{$self->{mails}};
          @{$self->{mails}} = grep {
            # hole alle mails, die aelter als die thresholds sind
            $self->check_thresholds(metric => 'max_age', value => $_->age_minutes);
          } @{$self->{mails}};
          $self->{num_mails} = scalar(@{$self->{mails}});
          if (scalar(@{$self->{mails}})) {
            $self->add_message($self->check_thresholds(metric => 'max_age', value => $self->{max_mail_age}),
                sprintf "%d mails too old", $self->{num_mails});
            $self->add_info(sprintf "age of the oldest mail is %d minutes", @{$self->{mails}}[-1]->age_minutes);
          } else {
            $self->add_critical("jetz klauns da de mails scho mittn ausm plugin aussa");
          }
          $self->add_message($self->check_thresholds($self->{max_mail_age}));
        } else {
          $self->add_ok("no outdated mails");
        }
      } else {
        $self->add_ok("no mails");
      }
      $self->add_perfdata(
          label => 'mails',
          value => $self->{num_mails},
      );
      $self->add_perfdata(
          label => 'max_age',
          value => $self->{max_mail_age},
      );
    } elsif ($self->mode =~ /^mails::count/) {
      $self->set_thresholds(metric => 'mails', warning => 30, critical => 60);
      $self->add_message($self->check_thresholds(metric => 'mails', value => $self->{num_mails}));
      $self->add_perfdata(
          label => 'mails',
          value => $self->{num_mails},
      );
    }
  }
}

sub num_mails {
  my $self = shift;
  return scalar(@{$self->{mails}});
}

sub filter_mails {
  my $self = shift;
  # --select subject='Anlieferung.+aktuell' --select attachments=text/pdf
  return if ! $self->opts->select;
  my @filters = ();
  foreach my $key (keys %{$self->opts->select}) {
    if (lc $key eq "subject") {
      push(@filters, sub {
        my $self = shift;
        my $mail = shift;
        return $self->filter_namex($self->opts->select->{$key}, $mail->subject);
      });
    } elsif (lc $key eq "content") {
      push(@filters, sub {
        my $self = shift;
        my $mail = shift;
        if (! $mail->num_attachments) {
          return $self->filter_namex($self->opts->select->{$key}, $mail->body);
        } else {
          grep {
            $self->filter_namex($self->opts->select->{$key}, $_->body);
          } grep {
            $_->content_type =~ /^text/;
          } @{$mail->{attachments}};
        }
      });
    } elsif (lc $key eq "newer_than") {
      push(@filters, sub {
        my $self = shift;
        my $mail = shift;
        $mail->age_minutes <= $self->opts->select->{$key};
      });
    } elsif (lc $key eq "older_than") {
      push(@filters, sub {
        my $self = shift;
        my $mail = shift;
        $mail->age_minutes >= $self->opts->select->{$key};
      });
    } elsif (lc $key eq "has_attachments") {
      push(@filters, sub {
        my $self = shift;
        my $mail = shift;
        return $mail->num_attachments;
      });
    } elsif (lc $key eq "attachments") {
      push(@filters, sub {
        my $self = shift;
        my $mail = shift;
        grep { my $attachment = $_;
          grep {
            $self->filter_namex($_, $attachment->content_type) ;
          } map { 
            if ($self->opts->regexp) {
              s/\//\\\//g; $_;
            }
          } map {
            /^\s*(.*?)\s*$/; $1; 
          } split(/,/, $self->opts->select->{$key});
        } @{$mail->{attachments}};
      });
    }
  }
  my $filters = scalar(@filters);
  my $ok_filters = 0;
  @{$self->{mails}} = grep {
      $ok_filters = 0;
      foreach my $filter (@filters) {
        $ok_filters++ if
            $filter->($self, $_);
      }
      $ok_filters == $filters;
  } @{$self->{mails}};
}

