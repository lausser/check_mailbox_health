package Classes::MAIL;
our @ISA = qw(Monitoring::GLPlugin::TableItem);
use strict;
use List::MoreUtils qw(natatime);
use Date::Manip;
use Encode qw(decode);
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
      printf STDERR "stderrvar %s\n", $stderrvar;
      printf STDERR "stderrvar %s\n----------------------------------\n", $raw_text;
    }
    $stderrvar = undef;
  }
  my $header_values = {};
  my @header_names = $parsed->header_pairs;
  my $iter = natatime(2, @header_names);
  while (my @vals = $iter->()) {
    next if $vals[0] eq "Received" && exists $header_values->{received}; # an oberster Stelle ist der letzte Hop
    $header_values->{lc $vals[0]} = $vals[1]; # weil manchmal Message-ID, manchmal Message-Id
  }
  my %save_header_values = %{$header_values};
  *SAVEERR = *STDERR;
  open OUT ,'>',\$stderrvar;
  *STDERR = *OUT;
  eval {
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
  };
  *STDERR = *SAVEERR;
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
      printf STDERR "2norecieved %s\n%s\n", $stderrvar, Data::Dumper::Dumper($header_values);
      printf STDERR "3norecieved %s\n%s\n", $stderrvar, $raw_text;
      printf "--------------------------------------------------------------------------------\n\n";
      $self->add_unknown(sprintf "date error in %s from %s",
          $header_values->{'message-id'}, $header_values->{from});
    }
  }
  %{$self->{header_values}} = %{$header_values};
  $self->{body} = $parsed->body;
  #my @ attachments = $parsed->subparts;
  # flatten
  @{$self->{attachments}} = $parsed->subparts;
  foreach (@{$self->{attachments}}) {
    bless $_, "Classes::Attachment";
    $_->parse_attachments();
  }
  return $self;
}

sub is_spam {
  my $self = shift;
  return $self->subject eq "_check_mailbox_health_SPAM_" ? 1 : 0;
}

sub signature {
  my $self = shift;
  return sprintf "%s %s %s\n%s", scalar localtime $self->{header_values}->{received}, $self->{header_values}->{from}, $self->{header_values}->{subject}, join("\n", map { "  ".$_->content_type(); } @{$self->{attachments}});
}

sub dump {
  my $self = shift;
  printf "[MESSAGE_%s]\n", $self->message_id();
  printf "Received: %s\n", $self->received();
  printf "From: %s\n", $self->from();
  printf "Subject: %s\n", $self->subject();
#printf "Header %s\n", Data::Dumper::Dumper($self->{header_values});
my $sisi = $self->size();
printf "size %.2fKB final\n", $sisi / 1024;
  printf "\n";
}

sub age_minutes {
  my $self = shift;
  return (time - $self->{header_values}->{received}) / 60;
}

sub received {
  my $self = shift;
  return $self->{header_values}->{received};
}

sub message_id {
  my $self = shift;
  return $self->{header_values}->{'message-id'};
}

sub from {
  my $self = shift;
  return $self->{header_values}->{from};
}

sub subject {
  my $self = shift;
  return decode("MIME-Header", $self->{header_values}->{subject} || "");
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

sub size {
  my $self = shift;
  my $size = 0;
  $size += length($_->body());
  foreach (@{$self->{attachments}}) {
    my $asize = $_->size();
    $size += $asize;
  }
  return $size;
}

sub raw_size {
  my $self = shift;
  my $size = 0;
  $size += length($_->body_raw());
  foreach (@{$self->{attachments}}) {
    my $asize = $_->size();
    $size += $asize;
  }
  return $size;
}


package Classes::Attachment;
our @ISA = qw(Email::MIME Classes::MAIL Monitoring::GLPlugin::TableItem);
use strict;

sub new {
  my $class = shift;
  my $raw_text = shift;
  my $self = {
    attachments => [],
  };
  bless $self, $class;
  my $parsed = undef;
  eval {
    $parsed = Email::MIME->new($raw_text);
    
    @{$self->{attachments}} = $parsed->subparts;
    $self->{body} = $parsed->body;
  };
  if ($self->content_type !~ /^text/) {
    $self->body_set("_binaerer_schrott_");
  }
  return $self;
}

sub parse_attachments {
  my $self = shift;
  $self->{attachments} = [];
  my @attachments = $self->subparts();
  foreach (@attachments) {
    bless $_, "Classes::Attachment";
    $_->parse_attachments();
    push(@{$self->{attachments}}, $_);
  }
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

