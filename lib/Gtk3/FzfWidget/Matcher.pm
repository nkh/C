package Gtk3::FzfWidget::Matcher ;

# Abstract fuzzy matcher interface.
#
# A Matcher takes a list of strings and a query string, and returns
# the indices of matching strings in ranked order.
#
# All methods are synchronous.  The FzfBackend layer handles async
# dispatch if needed.
#
# Interface:
#   $m->set_items(\@items)      — load items (must be called before match)
#   $m->match($query, $limit)   — returns \@matches: [{index=>N, score=>N, text=>S}, ...]
#   $m->item_count()            — total number of items
#   $m->name()                  — human-readable name of this implementation

use strict ;
use warnings ;

our $VERSION = '0.01' ;

sub new        { die ref(shift) . '::new not implemented'        }
sub set_items  { die ref(shift) . '::set_items not implemented'  }
sub match      { die ref(shift) . '::match not implemented'      }
sub item_count { 0 }
sub name       { 'abstract' }

1 ;

# ==============================================================================

package Gtk3::FzfWidget::PerlMatcher ;

# Pure-Perl fuzzy matcher.  No external dependencies.
#
# Matching algorithm:
#   1. Empty query: all items match, in insertion order, score=0.
#   2. Non-empty query: case-insensitive substring for each space-separated
#      token.  Items matching all tokens are returned.  Score is the sum of
#      the positions of each token match (lower = better).
#
# This is not as sophisticated as fzf's Smith-Waterman-based scoring, but it
# is fast, dependency-free, and correct enough for testing and fallback use.

use strict ;
use warnings ;
use Encode qw(decode_utf8 is_utf8) ;

our @ISA = ('Gtk3::FzfWidget::Matcher') ;
our $VERSION = '0.01' ;

sub new
{
my ($class, %args) = @_ ;
return bless { _items => [], _lc_items => [] }, $class ;
}

sub name { 'PerlMatcher (substring)' }

sub set_items
{
my ($self, $items) = @_ ;
$self->{_items} = $items ;
$self->{_lc_items} = [map { lc(defined $_ ? $_ : '') } @$items] ;
}

sub item_count { scalar @{$_[0]->{_items}} }

sub match
{
my ($self, $query, $limit) = @_ ;
$limit //= scalar @{$self->{_items}} ;

my $items    = $self->{_items} ;
my $lc_items = $self->{_lc_items} ;
my @results ;

if (!defined $query || $query eq '')
	{
	# Empty query: all items, insertion order
	my $n = @$items < $limit ? scalar @$items : $limit ;
	for my $i (0 .. $n - 1)
		{
		push @results, { index => $i, score => 0, text => $items->[$i] } ;
		}
	return \@results ;
	}

my @tokens = map { lc } split /\s+/, $query ;

for my $i (0 .. $#$items)
	{
	my $lc = $lc_items->[$i] ;
	my $score = 0 ;
	my $all_match = 1 ;

	for my $token (@tokens)
		{
		my $pos = index($lc, $token) ;
		if ($pos < 0) { $all_match = 0 ; last }
		$score += $pos ;
		}

	if ($all_match)
		{
		push @results, { index => $i, score => $score, text => $items->[$i] } ;
		last if @results >= $limit * 4 ;   # collect extras for sorting
		}
	}

# Sort by score (lower = better match position)
@results = sort { $a->{score} <=> $b->{score} } @results ;
return [@results[0 .. ($#results < $limit-1 ? $#results : $limit-1)]] ;
}

1 ;
