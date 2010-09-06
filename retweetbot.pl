#!/usr/bin/perl 
#===============================================================================
#
#         FILE:  vanPortGamers-TwitBot.pl
#
#        USAGE:  ./vanPortGamers-TwitBot.pl 
#
#  DESCRIPTION:  
#
#      OPTIONS:  ---
# REQUIREMENTS:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Gavin Mogan (Gavin), <gavin@kodekoan.com>
#      COMPANY:  KodeKoan
#      VERSION:  1.0
#      CREATED:  08/20/2010 08:25:00 PM UTC
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;
use Net::Twitter::Lite;
use Data::Dumper;
use File::HomeDir;
use File::Spec;
use Config::Std;
use Carp;
use Getopt::Std;

my %opts;
getopts('vc:', \%opts);

$Carp::Verbose = 1;
my $confFile = $opts{'c'} || File::Spec->catfile(File::HomeDir->my_home, ".vanPortGamers.conf");
my %conf;
if (-e $confFile)
{
    read_config $confFile => %conf;
}

# apt-get install libconfig-std-perl libnet-twitter-lite-perl libfile-homedir-perl libnet-oauth-perl
my $nt = Net::Twitter::Lite->new(
        consumer_key    => $conf{default}{consumer_key},
        consumer_secret => $conf{default}{consumer_secret},
);

# You'll save the token and secret in cookie, config file or session database
if ($conf{default}{access_token} && $conf{default}{access_token_secret}) {
  $nt->access_token($conf{default}{access_token});
  $nt->access_token_secret($conf{default}{access_token_secret});
}

unless ( $nt->authorized ) {
  # The client is not yet authorized: Do it now
  print "Authorize this app at ", $nt->get_authorization_url, " and enter the PIN#\n";

  my $pin = <STDIN>; # wait for input
  chomp $pin;

  ($conf{default}{access_token}, $conf{default}{access_token_secret}) = $nt->request_access_token(verifier => $pin);
  write_config %conf, $confFile;
}

my $limit;
eval {
    $limit = $nt->rate_limit_status();
};
die ("Error getting limit: $@") if $@;
unless ($limit->{remaining_hits})
{
    print "no more api allowed\n";
    exit;
}
#print "We've got $limit->{remaining_hits} API calls left\n"

my $didChange = 0;

foreach my $term (grep { /^\#/ } keys %conf)
{
    $conf{$term}{lastSeenId} ||= 0;
    my $status;
    warn "Searching for $term\n" if $opts{v};
    my $r = $nt->search({
            since_id=>$conf{$term}{lastSeenId},
            q=>$term
    });
    eval {
        for $status ( @{$r->{results}} ) {
            next unless $status;
            next unless $status->{id} > $conf{$term}{lastSeenId};
            $nt->retweet($status->{id});
            $conf{$term}{lastSeenId} = $status->{id};
            $didChange = 1;
        }
    };
    if ($@)
    {
        warn ("Error handling $term: $@ -- " . Data::Dumper::Dumper($status));
        last;
    }
}

if (0)
{
    eval {
        my $r = $nt->direct_messages();
        for my $dm ( @$r ) {
            $nt->new_direct_message({user=>"halkeye", text=>"\@$dm->{sender_screen_name} - $dm->{text}"});
            $nt->destroy_direct_message($dm->{id});
        }
    };
    warn("Error handling dms: $@") if $@;
}

if ($didChange)
{
    write_config %conf, $confFile;
}

1;

