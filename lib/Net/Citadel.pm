package Net::Citadel;

use strict;
use warnings;

require Exporter;
use base qw(Exporter);

use IO::Socket;
use Data::Dumper;

=pod

=head1 NAME

Net::Citadel - Citadel.org protocol coverage

=head1 SYNOPSIS

  use Net::Citadel;
  my $c = new Net::Citadel (host => 'citadel.example.org');
  $c->login ('Administrator', 'goodpassword');
  my @floors = $c->floors;

  eval {
     $c->assert_floor ('Level 6 (Management)');
  }; warn $@ if $@;

  $c->retract_floor ('Level 6 (Management)');

  $c->logout;

=head1 DESCRIPTION

Citadel is a "turnkey open-source solution for email and collaboration" (this is as far as marketing
can go :-). The main component is the I<citadel server>. To communicate with it you can use either
a web interface, or - if you have to automate things - with a protocol

   http://www.citadel.org/doku.php/documentation:appproto:start

This package tries to do a bit of abstraction (more could be) and handles some of the protocol
handling.  The basic idea is that the application using the package deals with Citadel's objects:
rooms, floors, users.

=head1 INTERFACE

=cut

use constant {
    CITADEL_PORT => 504
};

use constant {
    LISTING_FOLLOWS => 100,
    CIT_OK          => 200,
    MORE_DATA       => 300,
    SEND_LISTING    => 400,
    ERROR           => 500,
    BINARY_FOLLOWS  => 600,
    SEND_BINARY     => 700,
    START_CHAT_MODE => 800
};

use constant {
    PUBLIC             => 0,
    PRIVATE            => 1,
    PRIVATE_PASSWORD   => 2,
    PRIVATE_INVITATION => 3,
    PERSONAL           => 4
    };

=pod

=head2 Constructor

The constructor creates a handle to the citadel server (and creates the TCP connection). It expects
the folloing named parameters:

=over

=item I<host> (C<localhost>)

The hostname (or IP address) where the citadel server is running on. Defaults to C<localhost>.

=item I<port> (C<CITADEL_PORT>)

The port there.

=back

The constructor will die if no connection can be established.

=cut

sub new {
    my $class = shift;
    my $self = bless { @_ }, $class;
    $self->{host} ||= 'localhost';
    $self->{port} ||= CITADEL_PORT;
    use IO::Socket::INET;
    $self->{socket} = IO::Socket::INET->new (PeerAddr => $self->{host},
					     PeerPort => $self->{port},
					     Proto    => 'tcp',
					     Type     => SOCK_STREAM) or die "cannot connect to $self->{host}:$self->{port} ($@)";
    my $s = $self->{socket}; <$s>; # consume banner
    return $self;
}

=pod

=head2 Methods

=head3 Authentication

=over

=item I<login>

I<$c>->login (I<$user>, I<$pwd>)

Logs in this user, or will die if that fails.

=cut

sub login {
    my $self = shift;
    my $user = shift;
    my $pwd  = shift;
    my $s    = $self->{socket};

    print $s "USER $user\n";
    <$s> =~ /(\d).. (.*)/ and ($1 == 3 or die $2);

    print $s "PASS $pwd\n";
    <$s> =~ /(\d).. (.*)/ and ($1 == 2 or die $2);
}

=pod

=item I<logout>

I<$c>->logout

Well, logs out the current user.

=cut

sub logout {
    my $self = shift;
    my $s    = $self->{socket};

    print $s "LOUT\n";
    <$s> =~ /(\d).. (.*)/ and ($1 == 2 or die $2);
}

=pod

=back

=head3 Floors

=over

=item I<floors>

I<@floors> = I<$c>->floors

Retrieves a list (ARRAY) of known floors. Each entry is a hash reference with the name, the number
of rooms in that floor and the index as ID. The index within the array is also the ID of the floor.

=cut

sub floors {
    my $self = shift;
    my $s    = $self->{socket};

    print $s "LFLR\n";
    <$s> =~ /(\d).. (.*)/ and ($1 == 1 or die $2);

    my @floors;
    while (($_ = <$s>) !~ /^000/) {
#warn "_floors $_";
	my ($nr, $name, $nr_rooms) = /(.+)\|(.+)\|(.+)/;
	push @floors, { id => $nr, name => $name, nr_rooms => $nr_rooms };
    }
    return @floors;
#100 Known floors:
#0|Main Floor|33
#1|SecondLevel|1
#000
}

