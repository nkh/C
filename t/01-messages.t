use strict ;
use warnings ;
use Test::More tests => 8 ;

use Gtk3::FzfWidget::Messages qw(
	msg
	MSG_FZF_NOT_FOUND
	MSG_VERSION_TOO_OLD
	MSG_PROCESS_FAILED
	MSG_PROCESS_RESTART
	MSG_PROCESS_GIVE_UP
	MSG_LOADING
	MSG_MATCH_COUNT
	MSG_PLACEHOLDER
	MSG_HTTP_FAILED
	MSG_EXIT_CODE
	MSG_VERSION_PARSE
	) ;

is(msg(MSG_FZF_NOT_FOUND),
	'fzf binary not found on PATH',
	'MSG_FZF_NOT_FOUND') ;

is(msg(MSG_VERSION_TOO_OLD, '0.60.0', '0.65.0'),
	'fzf version 0.60.0 is below minimum required version 0.65.0',
	'MSG_VERSION_TOO_OLD with args') ;

is(msg(MSG_PROCESS_FAILED, 'fork: ENOMEM'),
	'failed to start fzf process: fork: ENOMEM',
	'MSG_PROCESS_FAILED with arg') ;

is(msg(MSG_PROCESS_RESTART, 1, 3),
	'fzf process crashed (attempt 1 of 3), restarting',
	'MSG_PROCESS_RESTART with args') ;

is(msg(MSG_PROCESS_GIVE_UP, 3, 'timeout'),
	'fzf process failed after 3 restart attempts: timeout',
	'MSG_PROCESS_GIVE_UP with args') ;

is(msg(MSG_LOADING),   'Loading...', 'MSG_LOADING') ;
is(msg(MSG_PLACEHOLDER), 'Search...', 'MSG_PLACEHOLDER') ;

is(msg(MSG_MATCH_COUNT, 5, 42), '5/42', 'MSG_MATCH_COUNT with args') ;
