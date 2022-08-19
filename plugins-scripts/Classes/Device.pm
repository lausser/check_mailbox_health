package Classes::Device;
our @ISA = qw(Monitoring::GLPlugin);
use strict;


sub classify {
  my $self = shift;
#  if ($self->opts->config) {
#    # require config and force_opts
#  }
  if ($self->opts->protocol eq 'imap') {
    bless $self, "Classes::IMAP";
    if (! $self->opts->hostname && ! $self->opts->username && ! $self->opts->password) {
      $self->add_unknown('Please specify hostname, username and password');
    }
    if (! eval "require Net::IMAP::Simple") {
      $self->add_critical('could not load perl module Net::IMAP::Simple');
    }
    if (! eval "require List::MoreUtils") {
      $self->add_critical('could not load perl module List::MoreUtils');
    }
  } elsif ($self->opts->protocol eq 'o365') {
    bless $self, "Classes::O365";
    if (! $self->opts->hostname && ! $self->opts->username && ! $self->opts->password) {
      $self->add_unknown('Please specify hostname, username and password');
    }
    if (! eval "require Net::IMAP::Simple") {
      $self->add_critical('could not load perl module Net::IMAP::Simple');
    }
    if (! eval "require LWP::UserAgent") {
      $self->add_critical('could not load perl module LWP::UserAgent');
    }
    if (! eval "require HTTP::Request") {
      $self->add_critical('could not load perl module HTTP::Request');
    }
  }
  if (! eval "require Email::MIME") {
    $self->add_critical('could not load perl module Email::MIME');
  } else {
    my $x = $Email::MIME::ContentType::STRICT_PARAMS;
    $Email::MIME::ContentType::STRICT_PARAMS = 0;
  }
  if (! $self->check_messages()) {
    $self->check_connect_and_version();
    if (! $self->check_messages()) {
      if ($self->opts->mode =~ /^my-/) {
        $self->load_my_extension();
      }
    }
  }
}

