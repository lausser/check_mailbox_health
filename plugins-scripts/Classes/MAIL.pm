package Classes::MAIL;
our @ISA = qw(GLPlugin::TableItem);
use strict;
use List::MoreUtils qw(natatime);
use Date::Manip;
our $AUTOLOAD;

sub new {
  my $class = shift;
  my $raw_text = shift;
  my $self = {
    attachments => [],
  };
  bless $self, $class;
  my $stderrvar;
  *SAVEERR = *STDERR;
  open OUT ,'>',\$stderrvar;
  *STDERR = *OUT;
  my $parsed = undef;
  eval {
    $parsed = Email::MIME->new($raw_text);
  };
  if ($@) {
    $self->add_unknown(sprintf "scheise mail %s", $raw_text);
  }
  *STDERR = *SAVEERR;
  if ($stderrvar) {
    if ($stderrvar =~ /Illegal Content-Type parameter/) {
    } elsif ($stderrvar =~ /Use of uninitialized value in lc.*Header.pm/) {
    } else {
      printf "stderrvar %s\n", $stderrvar;
      printf "stderrvar %s\n----------------------------------\n", $raw_text;
    }
  }
  @{$self->{attachments}} = $parsed->subparts;
  my $header_values = {};
  my @header_names = $parsed->header_pairs;
  my $iter = natatime(2, @header_names);
  while (my @vals = $iter->()) {
    next if $vals[0] eq "Received" && exists $header_values->{received}; # an oberster Stelle ist der letzte Hop
    $header_values->{lc $vals[0]} = $vals[1]; # weil manchmal Message-ID, manchmal Message-Id
  }
  my %save_header_values = %{$header_values};
  eval {
  my $stderrvar;
  *SAVEERR = *STDERR;
  open OUT ,'>',\$stderrvar;
  *STDERR = *OUT;
    my $date = new Date::Manip::Date;
    if (! exists $header_values->{received}) {
      # vom lokalen Notes versandt
      my $err = $date->parse($header_values->{date});
      $header_values->{received} = $date->printf("%s");
      #$header_values->{received} = $date->printf("%Y/%m/%d %H:%M:%S");
    } else {
      $header_values->{received} =~ s/.*;//;
      my $err = $date->parse($header_values->{received});
      $header_values->{received} = $date->printf("%s");
      #$header_values->{received} = $date->printf("%Y/%m/%d %H:%M:%S");
    }
  *STDERR = *SAVEERR;
  };
  if ($@ || $stderrvar) {
    if (! $header_values->{received} && exists $header_values->{'x-olkeid'}) {
      $header_values->{subject} = '_check_mailbox_health_SPAM_';
    } elsif ($stderrvar =~ /Illegal Content-Type parameter/) {
      # z.b.
      # Illegal Content-Type parameter ; name=stammtisch.ics at /usr/share/perl5/Email/MIME.pm line 34
      # bei
      # Content-Type: text/calendar;method=PUBLISH;charset=UTF-8;; name=stammtisch.ics
      # Content-Disposition: inline,filename=stammtisch.ics; filename=stammtisch.ics
      # das raeumt dann die content_type-Methode auf
    } elsif ($stderrvar =~ /Use of uninitialized value in lc at .*Header\.pm/) {
    } else {
    printf STDERR "1norecieved %s\n%s\n", $stderrvar, Data::Dumper::Dumper(\%save_header_values);
    printf STDERR "2norecieved %s\n%s\n", $stderrvar, Data::Dumper::Dumper($header_values);
    printf STDERR "3norecieved %s\n%s\n", $stderrvar, $raw_text;
    printf "--------------------------------------------------------------------------------\n\n";
      $self->add_unknown(sprintf "date error in %s from %s",
          $header_values->{'message-id'}, $header_values->{from});
    }
  }
  %{$self->{header_values}} = %{$header_values};
  $self->{body} = $parsed->body;
  foreach (@{$self->{attachments}}) {
    bless $_, "Classes::Attachment";
  }
  return $self;
}

sub is_spam {
  my $self = shift;
  return $self->subject eq "_check_mailbox_health_SPAM_" ? 1 : 0;
}

sub signature {
  my $self = shift;
  return sprintf "%s %s %s\n%s\n", scalar localtime $self->{header_values}->{received}, $self->{header_values}->{from}, $self->{header_values}->{subject}, join("\n", map { "  ".$_->content_type(); } @{$self->{attachments}});
}

sub age_minutes {
  my $self = shift;
if (! defined $self->{header_values}->{received}) {
    printf STDERR "rootz %s %s\n", $self->is_spam ? "spaschpff" : "nox", Data::Dumper::Dumper($self->{header_values});
}
  return (time - $self->{header_values}->{received}) / 60;
}

sub received {
  my $self = shift;
  return $self->{header_values}->{received};
}

sub from {
  my $self = shift;
  return $self->{header_values}->{from};
}

sub subject {
  my $self = shift;
  return $self->{header_values}->{subject} || "";
}

sub body {
  my $self = shift;
  return $self->{body} || "";
}

sub num_attachments {
  my $self = shift;
  return scalar(@{$self->{attachments}});
}

sub attachments {
  my $self = shift;
  return @{$self->{attachments}};
}


sub iAUTOLOAD {
  my $self = shift;
  #$self->debug("AUTOLOAD %s\n", $AUTOLOAD)
  #      if $self->opts->verbose >= 2;
  return if ($AUTOLOAD =~ /DESTROY/);
  if ($AUTOLOAD =~ /^.*::(date|from|to|subject|received|message\-id)$/) {
    return $self->{header_values}->{$1};
  } else {
  #  $self->debug("AUTOLOAD: class %s has no method %s\n",
  #      ref($self), $AUTOLOAD);
  }
}

package Classes::Attachment;
our @ISA = qw(Email::MIME GLPlugin::TableItem);
use strict;

sub new {
  my $class = shift;
  my $raw_text = shift;
  my $self = {};
  bless $self, $class;
  if ($self->content_type !~ /^text/) {
    $self->body_set("_binaerer_schrott_");
  }
  return $self;
}

sub content_type {
  my $self = shift;
  my $content_type = "text/plain";
  if (! defined $self->SUPER::content_type) {
    if (exists $self->{ct} && exists $self->{ct}->{type} && exists $self->{ct}->{subtype}) {
      $content_type = $self->{ct}->{type}."/".$self->{ct}->{subtype};
    } else {
      $content_type = "text/plain";
    }
  } else {
    $content_type = $self->SUPER::content_type;
    $content_type =~ s/;.*//g;
  }
  return $content_type
}

