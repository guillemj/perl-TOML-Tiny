package TOML::Tiny::Writer;

use strict;
use warnings;
no warnings qw(experimental);
use v5.18;

use B qw(svref_2object SVf_IOK SVf_NOK);
use Data::Dumper;
use TOML::Tiny::Grammar;
use TOML::Tiny::Util qw(is_strict_array);

my @KEYS;

sub to_toml {
  my $data = shift;
  my $param = ref($_[1]) eq 'HASH' ? $_[1] : undef;
  my @buff_assign;
  my @buff_tables;

  for (ref $data) {
    when ('HASH') {
      # Generate simple key/value pairs for scalar data
      for my $k (grep{ ref($data->{$_}) !~ /HASH|ARRAY/ } sort keys %$data) {
        my $key = to_toml_key($k);
        my $val = to_toml($data->{$k}, $param);
        push @buff_assign, "$key=$val";
      }

      # For values which are arrays, generate inline arrays for non-table
      # values, array-of-tables for table values.
      ARRAY: for my $k (grep{ ref $data->{$_} eq 'ARRAY' } sort keys %$data) {
        # Empty table
        if (!@{$data->{$k}}) {
          my $key = to_toml_key($k);
          push @buff_assign, "$key=[]";
          next ARRAY;
        }

        my @inline;
        my @table_array;

        # Sort table and non-table values into separate containers
        for my $v (@{$data->{$k}}) {
          if (ref $v eq 'HASH') {
            push @table_array, $v;
          } else {
            push @inline, $v;
          }
        }

        # Non-table values become an inline table
        if (@inline) {
          my $key = to_toml_key($k);
          my $val = to_toml(\@inline, $param);
          push @buff_assign, "$key=$val";
        }

        # Table values become an array-of-tables
        if (@table_array) {
          push @KEYS, $k;

          for (@table_array) {
            push @buff_tables, '', '[[' . join('.', map{ to_toml_key($_) } @KEYS) . ']]';
            push @buff_tables, to_toml($_);
          }

          pop @KEYS;
        }
      }

      # Sub-tables
      for my $k (grep{ ref $data->{$_} eq 'HASH' } sort keys %$data) {
        if (!keys(%{$data->{$k}})) {
          # Empty table
          my $key = to_toml_key($k);
          push @buff_assign, "$key={}";
        } else {
          # Generate [table]
          push @KEYS, $k;
          push @buff_tables, '', '[' . join('.', map{ to_toml_key($_) } @KEYS) . ']';
          push @buff_tables, to_toml($data->{$k}, $param);
          pop @KEYS;
        }
      }
    }

    when ('ARRAY') {
      if (@$data && $param->{strict_arrays}) {
        my ($ok, $err) = is_strict_array($data);
        die "toml: found heterogenous array, but strict_arrays is set ($err)\n" unless $ok;
      }

      push @buff_tables, '[' . join(', ', map{ to_toml($_, $param) } @$data) . ']';
    }

    when ('SCALAR') {
      if ($$_ eq '1') {
        return 'true';
      } elsif ($$_ eq '0') {
        return 'false';
      } else {
        push @buff_assign, to_toml($$_, $param);
      }
    }

    when (/JSON::PP::Boolean/) {
      return $$data ? 'true' : 'false';
    }

    when (/Types::Serializer::Boolean/) {
      return $data ? 'true' : 'false';
    }

    when (/DateTime/) {
      # TOML uses RFC3339 for datetimes, but supports a "local datetime"
      # which excludes the timezone offset. A DateTime with a floating
      # time zone indicates a TOML local datetime.
      #
      # DateTime::Format::RFC3339 requires a time zone, however, and defaults
      # to +00:00 for floating time zones. To support local datetimes in
      # output, format the datetime as RFC3339 and strip the timezone
      # when encountering a floating time zone.
      require DateTime::Format::RFC3339;

      my $dt = DateTime::Format::RFC3339->new->format_datetime($data);

      if ($data->time_zone_short_name eq 'floating') {
        $dt =~ s/\+00:00$//;
      }

      return $dt;
    }

    when ('Math::BigInt') {
      return $data->bstr;
    }

    when ('Math::BigFloat') {
      return $data->bstr;
    }

    when ('') {
      # Thanks to ikegami on Stack Overflow for the trick!
      # https://stackoverflow.com/questions/12686335/how-to-tell-apart-numeric-scalars-and-string-scalars-in-perl/12693984#12693984
      # note: this must come before any regex can flip this flag off
      return $data if svref_2object(\$data)->FLAGS & (SVf_IOK | SVf_NOK);
      return $data if $data =~ /$DateTime/;
      return to_toml_string($data);
    }

    default{
      die 'unhandled: '.Dumper($_);
    }
  }

  join "\n", @buff_assign, @buff_tables;
}

sub to_toml_key {
  my $str = shift;

  if ($str =~ /^[-_A-Za-z0-9]+$/) {
    return $str;
  }

  if ($str =~ /^"/) {
    return qq{'$str'};
  } else {
    return qq{"$str"};
  }
}

sub to_toml_string {
  state $escape = {
    "\n" => '\n',
    "\r" => '\r',
    "\t" => '\t',
    "\f" => '\f',
    "\b" => '\b',
    "\"" => '\"',
    "\\" => '\\\\',
    "\'" => '\\\'',
  };

  my ($arg) = @_;
  $arg =~ s/([\x22\x5c\n\r\t\f\b])/$escape->{$1}/g;
  $arg =~ s/([\x00-\x08\x0b\x0e-\x1f])/'\\u00' . unpack('H2', $1)/eg;

  return '"' . $arg . '"';
}

1;
