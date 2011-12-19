#!perl

use warnings;
use strict;
use Test::More;
use Test::Exception;
use Test::Deep;
use IO::Socket::INET;
use Redis;

my $lsocket = IO::Socket::INET->new(
    LocalHost => '127.0.0.1',
    Proto => 'tcp',
    Listen => 1
);
my $port = $lsocket->sockport;

ok(my $r = Redis->new(server => "127.0.0.1:$port"), 'connected to our test redis-server');

my $socket = $lsocket->accept;
$lsocket->close;

sub r {
  $socket->send(join('', map {"$_\r\n"} @_));
}

## -ERR responses
r('-you must die!!');
throws_ok sub { $r->__read_response('cmd') }, qr/\[cmd\] you must die!!/,
  'Error response must throw exception';


## +TEXT responses
my $m;
r('+all your text are belong to us');
lives_ok sub { $m = $r->__read_response('cmd') }, 'Text response ok';
is($m, 'all your text are belong to us', '... with the expected message');


## :NUMBER responses
r(':234');
lives_ok sub { $m = $r->__read_response('cmd') }, 'Integer response ok';
is($m, 234, '... with the expected value');


## $SIZE PAYLOAD responses
r('$19', "Redis\r\nis\r\ngreat!\r\n");
lives_ok sub { $m = $r->__read_response('cmd') }, 'Size+payload response ok';
is($m, "Redis\r\nis\r\ngreat!\r\n", '... with the expected message');

r('$0', "");
lives_ok sub { $m = $r->__read_response('cmd') },
  'Zero-size+payload response ok';
is($m, "", '... with the expected message');

r('$-1');
lives_ok sub { $m = $r->__read_response('cmd') },
  'Negative-size+payload response ok';
ok(!defined($m), '... with the expected undefined message');


## Multi-bulk responses
my @m;
r('*4', '$5', 'Redis', ':42', '$-1', '+Cool stuff');
lives_ok sub { @m = $r->__read_response('cmd') },
  'Simple multi-bulk response ok';
cmp_deeply(
  \@m,
  ['Redis', 42, undef, 'Cool stuff'],
  '... with the expected list of values'
);


## Nested Multi-bulk responses
r('*5', '$5', 'Redis', ':42', '*4', ':1', ':2', '$4', 'hope', '*2', ':4',
  ':5', '$-1', '+Cool stuff');
lives_ok sub { @m = $r->__read_response('cmd') },
  'Nested multi-bulk response ok';
cmp_deeply(
  \@m,
  ['Redis', 42, [1, 2, 'hope', [4, 5]], undef, 'Cool stuff'],
  '... with the expected list of values'
);


## Nil multi-bulk responses
r('*-1');
lives_ok sub { $m = $r->__read_response('blpop') },
  'Read a NIL multi-bulk response';
is($m, undef, '... with the expected "undef" value');

done_testing();
