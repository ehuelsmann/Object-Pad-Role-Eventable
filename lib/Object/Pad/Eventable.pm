#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2022 -- leonerd@leonerd.org.uk

package Object::Pad::Eventable 0.01;

use v5.16;
use feature 'signatures';
use warnings;
no warnings 'experimental::signatures';
use strict;

use Carp;
use Feature::Compat::Try;
use Scalar::Util qw( blessed weaken );
use Scope::Guard;

use Object::Pad 0.76 ':experimental(mop)';

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
        push @events, @{$super->name . '::EFFECTIVE_EVENTS'};
    }
    for my $super ($class->all_roles) {
        push @events, @{$super->name . '::EFFECTIVE_EVENTS'};
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

    method invoke_event( $event, @args ) {
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