=pod

=item I<assert_floor>

I<$c>->assert_floor (I<$floor_name>)

Creates the floor with the name provided, or if it exists already simply returns. This only dies if
there are insufficient privileges.

=cut

sub assert_floor {
    my $self = shift;
    my $name = shift;

    my $s    = $self->{socket};
    print $s "CFLR $name|1\n";  # we really want to create it
    <$s> =~ /(\d).. (.*)/ and ($1 == 1 or $1 == 2 or $2 =~ /already exists/ or die $2);
#CFLR XXX|1
#550 This command requires Aide access.
}

=pod

=item I<retract_floor>

I<$c>->retract_floor (I<$floor_name>)

Retracts a floor with this name. Dies if that fails because of insufficient privileges. Does
not die if the floor did not exist.

B<NOTE>: Citadel server (v7.20) seems to have the bug that you cannot
delete an empty floor without restarting the server. Not much I can do
here about that.

=cut

sub retract_floor {
    my $self = shift;
    my $name = shift;

    my @floors = $self->floors;
    for (my $i = 0; $i <= $#floors; $i++) {
	if ($floors[$i]->{name} eq $name) {
	    my $s    = $self->{socket};
	    print $s "KFLR $i|1\n";  # we really want to delete it
	    <$s> =~ /(\d).. (.*)/ and ($1 == 2 or $2 =~ /not in use/ or die $2);
	    return;
	}
    }
}

=pod

=item I<rooms>

I<@rooms> = I<$c>->rooms (I<$floor_name>)

Retrieves the rooms on that given floor.

=cut

sub rooms {
    my $self = shift;
    my $name = shift;

    my $s    = $self->{socket};

    my @floors  = $self->floors;
#warn "looking for $name rooms ". Dumper \@floors;
    my ($floor) = grep { $_->{name} eq $name } @floors or die "no floor '$name' known";
#warn "found floor: ".Dumper $floor;

    print $s "LKRA ".$floor->{id}."\n";
    <$s> =~ /(\d).. (.*)/ and ($1 == 1 or die $2);
    my @rooms;
    while (($_ = <$s>) !~ /^000/) {
#warn "processing $_";
 	my %room;
	@room{ ('name', 'qr_flags', 'qr2_flags', 'floor', 'order', 'ua_flags', 'view', 'default', 'last_mod') } = split /\|/, $_;
 	push @rooms, \%room;
     }
     return @rooms;
#LKRA
#100 Known rooms:
#Calendar|16390|0|0|0|230|3|3|1191241353|
#Contacts|16390|0|0|0|230|2|2|1191241353|
#..
#ramsti|2|1|64|0|230|0|0|1191241691|
#000
}

=pod

=back

=head3 Rooms

=over

=item I<assert_room>

I<$c>->assert_room (I<$floor_name>, I<$room_name>, [ I<$room_attributes> ])

Creates the room on the given floor. If the room already exists there, nothing
else happens. If the floor does not exist, it will complain.

The optional room attributes are provided as hash with the following fields

=over

=item C<access> (default: C<PUBLIC>)

One of the constants C<PUBLIC>, C<PRIVATE>, C<PRIVATE_PASSWORD>, C<PRIVATE_INVITATION> or
C<PERSONAL>.

=item C<password> (default: empty)

=item C<default_view> (default: empty)

=back

=cut

sub assert_room {
    my $self    = shift;
    my $fname   = shift;
    my @floors  = $self->floors;
    my ($floor) = grep { $_->{name} eq $fname } @floors or die "no floor '$fname' known";

    my $name  = shift;
    my $attrs = shift;
    $attrs->{access}       ||= PUBLIC;
    $attrs->{password}     ||= '';
    $attrs->{default_view} ||= '';

    my $s    = $self->{socket};

    print $s "CRE8 1|$name|".
	           $attrs->{access}.'|'.
		   $attrs->{password}.'|'.
		   $floor->{id}.'|'.
		   '|'.   # no idea what this is
		   $attrs->{default_view}.'|'.
		   "\n";
    <$s> =~ /(\d).. (.*)/ and ($1 == 2 or $2 =~ /already exists/ or die $2);
}

#CRE8 1|Bumsti|0||0|||
#200 'Bumsti' has been created.

=pod

=item I<retract_room>

I<$c>->retract_room (I<$floor_name>, I<$room_name>)

B<NOTE>: Not implemented yet.

=cut

