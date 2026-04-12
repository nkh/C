package Gtk3::FzfWidget::Client ;

use strict ;
use warnings ;
use IO::Socket::INET ;
use Gtk3::FzfWidget::Messages qw(msg MSG_HTTP_FAILED) ;

our $VERSION = '0.01' ;

# Use the fastest available JSON decoder.
my $_json_class ;

BEGIN
	{
	$_json_class =
		eval { require JSON::XS        ; 'JSON::XS'        } //
		eval { require Cpanel::JSON::XS ; 'Cpanel::JSON::XS' } //
		do   { require JSON::PP        ; 'JSON::PP'         } ;
	}

# Number of matches requested per poll.  Small enough to keep JSON payloads
# tiny; _maybe_fetch_more loads more on demand when the cursor approaches the end.
my $PAGE_SIZE = 50 ;

sub new
{
my ($class, %args) = @_ ;

my $self =
	{
	host      => $args{host} // '127.0.0.1',
	port      => $args{port},
	sock_get  => undef,   # persistent socket for GET (state queries)
	sock_post => undef,   # persistent socket for POST (actions)
	json      => $_json_class->new->utf8,
	} ;

return bless $self, $class ;
}

# ------------------------------------------------------------------------------

sub _connect_get
{
my ($self) = @_ ;
return $self->_connect_sock(\$self->{sock_get}) ;
}

sub _connect_post
{
my ($self) = @_ ;
return $self->_connect_sock(\$self->{sock_post}) ;
}

sub _connect_sock
{
my ($self, $sock_ref) = @_ ;

return 1 if $$sock_ref && !$$sock_ref->eof() ;

$$sock_ref = undef ;

$$sock_ref = IO::Socket::INET->new(
	PeerHost => $self->{host},
	PeerPort => $self->{port},
	Proto    => 'tcp',
	Timeout  => 2,
	) ;

unless ($$sock_ref)
	{
	my $m = msg(MSG_HTTP_FAILED, "connect: $!") ;
	warn $m ;
	print STDERR $m . "\n" ;
	return 0 ;
	}

$$sock_ref->autoflush(1) ;
return 1 ;
}

# ------------------------------------------------------------------------------

sub get_state
{
my ($self, $limit) = @_ ;

$limit //= $PAGE_SIZE ;

$self->_connect_get() or return undef ;

my $resp = $self->_get($self->{sock_get}, "/?limit=$limit&offset=0") ;
return undef unless $resp && $resp->{status} == 200 ;

my $data = eval { $self->{json}->decode($resp->{body}) } ;

if ($@)
	{
	my $m = msg(MSG_HTTP_FAILED, "JSON decode: $@") ;
	warn $m ;
	print STDERR $m . "\n" ;
	return undef ;
	}

return $data ;
}

# ------------------------------------------------------------------------------

sub get_more_matches
{
my ($self, $offset) = @_ ;

$self->_connect_get() or return undef ;

my $resp = $self->_get($self->{sock_get}, "/?limit=$PAGE_SIZE&offset=$offset") ;
return undef unless $resp && $resp->{status} == 200 ;

my $data = eval { $self->{json}->decode($resp->{body}) } ;

if ($@)
	{
	my $m = msg(MSG_HTTP_FAILED, "JSON decode: $@") ;
	warn $m ;
	print STDERR $m . "\n" ;
	return undef ;
	}

return $data->{matches} // [] ;
}

# ------------------------------------------------------------------------------

sub post_action
{
my ($self, $action) = @_ ;

$self->_connect_post() or return 0 ;

my $resp = $self->_post($self->{sock_post}, '/', $action) ;

return $resp && ($resp->{status} == 200 || $resp->{status} == 204) ;
}

# ------------------------------------------------------------------------------

sub _get
{
my ($self, $sock, $path) = @_ ;

my $req =
	"GET $path HTTP/1.1\r\n"
	. "Host: localhost\r\n"
	. "Connection: keep-alive\r\n"
	. "\r\n" ;

my $ok = eval { print $sock $req ; 1 } ;

unless ($ok)
	{
	# Socket broken — clear it so _connect_get reconnects next time
	$self->{sock_get} = undef ;
	my $m = msg(MSG_HTTP_FAILED, "write: $!") ;
	warn $m ;
	print STDERR $m . "\n" ;
	return undef ;
	}

return $self->_read_response($sock) ;
}

# ------------------------------------------------------------------------------

sub _post
{
my ($self, $sock, $path, $body) = @_ ;

$body //= '' ;

my $len = length($body) ;
my $req =
	"POST $path HTTP/1.1\r\n"
	. "Host: localhost\r\n"
	. "Content-Length: $len\r\n"
	. "Connection: keep-alive\r\n"
	. "\r\n"
	. $body ;

my $ok = eval { print $sock $req ; 1 } ;

unless ($ok)
	{
	$self->{sock_post} = undef ;
	my $m = msg(MSG_HTTP_FAILED, "write: $!") ;
	warn $m ;
	print STDERR $m . "\n" ;
	return undef ;
	}

return $self->_read_response($sock) ;
}

# ------------------------------------------------------------------------------

sub _read_response
{
my ($self, $sock) = @_ ;

my $status_line = $sock->getline() ;
return undef unless defined $status_line ;
$status_line =~ s/\r\n$// ;

my ($status) = $status_line =~ /HTTP\/1\.[01]\s+(\d+)/ ;
return undef unless defined $status ;

my %headers ;

while (my $line = $sock->getline())
	{
	$line =~ s/\r\n$// ;
	last if $line eq '' ;
	my ($k, $v) = split(/:\s*/, $line, 2) ;
	$headers{lc $k} = $v // '' ;
	}

my $body = '' ;

if (my $clen = $headers{'content-length'})
	{
	my $got = read($sock, $body, $clen + 0) ;

	unless (defined $got && $got == ($clen + 0))
		{
		my $m = msg(MSG_HTTP_FAILED, 'short body read') ;
		warn $m ;
		print STDERR $m . "\n" ;

		return undef ;
		}
	}

return { status => $status + 0, headers => \%headers, body => $body } ;
}

# ------------------------------------------------------------------------------

sub disconnect
{
my ($self) = @_ ;

for my $field (qw(sock_get sock_post))
	{
	if ($self->{$field})
		{
		$self->{$field}->close() ;
		$self->{$field} = undef ;
		}
	}
}

1 ;
