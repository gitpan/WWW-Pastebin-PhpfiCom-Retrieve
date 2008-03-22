package WWW::Pastebin::PhpfiCom::Retrieve;

use warnings;
use strict;

our $VERSION = '0.001';

use URI;
use HTML::TokeParser::Simple;
use HTML::Entities;
use base 'WWW::Pastebin::Base::Retrieve';

sub _make_uri_and_id {
    my ( $self, $id ) = @_;

    $id=~ s{ ^\s+ | (?:http://)? (?:www\.)? phpfi\.com/(?=\d+) | \s+$ }{}xgi;

    return ( URI->new("http://phpfi.com/$id"), $id );
}

sub _get_was_successful {
    my ( $self, $content ) = @_;

    my $results_ref = $self->_parse( $content );
    return
        unless defined $results_ref;

    my $content_uri = $self->uri->clone;
    $content_uri->query_form( download => 1 );
    my $content_response = $self->ua->get( $content_uri );
    if ( $content_response->is_success ) {
        $results_ref->{content} =
            $self->content($content_response->content);
        return $self->results( $results_ref );
    }
    else {
        return $self->_set_error(
            'Network error: ' . $content_response->status_line
        );
    }
}

sub _parse {
    my ( $self, $content ) = @_;

    my $parser = HTML::TokeParser::Simple->new( \$content );

    my %data;
    my %nav;
    @nav{ qw(get_info  level  get_lang  is_success get_content  check_404) }
    = (0) x 6;
    $nav{content} = '';
    while ( my $t = $parser->get_token ) {
        if ( $t->is_start_tag('td') ) {
            $nav{get_info}++;
            $nav{check_404}++;
            $nav{level} = 1;
        }
        elsif ( $nav{check_404} == 1 and $t->is_end_tag('td') ) {
            $nav{check_404} = 2;
            $nav{level} = 10;
        }
        elsif ( $nav{check_404} and $t->is_start_tag('b') ) {
            return $self->_set_error('This paste does not seem to exist');
        }
        elsif ( $nav{get_info} == 1 and $t->is_text ) {
            my $text = $t->as_is;
            $text =~ s/&nbsp;/ /g;

            @data{ qw(age name hits) } = $text
            =~ /
                created \s+
                ( .+? (?:\s+ago)? ) # stupid timestaps
                (?: \s+ by \s+ (.+?) )? # name might be missing
                ,\s+ (\d+) \s+ hits?
            /xi;

            $data{name} = 'N/A'
                unless defined $data{name};

            @nav{ qw(get_info level) } = (2, 2);
        }
        elsif ( $t->is_start_tag('select')
            and defined $t->get_attr('name')
            and $t->get_attr('name') eq 'lang'
        ) {
            $nav{get_lang}++;
            $nav{level} = 3;
        }
        elsif ( $t->is_start_tag('div')
            and defined $t->get_attr('id')
            and $t->get_attr('id') eq 'content'
        ) {
            @nav{ qw(get_content level) } = (1, 4);
        }
        elsif ( $nav{get_content} and $t->is_end_tag('div') ) {
            @nav{ qw(get_content level) } = (0, 5);
        }
        elsif ( $nav{get_content} and $t->is_text ) {
            $nav{content} .= $t->as_is;
            $nav{level} = 6;
        }
        elsif ( $nav{get_lang} == 1
            and $t->is_start_tag('option')
            and defined $t->get_attr('selected')
            and defined $t->get_attr('value')
        ) {
            $data{lang} = $t->get_attr('value');
            $nav{is_success} = 1;
            last;
        }
    }

    return $self->_set_error('This paste does not seem to exist')
        if $nav{content} =~ /entry \d+ not found/i;

    return $self->_set_error("Parser error! Level == $nav{level}")
        unless $nav{is_success};

    $data{ $_ } = decode_entities( delete $data{ $_ } )
        for grep { $_ ne 'content' } keys %data;

    # content() is set in retrieve()
    return \%data;
}


1;
__END__

=head1 NAME

WWW::Pastebin::PhpfiCom::Retrieve - retrieve pastes from http://phpfi.com/ website

=head1 SYNOPSIS

    use strict;
    use warnings;

    use WWW::Pastebin::PhpfiCom::Retrieve;

    my $paster = WWW::Pastebin::PhpfiCom::Retrieve->new;

    my $results_ref = $paster->retrieve('http://phpfi.com/302683')
        or die $paster->error;

    printf "Paste %s was posted %s by %s, it is written in %s "
                . "and was viewed %s time(s)\n%s\n",
                $paster->uri, @$results_ref{ qw(age name lang hits content) };

=head1 DESCRIPTION

The module provides interface to retrieve pastes from L<http://phpfi.com/>
website via Perl.

=head1 CONSTRUCTOR

=head2 C<new>

    my $paster = WWW::Pastebin::PhpfiCom::Retrieve->new;

    my $paster = WWW::Pastebin::PhpfiCom::Retrieve->new(
        timeout => 10,
    );

    my $paster = WWW::Pastebin::PhpfiCom::Retrieve->new(
        ua => LWP::UserAgent->new(
            timeout => 10,
            agent   => 'PasterUA',
        ),
    );

Constructs and returns a brand new juicy WWW::Pastebin::PhpfiCom::Retrieve
object. Takes two arguments, both are I<optional>. Possible arguments are
as follows:

=head3 C<timeout>

    ->new( timeout => 10 );

B<Optional>. Specifies the C<timeout> argument of L<LWP::UserAgent>'s
constructor, which is used for retrieving. B<Defaults to:> C<30> seconds.

=head3 C<ua>

    ->new( ua => LWP::UserAgent->new( agent => 'Foos!' ) );

B<Optional>. If the C<timeout> argument is not enough for your needs
of mutilating the L<LWP::UserAgent> object used for retrieving, feel free
to specify the C<ua> argument which takes an L<LWP::UserAgent> object
as a value. B<Note:> the C<timeout> argument to the constructor will
not do anything if you specify the C<ua> argument as well. B<Defaults to:>
plain boring default L<LWP::UserAgent> object with C<timeout> argument
set to whatever C<WWW::Pastebin::PhpfiCom::Retrieve>'s C<timeout> argument
is set to as well as C<agent> argument is set to mimic Firefox.

=head1 METHODS

=head2 C<retrieve>

    my $results_ref = $paster->retrieve('http://phpfi.com/302683')
        or die $paster->error;

    my $results_ref = $paster->retrieve('302683')
        or die $paster->error;

Instructs the object to retrieve a paste specified in the argument. Takes
one mandatory argument which can be either a full URI to the paste you
want to retrieve or just its ID.
On failure returns either C<undef> or an empty list depending on the context
and the reason for the error will be available via C<error()> method.
On success returns a hashref with the following keys/values:

    $VAR1 = {
        'hits' => '0',
        'lang' => 'perl',
        'content' => '{ test => \'yes\' }',
        'name' => 'Zoffix',
        'age' => '7 hours and 41 minutes'
    };

=head3 content

    { 'content' => '{ test => \'yes\' }' }

The C<content> kew will contain the actual content of the paste.

=head3 lang

    { 'lang' => 'perl' }

The C<lang> key will contain the (computer) language of the paste
(as was specified by the poster).

=head3 name

    { 'name' => 'Zoffix' }

The C<name> key will contain the name of the poster who created the paste.

=head3 hits

    { 'hits' => '0' }

The C<hits> key will contain the number of times the paste was viewed.

=head3 age

    { 'age' => '7 hours and 41 minutes ago' }

The C<age> key will contain the "age" of the paste, i.e. how long ago
it was created. B<Note:> if the paste is old enough the C<age> will contain
the date/time of the post instead of "foo bar ago".

=head2 C<error>

    $paster->retrieve('http://phpfi.com/302683')
        or die $paster->error;

On failure C<retrieve()> returns either C<undef> or an empty list depending
on the context and the reason for the error will be available via C<error()>
method. Takes no arguments, returns an error message explaining the failure.

=head2 C<id>

    my $paste_id = $paster->id;

Must be called after a successful call to C<retrieve()>. Takes no arguments,
returns a paste ID number of the last retrieved paste irrelevant of whether
an ID or a URI was given to C<retrieve()>

=head2 C<uri>

    my $paste_uri = $paster->uri;

Must be called after a successful call to C<retrieve()>. Takes no arguments,
returns a L<URI> object with the URI pointing to the last retrieved paste
irrelevant of whether an ID or a URI was given to C<retrieve()>

=head2 C<results>

    my $last_results_ref = $paster->results;

Must be called after a successful call to C<retrieve()>. Takes no arguments,
returns the exact same hashref the last call to C<retrieve()> returned.
See C<retrieve()> method for more information.

=head2 C<content>

    my $paste_content = $paster->content;

    print "Paste content is:\n$paster\n";

Must be called after a successful call to C<retrieve()>. Takes no arguments,
returns the actual content of the paste. B<Note:> this method is overloaded
for this module for interpolation. Thus you can simply interpolate the
object in a string to get the contents of the paste.

=head2 C<ua>

    my $old_LWP_UA_obj = $paster->ua;

    $paster->ua( LWP::UserAgent->new( timeout => 10, agent => 'foos' );

Returns a currently used L<LWP::UserAgent> object used for retrieving
pastes. Takes one optional argument which must be an L<LWP::UserAgent>
object, and the object you specify will be used in any subsequent calls
to C<retrieve()>.

=head1 SEE ALSO

L<LWP::UserAgent>, L<URI>

=head1 AUTHOR

Zoffix Znet, C<< <zoffix at cpan.org> >>
(L<http://zoffix.com>, L<http://haslayout.net>)

=head1 BUGS

Please report any bugs or feature requests to C<bug-www-pastebin-phpficom-retrieve at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=WWW-Pastebin-PhpfiCom-Retrieve>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::Pastebin::PhpfiCom::Retrieve

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=WWW-Pastebin-PhpfiCom-Retrieve>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/WWW-Pastebin-PhpfiCom-Retrieve>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/WWW-Pastebin-PhpfiCom-Retrieve>

=item * Search CPAN

L<http://search.cpan.org/dist/WWW-Pastebin-PhpfiCom-Retrieve>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2008 Zoffix Znet, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

