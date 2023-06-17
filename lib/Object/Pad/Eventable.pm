
package Object::Pad::Eventable 0.01;

use v5.16;
use feature 'signatures';
use warnings;
use strict;

no warnings 'experimental::signatures';

use Carp;
use Feature::Compat::Try;
use Scalar::Util qw( blessed weaken );
use Scope::Guard;

use Object::Pad 0.60 ':experimental(mop)';

require XSLoader;
XSLoader::load( __PACKAGE__, our $VERSION );


sub import
{
   $^H{"Object::Pad::Eventable"}++;
   $^H{"Object::Pad::Eventable/Eventable"}++;
}

sub _post_seal( $classname ) {
    no strict 'refs';

    my @events = @{$classname . '::EVENTS'};
    my $class = Object::Pad::MOP::Class->for_class( $classname );
    for my $super ($class->superclasses) {
        my $super_name = $super->name;
        if ($super_name->DOES( 'Object::Pad::Eventable' )) {
            push @events, @{$super_name . '::EFFECTIVE_EVENTS'};
        }
    }
    for my $super ($class->all_roles) {
        my $super_name = $super->name;
        if ($super_name->DOES( 'Object::Pad::Eventable' )) {
            push @events, @{$super_name . '::EFFECTIVE_EVENTS'};
        }
    }
    my %effective_events = (
        map { $_ => 1 }
        @events
        );
    @{$classname . '::EFFECTIVE_EVENTS'} = keys %effective_events;
}

role Object::Pad::Eventable {

    field %subscribers;
    field $_guard;

    ADJUST {
        no strict 'refs';
        %subscribers = (
            map { $_ => [] }
            @{__CLASS__ . '::EFFECTIVE_EVENTS'}
            );
    }

    method emit( $event, @args ) {
        croak "Event '$event' not produced by " . __CLASS__
            if not exists $subscribers{$event};

        for my $item (@{$subscribers{$event}}) {
            $item->[0]->( $self, @args );
        }
    }

    method has_subscribers( $event ) {
        croak "Event '$event' not produced by " . __CLASS__
            if not exists $subscribers{$event};

        return scalar(@{$subscribers{$event}});
    }

    method on( $event, $consumer ) {
        croak "Event '$event' not produced by " . __CLASS__
            if not exists $subscribers{$event};

        if (not $_guard) { # Emulate DEMOLISH
            $_guard = Scope::Guard->new(
                sub {
                    for my $event (keys %subscribers) {
                        # make sure all futures are cancelled
                        # and queues are finished
                        for my $item (@{$subscribers{$event}}) {
                            $item->[1]->();
                        }
                    }
                })
        }

        my $item;
        if (blessed $consumer) {
            if ($consumer->isa("Future")) {
                $item = [
                    sub {
                        my ($self) = @_;
                        $consumer->done( @_ );
                    },
                    sub { $consumer->cancel; }
                    ];

                my $weak_self = $self;
                weaken $weak_self;
                $consumer->on_ready(
                    sub {
                        if ($weak_self) {
                            # During the DEMOLISH workaround, the weak
                            # self reference has been nullified, yet
                            # since the Future is being cancelled, this
                            # callback is being invoked.  It's not an
                            # issue when subscription removal isn't
                            # executed.
                            $weak_self->unsubscribe( $event, $item->[0] );
                        }
                    });
            }
            else { # this must be a Future::Queue
                $item = [
                    sub {
                        my ($self) = @_;
                        try {
                            $consumer->push( [ @_ ] );
                        }
                        catch ($e) {
                            # the queue was finished; unsubscribe
                            $self->unsubscribe( $event, __SUB__ );
                        }
                    },
                    sub { $consumer->finish; }
                    ];
            }
        }
        else {
            $item = [ $consumer, sub { } ];
        }
        push @{$subscribers{$event}}, $item;
        return $item->[0];
    }

    method once( $event, $consumer ) {
        croak "Event '$event' not produced by " . __CLASS__
            if not exists $subscribers{$event};

        return $self->on(
            $event,
            sub {
                my ($self) = @_;
                $consumer->( @_ );
                $self->unsubscribe( $event, __SUB__ );
            });
    }

    method unsubscribe( $event, $subscription = undef ) {
        croak "Event '$event' not produced by " . __CLASS__
            if not exists $subscribers{$event};

        return
            unless @{$subscribers{$event}};

        if ($subscription) {
            my $idx;
            my $items = $subscribers{$event};
            ($items->[$_]->[0] == $subscription) and ($idx = $_), last for $#$items;

            if (defined $idx) {
                my $deleted = splice @$items, $idx, 1, ();
                $deleted->[1]->();
            }
        }
        else {
            for my $item (@{$subscribers{$event}}) {
                $item->[1]->();
            }
            $subscribers{$event} = [];
        }

        return;
    }

}

