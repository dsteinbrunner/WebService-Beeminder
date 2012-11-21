package WebService::Beeminder;

# ABSTRACT: Access the Beeminder API

use 5.010;
use strict;
use warnings;
use Any::Moose;
use JSON::Any;
use LWP::UserAgent;
use Carp qw(croak);

has 'token'   => (isa => 'Str', is => 'ro', required => 1);
has 'user'    => (isa => 'Str', is => 'ro', default => 'me');
has 'agent'   => (              is => 'rw');
has 'apibase' => (isa => 'Str', is => 'ro', default => 'https://www.beeminder.com/api/v1'); 

sub BUILD {
    my ($self) = @_;

    # Make sure we have a user-agent, if none provided.
    if (not $self->agent) {
        $self->agent(LWP::UserAgent->new(agent => "perl/$], WebService::Beeminder/" . $self->VERSION));
    }

    return;
}

sub fetch {
    my ($self, $goal) = @_;

    return $self->_userget( $goal, 'datapoints.json');

}

# Fetches something from the API. Automatically prepends the API path,
# adds the token to the end, and decodes the JSON.

sub _get {
    my ($self, @path) = @_;
    
    state $json = JSON::Any->new;

    my $url  = join('/', $self->apibase, @path) . "?auth_token=" . $self->token;
    my $ua   = $self->agent;
    my $resp = $ua->get($url);

    unless ($resp->is_success) { croak "Failed to fetch $url"; }

    return $json->decode($resp->content);
}

# As for _get, but prepends 'users' and the current user.
sub _userget {
    my ($self, @args) = @_;

    return $self->_get('users', $self->user);
}

1;
