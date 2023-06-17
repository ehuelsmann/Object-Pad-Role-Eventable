#!/usr/bin/perl

use v5.14;
use warnings;

use Test2::V0;

use Object::Pad;
use Object::Pad::Eventable;


class Parent :Eventable :does(Object::Pad::Eventable) {
    event a;
    event b;
    event c;
}

class Example :Eventable :isa(Parent) {
   event k;
   event y;

   field $x;
   field $y;
   field $z = undef;
}

my $i = Example->new;

ok( $i->DOES( 'Object::Pad::Eventable' ) );
is( [ sort @Parent::EVENTS ], [ qw( a b c ) ]);
is( [ sort @Example::EVENTS ], [ qw( k y ) ]);

is( [ sort @Parent::EFFECTIVE_EVENTS ], [ qw( a b c ) ]);
is( [ sort @Example::EFFECTIVE_EVENTS ], [ qw( a b c k y ) ]);
ok lives { $i->has_subscribers( 'a' ) };
ok lives { $i->has_subscribers( 'k' ) };
ok dies { $i->has_subscribers( 'non-existent' ) };


done_testing;