0x55AA;

__END__

=head1 NAME

Object::Pad::Eventable - A class attribute and role to emit events

=head1 SYNOPSIS

  use Object::Pad;
  use Object::Pad::Eventable;

  package MyObject 0.001;
  class MyObject :Eventable :does(Object::Pad::Eventable);

  event foo;

  method foo($a) {
    $self->emit( foo => $a );
  }

  1;

  package main;

  use MyObject;
  use Future;
  use Future::Queue;

  my $i = MyObject->new;

  # subscribe to an event once:
  $i->once( foo => sub { say "Hello" } );

  # or with a future:
  my $f = Future->new->on_done( sub { say "Hello" } );
  $i->on( foo => $f );

  # subscribe to multiple events:
  my $subscription = $i->on( foo => sub { say "Hello" } );

  # or on a queue:
  my $q = Future::Queue->new;
  my $subscription_q = $i->on( foo => $q );

  # then unsubscribe:
  $i->unsubscribe( $subscription );
  $i->unsubscribe( $subscription_q );

  # alternatively, unsubscribe by cancelling the future:
  $f->cancel;

  # or by finishing the queue (unsubscribes upon the next event):
  $q->finish;


=head1 DESCRIPTION

This module makes the C<:Eventable> class attribute available to Object::Pad.
When applied to a class, it adds the capability to define and emit events to
subscribers. Methods to subscribe to and emit events are provided by the
C<Object::Pad::Eventable> role.

Interested subscribers can provide a code reference, a L<Future::Queue>
or a L<Future> to receive events.

=head1 METHODS

=head2 on

  my $subscription = $obj->on( foo => sub { ... } );
  my $subscription = $obj->on( foo => $f );
  my $subscription = $obj->on( foo => $q );

Subscribes to notifications of the named event.  The event consumer can be
a coderef, L<Future> or L<Future::Queue>. In case it's a C<Future>, the
consumer will be unsubscribed after a single event.

Returns a C<$subscription> which can be used to unsubscribe later.

=head2 once

  my $subscription = $obj->once( foo => sub { ... } );

Subscribes to a single notification of teh named event.  This function does
not make sense for the Future and Future::Queue subscribers, because Futures
are single-notification anyway and Future::Queues are much more easily
replaced with Futures for single notifications.

=head2 emit

  $obj->emit( $event_name, $arg1, $arg2, ... )

Send the event to subscribers.  If the subscriber is a coderef, the
function is called with the object as the first argument and the values
of C<$arg1, $arg2, ...> as further arguments.  If the subscriber is a
Future, it resolves with the same values as passed to the callback.  If
the subscriber is a Future::Queue, an arrayref is put in the queue with
the elements of the array being the values as passed to the callback.

  # callback style:
  $sink->( $obj, $arg1, $arg2, ... );

  # Future style:
  $f->done( $obj, $arg1, $arg2, ... );

  # Future::Queue style:
  $q->push( [ $obj, $arg1, $arg2, ... );

=head2 has_subscribers

  my $bool = $obj->has_subscribers( 'foo' );

Checks if the named event has subscribers.

=head2 unsubscribe

  $obj->unsubscribe( 'foo' );
  $obj->unsubscribe( foo => $subscription );

Remove all subscribers from the named event (when no subscription argument
is given) or remove the specific subscription.

Any pending futures will be cancelled upon unsubscription.  Queues will
be finished.

When an object goes out of scope, this function is used to cancel any active
subscriptions.

=head1 TODO

=over 4

=item * Add event names to the 'Eventable' class attribute data structure
        instead of in the c<@EVENTS> variable.  This requires support from
        Object::Pad to retrieve the class attribute data (from its API)

=item * Restrict the use of the 'event' keyword to classes which have been
        applied the 'Eventable' attribute

=item * Restrict the use of the 'event' keyword to the class definition scope

=item * Automatically apply the C<Object::Pad::Eventable> role as part of
        the application of the class attribute

=back

=head1 AUTHOR

=over 4

=item * C<< Erik Huelsmann <ehuels@gmail.com> >>

=back

Inspired by L<Role::EventEmitter> by Dan Book, which is itself adapted
from L<Mojolicious>.  This module and its tests are implemented from scratch.

With code copied from L<Object::Pad::Keyword::Accessor> and
L<Object::Pad::ClassAttr::Struct> by Paul Evans for respectively the C<event>
keyword and C<:Eventable> class attribute.

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2023 by Erik Huelsmann.

This is free software; you can redistribute it and/or modify it under the same
terms as the Perl 5 programming language system itself.
