package TOML::Tiny;
# ABSTRACT: a minimal, pure perl TOML parser and serializer

use strict;
use warnings;
no warnings qw(experimental);
use v5.18;

use TOML::Tiny::Parser;
use TOML::Tiny::Writer;

use parent 'Exporter';

our @EXPORT = qw(
  from_toml
  to_toml
);

#-------------------------------------------------------------------------------
# TOML module compatibility
#-------------------------------------------------------------------------------
sub from_toml {
  my $source = shift;
  my $parser = TOML::Tiny::Parser->new(@_);
  my $toml = eval{ $parser->parse($source) };
  if (wantarray) {
    return ($toml, $@);
  } else {
    die $@ if $@;
    return $toml;
  }
}

sub to_toml {
  goto \&TOML::Tiny::Writer::to_toml;
}

#-------------------------------------------------------------------------------
# Object API
#-------------------------------------------------------------------------------
sub new {
  my ($class, %param) = @_;
  bless{ %param, parser => TOML::Tiny::Parser->new(%param) }, $class;
}

sub encode {
  my ($self, $source) = @_;
  $self->{parser}->parse;
}

sub decode {
  my ($self, $data) = @_;
  TOML::Tiny::Writer::to_toml($data,
    strict_arrays => $self->{strict_arrays},
  );
}

#-------------------------------------------------------------------------------
# For compatibility with TOML::from_toml's use of $TOML::Parser
#-------------------------------------------------------------------------------
sub parse {
  goto \&encode;
}

1;

=head1 SYNOPSIS

  use TOML::Tiny qw(from_toml to_toml);

  binmode STDIN,  ':encoding(UTF-8)';
  binmode STDOUT, ':encoding(UTF-8)';

  # Decoding TOML
  my $toml = do{ local $/; <STDIN> };
  my ($parsed, $error) = from_toml $toml;

  # Encoding TOML
  say to_toml({
    stuff => {
      about => ['other', 'stuff'],
    },
  });

  # Object API
  my $parser = TOML::Tiny->new;
  my $data = $parser->decode($toml);
  say $parser->encode($data);


=head1 DESCRIPTION

C<TOML::Tiny> implements a pure-perl parser and generator for the
L<TOML|https://github.com/toml-lang/toml> data format. It conforms to TOML v5
(with a few caveats; see L</strict_arrays>) with support for more recent
changes in pursuit of v6.

C<TOML::Tiny> strives to maintain an interface compatible to the L<TOML> and
L<TOML::Parser> modules, and could even be used to override C<$TOML::Parser>:

  use TOML;
  use TOML::Tiny;

  local $TOML::Parser = TOML::Tiny->new(...);
  say to_toml(...);


=head1 EXPORTS

C<TOML::Tiny> exports the following to functions for compatibility with the
L<TOML> module. See L<TOML/FUNCTIONS>.

=head2 from_toml

Parses a string of C<TOML>-formatted source and returns the resulting data
structure. Any arguments after the first are passed to L<TOML::Tiny::Parser>'s
constructor.

If there is a syntax error in the C<TOML> source, C<from_toml> will die with
an explanation which includes the line number of the error.

  my $result = eval{ from_toml($toml_string) };

Alternately, this routine may be called in list context, in which case syntax
errors will result in returning two values, C<undef> and an error message.

  my ($result, $error) = from_toml($toml_string);

=head2 to_toml

Encodes a hash ref as a C<TOML>-formatted string.

  my $toml = to_toml({foo => {'bar' => 'bat'}});

  # [foo]
  # bar="bat"


=head1 OBJECT API

=head2 new

=over

=item inflate_datetime

By default, C<TOML::Tiny> treats TOML datetimes as strings in the generated
data structure. The C<inflate_datetime> parameter allows the caller to provide
a routine to intercept those as they are generated:

  use DateTime::Format::RFC3339;

  my $parser = TOML::Tiny->new(
    inflate_datetime => sub{
      my $dt_string = shift;
      return DateTime::Format::RFC3339->parse_datetime($dt_string);
    },
  );

=item inflate_boolean

By default, boolean values in a C<TOML> document result in a C<1> or C<0>.
If L<Types::Serialiser> is installed, they will instead be C<Types::Serialiser::true>
or C<Types::Serialiser::false>.

If you wish to override this, you can provide your own routine to generate values:

  my $parser = TOML::Tiny->new(
    inflate_boolean => sub{
      my $bool = shift;
      if ($bool eq 'true') {
        return 'The Truth';
      } else {
        return 'A Lie';
      }
    },
  );

=item strict_arrays

C<TOML v5> specified homogenous arrays. This has since been removed and will no
longer be part of the standard as of C<v6> (as of the time of writing; the
author of C<TOML> has gone back and forth on the issue, so no guarantees).

By default, C<TOML::Tiny> is flexible and supports heterogenous arrays. If you
wish to require strictly typed arrays (for C<TOML>'s definition of "type",
anyway), C<strict_arrays> will produce an error when encountering arrays with
heterogenous types.

=back

=head2 decode

Decodes C<TOML> and returns a hash ref. Dies on parse error.

=head2 encode

Encodes a perl hash ref as a C<TOML>-formatted string. Dies when encountering
an array of mixed types if C<strict_arrays> was set.

=head2 parse

Alias for C<encode> to provide compatibility with C<TOML::Parser> when
overriding the parser by setting C<$TOML::Parser>.


=head1 DIFFERENCES FROM L<TOML> AND L<TOML::Parser>

C<TOML::Tiny> differs in a few significant ways from the L<TOML> module,
particularly in adding support for newer C<TOML> features and strictness.

L<TOML> defaults to lax parsing and provides C<strict_mode> to (slightly)
tighten things up. C<TOML::Tiny> defaults to (somehwat) stricter parsing, with
the exception of permitting heterogenous arrays (illegal in v4 and v5, but
permissible in the upcoming v6); optional enforcement of homogenous arrays is
supported with C<strict_arrays>.

C<TOML::Tiny> ignores invalid surrogate pairs within basic and multiline
strings (L<TOML> may attempt to decode an invalid pair). Additionally, only
those character escapes officially supported by TOML are interpreted as such by
C<TOML::Tiny>.

C<TOML::Tiny> supports stripping initial whitespace and handles lines
terminating with a backslash correctly in multilne strings:

  # TOML input
  x="""
  foo"""

  y="""\
     how now \
       brown \
  bureaucrat.\
  """

  # Perl output
  {x => 'foo', y => 'how now brown bureaucrat.'}

C<TOML::Tiny> includes support for integers specified in binary, octal or hex
as well as the special float values C<inf> and C<nan>.

=head1 ACKNOWLEDGEMENTS

Thanks to L<ZipRecruiter|https://www.ziprecruiter.com> for encouraging their
employees to contribute back to the open source ecosystem. Without their
dedication to quality software development this distribution would not exist.
