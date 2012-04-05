#!/usr/bin/perl 
use strict;
use warnings;

use Net::Twitter;
use Data::Dumper;
use File::HomeDir;
use File::Spec;
use Config::Std;
use Carp;
use Getopt::Std;
use Scalar::Util qw(blessed);

my %opts;
$opts{v} = 1 if $ENV{VIM};
getopts('vc:', \%opts);

$Carp::Verbose = 1;
my $confFile = $opts{'c'} || File::Spec->catfile(File::HomeDir->my_home, ".vanPortGamers.conf");
my %conf;
if (-e $confFile)
{
    read_config $confFile => %conf;
}

# apt-get install libconfig-std-perl libnet-twitter-lite-perl libfile-homedir-perl libnet-oauth-perl
my $nt;
eval {
    $nt = Net::Twitter->new(
        traits              => [qw/OAuth API::REST API::Search/],
        consumer_key        => $conf{default}{consumer_key},
        consumer_secret     => $conf{default}{consumer_secret},
        access_token        => $conf{default}{access_token},
        access_token_secret => $conf{default}{access_token_secret},
        source              => 'api',
    );
};
if ( my $err = $@ ) {
    die $@ unless blessed $err && $err->isa('Net::Twitter::Error');

    warn "HTTP Response Code: ", $err->code, "\n",
    "HTTP Message......: ", $err->message, "\n",
    "Twitter error.....: ", $err->error, "\n";
}

my $limit = $nt->rate_limit_status();
unless ($limit->{remaining_hits})
{
    die("no more api allowed\n");
}

my $didChange = 0;

foreach my $term (grep { /^\#/ } keys %conf)
{
    $conf{$term}{lastSeenId} ||= 0;
    eval {
        my $status;
        warn "Searching for '$term'\n" if $opts{v};
        my $r = $nt->search({q=>$term, since_id=> $conf{$term}{lastSeenId}});
        #my $r = $nt->search({q=>$term});
        for $status ( @{$r->{results}} ) 
        {
            next unless $status;
            next unless $status->{id} > $conf{$term}{lastSeenId};
            # If its my tweet, ignore it
            if ($status->{'from_user'} ne $conf{default}{username})
            {
                $nt->retweet($status->{id});
            }
            $conf{$term}{lastSeenId} = $status->{id};
            $didChange = 1;
        }
    };
    if ( my $err = $@ ) 
    {
        die $@ unless blessed $err && $err->isa('Net::Twitter::Error');

        warn "Searching for $term $conf{$term}{lastSeenId}\n",
        "HTTP Response Code: ", $err->code, "\n",
        "HTTP Message......: ", $err->message, "\n",
        "Twitter error.....: ", $err->error, "\n";
    }
}

if (0)
{
    my $r = $nt->direct_messages();
    for my $dm ( @$r ) {
        $nt->new_direct_message({user=>"halkeye", text=>"\@$dm->{sender_screen_name} - $dm->{text}"});
        $nt->destroy_direct_message($dm->{id});
    }
    warn("Error handling dms: $@") if $@;
}

if ($didChange)
{
    write_config %conf, $confFile;
}

1;
