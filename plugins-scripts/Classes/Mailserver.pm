package Classes::Mailserver;
our @ISA = qw(Classes::Device);

use strict;

sub init {
  my $self = shift;
  if ($self->mode =~ /^server::connectiontime/) {
    $self->{connection_time} = $self->{tac} - $self->{tic};
  } elsif ($self->mode =~ /^mails::/) {
    $self->check_folder();
    return if $self->check_messages();
    $self->{num_all_mails} = scalar(@{$self->{mails}}) if ! exists $self->{num_all_mails};
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
  $self->dump()
      if $self->opts->verbose >= 2;
}

sub dump {
  my $self = shift;
  foreach (@{$self->{mails}}) {
    $_->dump();
  }
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
    $self->add_ok("have fun");
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
            $self->add_info(sprintf "age of the oldest mail is %d minutes", $self->{max_mail_age});
          } else {
            $self->add_critical("jetz klauns da de mails scho mittn ausm plugin aussa");
          }
          $self->add_message($self->check_thresholds($self->{max_mail_age}));
        } else {
          $self->add_ok(sprintf "age of the oldest mail is %d minutes", $self->{max_mail_age});
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
        if ($self->opts->select->{$key} =~ /^\d+$/) {
          $mail->age_minutes <= $self->opts->select->{$key};
        } else {
          my $date = new Date::Manip::Date;
          my $stderrvar;
          my $parseerr;
          *SAVEERR = *STDERR;
          open OUT ,'>',\$stderrvar;
          *STDERR = *OUT;
          eval {
            $parseerr = $date->parse($self->opts->select->{$key});
          };
          if ($@ || $stderrvar || $parseerr) {
            $self->add_unknown(sprintf "invalid date format \"%s\" (%s)",
                $self->opts->select->{$key}, $@ || $stderrvar || $parseerr);
          }
          *STDERR = *SAVEERR;
          $mail->received >= $date->printf("%s");
        }
      });
    } elsif (lc $key eq "older_than") {
      push(@filters, sub {
        my $self = shift;
        my $mail = shift;
        if ($self->opts->select->{$key} =~ /^\d+$/) {
          $mail->age_minutes < $self->opts->select->{$key};
        } else {
          my $date = new Date::Manip::Date;
          my $stderrvar;
          my $parseerr;
          *SAVEERR = *STDERR;
          open OUT ,'>',\$stderrvar;
          *STDERR = *OUT;
          eval {
            $parseerr = $date->parse($self->opts->select->{$key});
          };
          if ($@ || $stderrvar || $parseerr) {
            $self->add_unknown(sprintf "invalid date format \"%s\" (%s)", 
                $self->opts->select->{$key}, $@ || $stderrvar || $parseerr);
          }
          *STDERR = *SAVEERR;
          $mail->received < $date->printf("%s");
        }
      });
    } elsif (lc $key eq "has_attachments") {
      push(@filters, sub {
        my $self = shift;
        my $mail = shift;
        return $mail->num_attachments;
      });
    } elsif (lc $key eq "bigger_than") {
      push(@filters, sub {
        my $self = shift;
        my $mail = shift;
        my $size = $mail->size;
        $self->override_opt('units', 'MB') if ! $self->opts->units();
        if (lc $self->opts->units eq "kb") {
          $size /= 1024;
        } elsif (lc $self->opts->units eq "mb") {
          $size /= (1024 * 1024);
        } elsif (lc $self->opts->units eq "gb") {
          $size /= (1024 * 1024 * 1024);
        }
        return $size >= $self->opts->select->{$key};
      });
    } elsif (lc $key eq "attachments") {
      push(@filters, sub {
        my $self = shift;
        my $mail = shift;
        my $filter_raw = $self->opts->select->{$key};
        my $check_content_type = index($filter_raw, "/") != -1;
        my $extensions = [];
        if (!$check_content_type) {
          while ($filter_raw =~ /(\*(\.[a-z]+);?)/g) {
            push @$extensions, $2; # ".xls"
          }
        }

        if ($check_content_type) {
          # "application/pdf"
          grep { my $attachment = $_;
            grep {
              $self->filter_namex($_, $attachment->content_type) ;
            } map { 
              if ($self->opts->regexp) {
                s/\//\\\//g;
              }
              $_;
            } map {
              /^\s*(.*?)\s*$/; $1; 
            } split(/,/, $filter_raw);
          } @{$mail->{attachments}};
        }
        else {
          # "*.xls;*.xlsx"
          grep { my $attachment = $_;
            grep {
              substr($attachment->filename // '', -(length($_))) eq $_;
            } @$extensions
          } @{$mail->{attachments}};
        }

      });
    } elsif (lc $key eq "seen") {
      push(@filters, sub {
        my $self = shift;
        my $mail = shift;
        return 1 if $self->opts->select->{$key} eq "no" && ! $mail->{seen};
        return 1 if $self->opts->select->{$key} eq "yes" &&  $mail->{seen};
        return 0;
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

