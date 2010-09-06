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

$Carp::Verbose = 1;
my $confFile = File::Spec->catfile(File::HomeDir->my_home, ".vanPortGamers.conf");
my %conf;
if (-e $confFile)
{
    read_config $confFile => %conf;
}

# apt-get install libconfig-std-perl libnet-twitter-lite-perl libfile-homedir-perl
my $nt = Net::Twitter::Lite->new(
    username => $conf{default}{username},
    password => $conf{default}{password},
);

eval {
    my $limit = $nt->rate_limit_status();
    exit unless $limit->{remaining_hits};
};
warn ("Error getting limit: $@") if $@;
#print "We've got $limit->{remaining_hits} API calls left\n"

my $didChange = 0;

foreach my $term ('#vpgamers')#, '#vanpgg')
{
    $conf{$term}{lastSeenId} ||= 0;
    my $status;
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

