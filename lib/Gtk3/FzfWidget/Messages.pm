package Gtk3::FzfWidget::Messages ;

use strict ;
use warnings ;
use Exporter 'import' ;

our @EXPORT_OK = qw(
	msg
	MSG_FZF_NOT_FOUND
	MSG_VERSION_TOO_OLD
	MSG_VERSION_PARSE
	MSG_PROCESS_FAILED
	MSG_PROCESS_RESTART
	MSG_PROCESS_GIVE_UP
	MSG_OPT_CONFLICT
	MSG_SOCKET_FALLBACK
	MSG_LOADING
	MSG_MATCH_COUNT
	MSG_PLACEHOLDER
	MSG_HTTP_FAILED
	MSG_EXIT_CODE
	MSG_TCP_TIMEOUT
	MSG_UNIX_TIMEOUT
	) ;
our @EXPORT = qw() ;

our @MSG = (
	'fzf binary not found on PATH',                                   # MSG_FZF_NOT_FOUND
	'fzf version %s is below minimum required version %s',            # MSG_VERSION_TOO_OLD
	'failed to start fzf process: %s',                                # MSG_PROCESS_FAILED
	'fzf process crashed (attempt %d of %d), restarting',             # MSG_PROCESS_RESTART
	'fzf process failed after %d restart attempts: %s',               # MSG_PROCESS_GIVE_UP
	"conflicting fzf option '%s' is not supported in headless mode",  # MSG_OPT_CONFLICT
	'Unix socket unavailable, falling back to TCP: %s',               # MSG_SOCKET_FALLBACK
	'Loading...',                                                      # MSG_LOADING
	'%d/%d',                                                           # MSG_MATCH_COUNT
	'Search...',                                                       # MSG_PLACEHOLDER
	'fzf HTTP request failed: %s',                                     # MSG_HTTP_FAILED
	'fzf exited with code %d',                                         # MSG_EXIT_CODE
	'TCP startup timeout: fzf did not announce a listen port',         # MSG_TCP_TIMEOUT
	'Unix socket startup timeout',                                     # MSG_UNIX_TIMEOUT
	'cannot parse fzf version from output: %s',                       # MSG_VERSION_PARSE
	) ;

use constant {
	MSG_FZF_NOT_FOUND   => 0,
	MSG_VERSION_TOO_OLD => 1,
	MSG_PROCESS_FAILED  => 2,
	MSG_PROCESS_RESTART => 3,
	MSG_PROCESS_GIVE_UP => 4,
	MSG_OPT_CONFLICT    => 5,
	MSG_SOCKET_FALLBACK => 6,
	MSG_LOADING         => 7,
	MSG_MATCH_COUNT     => 8,
	MSG_PLACEHOLDER     => 9,
	MSG_HTTP_FAILED     => 10,
	MSG_EXIT_CODE       => 11,
	MSG_TCP_TIMEOUT     => 12,
	MSG_UNIX_TIMEOUT    => 13,
	MSG_VERSION_PARSE   => 14,
	} ;

sub msg
{
my ($idx, @args) = @_ ;

return sprintf($MSG[$idx], @args) ;
}

1 ;
