package Classes::O365;
our @ISA = qw(Classes::IMAP);

use strict;
use Time::HiRes;
use IO::File;
use File::Copy 'cp';
use MIME::Base64;
use JSON;
use Data::Dumper;


sub aquire_auth_token {
  # https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-client-creds-grant-flow
  # No, i will not help you setting up the azure environment.
  # You will have to bother your own admins. You can also ask Microsoft.
  my $self = shift;
  my $client_secret = $self->opts->password;
  my ($tenant_id, $client_id) = split("/", $self->opts->username);
  my $ua = LWP::UserAgent->new();
  $ua->agent(qq{Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:68.0) Gecko/20100101 Firefox/68.0});
  my $scope = "https://outlook.office365.com/.default";
  my $uri = "https://login.microsoftonline.com/".$tenant_id."/oauth2/v2.0/token";
  my $header = ['Content-Type' => 'application/x-www-form-urlencoded'];
  my $data =
      "client_id=$client_id".
      "&client_secret=$client_secret".
      "&scope=$scope".
      "&grant_type=client_credentials";
  my $r = HTTP::Request->new('POST', $uri, $header, $data);
  my $res = $ua->request($r);
  $self->debug(sprintf "token request is %s", Data::Dumper::Dumper($r));
  $self->debug(sprintf "token request uri is %s", $uri);
  my @token = ();
  eval {
    my $message = $res->decoded_content;
    my $fromjson = from_json($message);
    $self->debug(sprintf "token response is %s", Data::Dumper::Dumper($fromjson));
    @token = ($fromjson->{access_token}, time + $fromjson->{expires_in});
  };
  if ($@) {
    @token = (undef, undef);
  }
  return @token;
}

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

  {
    #
    # username = tenant_id/client_id/user@domain
    # password = client_secret
    # tokens aus dem cache holen (refresh und access)
    # pruefen, ob man sich mit dem _token einen xoauth2-token holen kann
    # falls nicht, den ganzen api-schlonz ausfuehren
    o warnings 'redefine';
    no warnings 'once';
    *Net::IMAP::Simple::login = sub {
      my ($self, $o365, $username, $password) = @_;
      my $client_secret = $password;
      my ($tenant_id, $client_id, $mailbox_user) = split("/", $username);
      # weil wir hier in classify() sind, ein fehlendes statefilesdir aber
      # erst im drauffolgenden validate_args() auf einen default gesetzt wird,
      # muss der code teilweise hierher vorgezogen werden.
      if ($o365->opts->can("statefilesdir") && ! $o365->opts->statefilesdir) {
        if ($^O =~ /MSWin/) {
          if (defined $ENV{TEMP}) {
            $o365->override_opt('statefilesdir',
                $ENV{TEMP}."/".$Monitoring::GLPlugin::plugin->{name});
          } elsif (defined $ENV{TMP}) {
            $o365->override_opt('statefilesdir',
                $ENV{TMP}."/".$Monitoring::GLPlugin::plugin->{name});
          } elsif (defined $ENV{windir}) {
            $o365->override_opt('statefilesdir',
                File::Spec->catfile($ENV{windir}, 'Temp')."/".$Monitoring::GLPlugin::plugin->{name});
          } else {
            $o365->override_opt('statefilesdir',
                "C:/".$Monitoring::GLPlugin::plugin->{name});
          }
        } elsif (exists $ENV{OMD_ROOT}) {
          $o365->override_opt('statefilesdir',
              $ENV{OMD_ROOT}."/var/tmp/".$Monitoring::GLPlugin::plugin->{name});
        } else {
          $o365->override_opt('statefilesdir',
              "/var/tmp/".$Monitoring::GLPlugin::plugin->{name});
        }
      }
      $Monitoring::GLPlugin::plugin->{statefilesdir} =
          $o365->opts->statefilesdir if $o365->opts->can("statefilesdir");
      $Monitoring::GLPlugin::mode = (
          map { $_->{internal} }
          grep {
             ($o365->opts->mode eq $_->{spec}) ||
             ( defined $_->{alias} && grep { $o365->opts->mode eq $_ } @{$_->{alias}})
          } @{$Monitoring::GLPlugin::plugin->{modes}}
      )[0];

      my $cache = $o365->load_state(name => "o365_tokens_".$client_id) || {
          auth_token => undef,
      };
      # eventuell validitaet des oauth_token/auth_token ermitteln
      if (! $cache->{auth_token} or $cache->{valid_until} < time - 600) {
        ($cache->{auth_token}, $cache->{valid_until}) = $o365->aquire_auth_token();
        $o365->save_state(name => "o365_tokens_".$client_id, save => {
            client_id => $client_id,
            tenant_id => $tenant_id,
            auth_token => $cache->{auth_token},
            valid_until => $cache->{valid_until},
        }) if $cache->{auth_token};
      }
      if (! $cache->{auth_token}) {
        #$o365->add_critical("unable to aquire a xoauth2 token");
        $self->{_errstr} = "unable to aquire a xoauth2 token";
        return undef;
      }
      my $auth_token = $cache->{auth_token};
      my $oauth_sign = sprintf "user=%s\x01auth=Bearer %s\x01\x01",
          $mailbox_user, $auth_token;
      $o365->debug(sprintf "SIGNING IN (%s)\n", $oauth_sign);
      $oauth_sign = encode_base64($oauth_sign, '');
      return $self->_process_cmd(
          cmd     => [ "AUTHENTICATE XOAUTH2" => qq[$oauth_sign] ],
          final   => sub { 1 },
          process => sub { },
      );
    };
  }

  $self->{session} = Net::IMAP::Simple->new(
      $self->opts->hostname, %options);
  #$self->{session}->starttls() if $self->opts->ssl;
  if (! $self->{session}) {
    $self->add_critical("imap server not available");
  } else {
    my $login = $self->{session}->login(
        $self, $self->opts->username, $self->opts->password);
    if (! $login) {
      $self->add_critical($self->{session}->errstr);
    }
  }
  $self->{tac} = time;
  if ($self->{tac} - $self->{tic} >= $self->opts->timeout) {
    $self->add_unknown("timeout");
  }
}

