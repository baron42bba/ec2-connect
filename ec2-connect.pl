#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
use JSON::XS;
use YAML::Any;

my %params;

sub main {
    my $cachefilename = "$ENV{HOME}/.ec2connect";
    my $awscommand = "aws ";
    my $awsgetec2list;
    my @ec2list;
    my $instanceid;
    my ($config);
    my $configfile = "$ENV{HOME}/.ec2connect.config";

    my $result = GetOptions (
	"name|n=s"         => \$params{name},
	"nocache"          => \$params{nocache},
	"profile|p=s"      => \$params{profile},
	"region|r=s"       => \$params{region},
	"list|l"           => \$params{list},
	"help|h"           => \$params{help},
	"verbose|v"        => \$params{verbose},
	"man|m"            => \$params{man},
	"bash_completion"  => \$params{bash_completion}
       );

    if ( $params{bash_completion }) {
	bash_completion();
    }

    if ( $params{man} ) {
	pod2usage( -verbose => 2 );
    }

    if ( -s $configfile ) {
	$config = YAML::Any::LoadFile( "$configfile" ) || pod2usage( { -message => "cannot open $configfile", -verbose => 1, -exitval => 2} );
    }

    if ( ! ( $params{name} || $params{list} ) || $params{help} ) {
        pod2usage(1);
    }

    if ( ! $params{profile} && $params{name} ) {
	for my $i ( 0 .. $#{$config->{hosts}}) {
	    if ( $params{name} eq ${${$config->{hosts}}[$i]}{alias} ) {
		$params{profile} = ${${$config->{hosts}}[$i]}{profile};
		$params{region} = ${${$config->{hosts}}[$i]}{region};
		$params{name} = ${${$config->{hosts}}[$i]}{name};
	    }
	}
    }

    if ( ! $params{profile} ) {
	$cachefilename = $cachefilename . "_default";
    }
    else {
	$cachefilename = $cachefilename . "_" . $params{profile};
	$awscommand = $awscommand . " --profile $params{profile}";
    }

    if ( ! $params{region} ) {
	$cachefilename = $cachefilename . "_default.cache";
    }
    else {
	$cachefilename = $cachefilename . "_" . $params{region} . ".cache";
	$awscommand = $awscommand . " --region $params{region}";
    }

    if ( -s $cachefilename && -M $cachefilename < 1 && ! $params{nocache}) {
	open (FILE, "< $cachefilename") or die "can't open $cachefilename: $!";
	undef $/;		# read in file all at once;
	eval <FILE>;
	die "can't recreate cache from $cachefilename: $@" if $@;
	close FILE;
    }
    else {
	print STDERR "fetching list....\n";
	$awsgetec2list = $awscommand . " ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value[] | [0]]' --output json";
	my $result = `$awsgetec2list`;
	@ec2list = decode_json $result;
	$Data::Dumper::Purity = 1;
	open (FILE, "> $cachefilename") or die "can't open $cachefilename: $!";
	print FILE Data::Dumper->Dump([\@ec2list], ['*ec2list']);
	close FILE                       or die "can't close $cachefilename: $!";
    }

    if ( $params{list} ) {
	for my $i ( 0 .. $#{$ec2list[0]} ) {
	    if ( ${$ec2list[0]}[$i][1] ) {
		print ${$ec2list[0]}[$i][1] . "\n";
	    }
	}
	exit 0;
    }

    for my $i ( 0 .. $#{$ec2list[0]} ) {
	if ( ${$ec2list[0]}[$i][1] && ${$ec2list[0]}[$i][1] eq $params{name} ) {
	    $instanceid = ${$ec2list[0]}[$i][0];
	    last;
	}
    }

    if ( $instanceid ) {
	print STDERR ($params{profile} || "default" ) . " - " . ($params{region} || "default" ) . " - " . $instanceid . "\n";
	system("$awscommand ssm start-session --target ${instanceid}");
    }
}

sub bash_completion {
    print '
__ec2connect_completions()
{
  # COMPREPLY+=("--profile")
  # COMPREPLY+=("--region")
  # COMPREPLY+=("--name")

  local cur
  COMPREPLY=()   # Array variable storing the possible completions.
  cur=${COMP_WORDS[COMP_CWORD]}
  case "$cur" in
    -*)
    COMPREPLY=( $( compgen -W \'-n -p -r -l -h -m \
                               --name --profile --region --help \' -- $cur ) );;
  esac
  return 0
}

complete -F __ec2connect_completions ec2-connect
';
    exit 0;

}

main();

1;

__END__

=head1 NAME

ec2-connect.pl - connect to aws ec2 instances via ssm

=head1 DESCRIPTION

Just a wrapper around aws ssm command to connect by using Name tags.

=head1 SYNOPSIS

ec2-connect

Options:

  --help, -h for help
  --man, -m for man page
  --nocache ignore local cache file
  --profile, -p  aws profile to use
  --region, -r   aws region to use
  --list, -l     list Name tags
  --name, -n     instance name Tag to connect to.
  --bash_completion use as source <(ec2-connect --bash_completion) in bashrc.

=cut

=head1 AUTHOR

Andreas Gerler <baron@bundesbrandschatzamt.de>

=head1 LICENSE

This program is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
