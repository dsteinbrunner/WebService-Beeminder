package WebService::Beeminder;

# ABSTRACT: Access the Beeminder API

=head1 SYNOPSIS

    my $bee = WebService::Beeminder->new( token => $token );

    # I flossed my teeth today.
    $bee->add_datapoint( goal => 'floss', value => 1 );

    # When did I last take dance lessons?
    my $result = $bee->datapoints('dance');

    say "I danced $result->[-1]{timestamp} seconds from the epoch at " .
        $result->[-1]{comment};

=head1 DESCRIPTION

This is a I<thin-ish> wrapper around the Beeminder API.  All results are
exactly what's returned by the underlying API, with the JSON being
converted into Perl data structures.

You need a Beeminder API token to use this module.  The easiest way
to get a personal token is just to login to L<Beeminder|http://beeminder.com/>
and then go to L<https://www.beeminder.com/api/v1/auth_token.json>.
Copy'n'paste the token into your code (or a config file your code uses),
and you're good to go!

More information on tokens is available in the
L<Beeminder API documentation|http://beeminder.com/api>.

=head1 INSTALLATION

This module presently uses L<MooseX::Method::Signatures>.  If you're
not experienced in installing module dependencies, it's recommend you
use L<APP::cpanminus>, which doesn't require any special privileges
or software.

Perl v5.10.0 or later is required for this module.

=head1 SEE ALSO

=over

=item * 

L<The Beeminder API|http://beeminder.com/api>

=back

=for Pod::Coverage BUILD

=cut

use 5.010;
use strict;
use warnings;
use MooseX::Method::Signatures;
use Moose;
use WebService::Beeminder::Types qw(BeeBool);
use JSON::Any;
use LWP::UserAgent;
use Carp qw(croak);

# VERSION: Generated by DZP::OurPkg:Version

has 'token'   => (isa => 'Str', is => 'ro', required => 1);
has 'username'=> (isa => 'Str', is => 'ro', default => 'me');
has 'agent'   => (              is => 'rw'); # Must act like LWP::UserAgent
has 'dryrun'  => (isa => 'Bool',is => 'ro', default => 0);
has 'apibase' => (isa => 'Str', is => 'ro', default => 'https://www.beeminder.com/api/v1'); 

# Everything needs to be able to read/write JSON.
my $json = JSON::Any->new;

sub BUILD {
    my ($self) = @_;

    # Make sure we have a user-agent, if none provided.
    if (not $self->agent) {
        $self->agent(LWP::UserAgent->new(agent => "perl/$], WebService::Beeminder/" . $self->VERSION));
    }

    return;
}

=method user

    my $result = $bee->user();

Obtains information about the current user. This returns a user resource
(as defined by the Beeminder API), which looks like this:

    {
        username   => "alice",
        timezone   => "America/Los_Angeles",
        updated_at => 1343449880,                       
        goals      =>  ['gmailzero', 'weight']
    }

Note: Presently only basic parameters are returned, even though the
beeminder API supports additional filters.

=cut

# Get information about a user
# TODO: Accept optional parameters
method user(Str $user = "me") {

    # AFAIK, the $user here is irrelevant, since we can only query
    # the user we're logged in as. Still, we'll respect it, in
    # case that changes in the future.

    return $self->_get(['users',"$user.json"]);

}

=method datapoints

    my $results = $bee->datapoints($goal);

This method returns an array reference of data points for the given goal:

    [
        {  
            id         => 'abc123'
            timestamp  => 1234567890,
            value      => 1.1,
            comment    => "Frobnicated a widget",
            updated_at => 1234567890
        },
        {
            id         => 'abc124'
            timestamp  => 1234567891,
            value      => 1.2,
            comment    => "Straightened my doohickies",
            updated_at => 1234567891
        },
    ]

=cut

# Gets the datapoints for a goal
# DONE: 2011-11-25. This takes no parameters.
method datapoints(Str $goal) {
    return $self->_userget( ['goals', $goal, 'datapoints.json']);
}

=method add_datapoint

    my $point = $bee->add_datapoint(
        goal      => 'floss',
        timestamp => time(),        # Optional, defaults to now
        value     => 1,
        comment   => 'Floss every tooth for great justice!',
        sendmail  => 0,             # Optional, defaults to false
    );

Adds a data-point to the given goal. Mail will be sent to the user if
the C<sendmail> parameter is true.

Returns the data-point that was created:

    {
        id         => 'abc125'
        timestamp  => 1234567892,
        value      => 1,
        comment    => 'Floss every tooth for great justice!'
        updated_at => 1234567892
    }

=cut

method add_datapoint(
    Str  :$goal!,
    Int  :$timestamp,     # TODO: Change to a proper timestamp type.
    Num  :$value!,
    Str  :$comment = "",
    Bool :$sendmail = 0
) {
    $timestamp //= time();

    return $self->_userpost( 
        { timestamp => $timestamp, value => $value, comment => $comment, sendmail => $sendmail },
        [ 'goals', $goal, 'datapoints.json' ]
    );
}

=method goal

   my $results = $bee->goal('floss', datapoints => 0);

Returns information about a goal. The optional C<datapoints> parameter can be
supplied with a true value to also fetch datapoints for that goal.

=cut

method goal(
    Str  $goal,
    BeeBool :$datapoints = 'false' does coerce
) {
    return $self->_userget( [ 'goals', "$goal.json" ], { datapoints => $datapoints });
}

# Posts to the API. Takes a hashref of parameters. Remaining arguments
# are interpreted as a path.
sub _userpost {
    my ($self, $params, $path, $options) = @_;

    my $url  = $self->_path(['users', $self->username, @$path], $options);

    my $resp = $self->agent->post( $url, $params );

    unless ($resp->is_success) { 
        croak "Failed to fetch $url - ".$resp->status_line; 
    }

    return $json->decode($resp->content);

};

# Builds a path, and adds appropriate auth tokens, etc.
sub _path {
    my ($self, $path, $options) = @_;

    my $url  = join('/', $self->apibase, @$path) . "?auth_token=" . $self->token;

    if ($self->dryrun) {
        $url .= "&dryrun=1";
    }

    foreach my $opt (keys %$options) {
        $url .= "&$opt=$options->{$opt}";   # TODO: Escape params!
    }
    
    return $url;
}

# Fetches something from the API. Automatically prepends the API path,
# adds the token to the end, and decodes the JSON.

sub _get {
    my ($self, $path, $options) = @_;

    my $url  = $self->_path($path, $options);
    my $resp = $self->agent->get( $url );

    unless ($resp->is_success) { 
        croak "Failed to fetch $url - ".$resp->status_line; 
    }

    return $json->decode($resp->content);
}

# As for _get, but prepends 'users' and the current user.
sub _userget {
    my ($self, $args, $options) = @_;

    return $self->_get([ 'users', $self->username, @$args], $options);
}

1;