sub retract_room {
    my $self = shift;
    my $name = shift;
    my $s    = $self->{socket};
    print $s "GOTO $name\n";
#GOTO Bumsti
    <$s> =~ /(\d).. (.*)/ and ($1 == 2 or die $2);
#200 Lobby|0|0|0|2|0|0|0|1|0|0|0|0|0|0|
    print $s "KILL 1\n";
#KILL 1
    <$s> =~ /(\d).. (.*)/ and ($1 == 2 or die $2);
#200 'Bumsti' deleted.
}

=pod

=back

=head3 Users

=over

=item I<create_user>

I<$c>->create_user (I<$username>, I<$password>)

Tries to create a user with name and password. Fails if this user already exists (or some other
reason).

=cut

sub create_user {
    my $self = shift;
    my $name = shift;
    my $pwd  = shift;
    my $s    = $self->{socket};
    print $s "CREU $name|$pwd\n";
#CREU RobertBarta|xxx
    <$s> =~ /(\d).. (.*)/ and ($1 == 2 or die $2);
#200 User 'RobertBarta' created and password set.
}

use constant {
    DELETED_USER   => 0,
    NEW_USER       => 1,
    PROBLEM_USER   => 2,
    LOCAL_USER     => 3,
    NETWORK_USER   => 4,
    PREFERRED_USER => 5,
    AIDE           => 6
};

=pod

=item I<change_user>

I<$c>->change_user (I<$user_name>, I<$aspect> => I<$value>)

Changes certain aspects of a user. Currently understood aspects are

=over

=item C<password> (string)

=item C<access_level> (0..6, constants available)

=back

=cut

sub change_user {
    my $self = shift;
    my $name = shift;
    my %changes = @_;
    my $s    = $self->{socket};

    print $s "AGUP $name\n";
#AGUP RobertBarta
    <$s> =~ /(\d).. (.*)/ and ($1 == 2 or die $2);
#200 RobertBarta|ggg|10768|1|0|4|4|1191255938|0
    my %user;
    my @attrs = ('name', 'password', 'flags', 'times_called', 'messages_posted', 'access_level', 'user_number', 'timestamp', 'purge_time');
    @user{ @attrs } = split /\|/, $2;

    $user{password}     = $changes{password}     if $changes{password};
    $user{access_level} = $changes{access_level} if $changes{access_level};

    print $s "ASUP ".(join "|", @user{ @attrs })."\n";
    <$s> =~ /(\d).. (.*)/ and ($1 == 2 or die $2);
}

=pod

=item I<remove_user>

I<$c>->remove_user (I<$name>)

Removes the user (actually sets level to C<DELETED_USER>).

=cut

sub remove_user {
    my $self = shift;
    my $name = shift;

    my $s    = $self->{socket};

    print $s "AGUP $name\n";
#AGUP RobertBarta
    <$s> =~ /(\d).. (.*)/ and ($1 == 2 or die $2);
#200 RobertBarta|ggg|10768|1|0|4|4|1191255938|0
    my %user;
    my @attrs = ('name', 'password', 'flags', 'times_called', 'messages_posted', 'access_level', 'user_number', 'timestamp', 'purge_time');
    @user{ @attrs } = split /\|/, $2;

    $user{access_level} = DELETED_USER;

    print $s "ASUP ".(join "|", @user{ @attrs })."\n";
    <$s> =~ /(\d).. (.*)/ and ($1 == 2 or die $2);
}

=pod

=back

=head3 Miscellaneous

=over

=item I<echo>

I<$c>->echo

Tests the connection.

=cut

sub echo {
    my $self = shift;
    my $msg  = shift;
    my $s    = $self->{socket};

    print $s "ECHO $msg\n";
    die "message not echoed ($msg)" unless <$s> =~ /2.. $msg/;
}

=pod

=item I<time>

I<$t> = I<$c>->time

Gets the UNIX time from the server.

C<TODO>: timezone handling

=cut

sub time {
    my $self = shift;
    my $s    = $self->{socket};
    print $s "TIME\n";
    die "protocol: time failed" unless <$s> =~ /2.. (.*)\|(.*)\|(.*)/;  # not sure what the others are
    return $1;
}

=pod

=back

=head1 SEE ALSO

   http://www.citadel.org/doku.php/documentation:appproto:app_proto

=head1 AUTHOR

Robert Barta, E<lt>rho@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Robert Barta

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut

our $VERSION = '0.01';

1;

__END__
