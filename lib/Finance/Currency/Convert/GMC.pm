package Finance::Currency::Convert::GMC;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Exporter 'import';
our @EXPORT_OK = qw(get_currencies convert_currency);

our %SPEC;

my $url = "https://www.gmc.co.id/";

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Convert currency using GMC (Golden Money Changer) website',
    description => <<"_",

This module can extract currency rates from the Golden Money Changer website:

    $url

Currently only conversions from a few currencies to Indonesian Rupiah (IDR) are
available.

_
};

$SPEC{get_currencies} = {
    v => 1.1,
    summary => 'Extract data from GMC page',
    result => {
        description => <<'_',
Will return a hash containing key `currencies`.

The currencies is a hash with currency symbols as keys and prices as values.

Tha values is a hash with these keys: `buy` and `sell`.

_
    },
};
sub get_currencies {
    require Mojo::DOM;
    require Parse::Date::Month::ID;
    #require Parse::Number::ID;
    require Parse::Number::EN;
    require Time::Local;

    my %args = @_;

    #return [543, "Test parse failure response"];

    my $page;
    if ($args{_page_content}) {
        $page = $args{_page_content};
    } else {
        require Mojo::UserAgent;
        my $ua = Mojo::UserAgent->new;
        my $tx = $ua->get($url);
        unless ($tx->success) {
            my $err = $tx->error;
            return [500, "Can't retrieve GMC page ($url): ".
                        "$err->{code} - $err->{message}"];
        }
        $page = $tx->res->body;
    }

    my $dom  = Mojo::DOM->new($page);

    my %currencies;
    my $tbody = $dom->find("table#rate-table tbody")->[0];
    $tbody->find("tr")->each(
        sub {
            my $row0 = shift;
            my $row = $row0->find("td")->map(
                sub { $_->text })->to_array;
            #use DD; dd $row;
            next unless $row->[0] =~ /\A[A-Z]{3}\z/;
            $currencies{$row->[0]} = {
                buy  => Parse::Number::EN::parse_number_en(text=>$row->[1]),
                sell => Parse::Number::EN::parse_number_en(text=>$row->[2]),
            };
        }
    );

    if (keys %currencies < 3) {
        return [543, "Check: no/too few currencies found"];
    }

    my $mtime;
  GET_MTIME: {
        unless ($page =~ m!</table>\s*<br>\s*<a>((\d+)-(\w+) (\d+):(\d+))</a>!s) {
            log_warn "Cannot extract last update time";
            last;
        }
        my $mon = Parse::Date::Month::ID::parse_date_month_id(text=>$3) or do {
            log_warn "Cannot recognize month name '$3' in last update time '$1'";
            last;
        };
        my $now = time();
        my $year = (localtime $now)[5];
        # the web page doesn't show year, pick year that will result in nearest
        # time to current time
        my $time1 = Time::Local::timegm(0, $5, $4, $2, $mon-1, $year  ) - 7*3600;
        my $time2 = Time::Local::timegm(0, $5, $4, $2, $mon-1, $year-1) - 7*3600;
        if (abs($time1 - $now) < abs($time2 - $now)) {
            $mtime = $time1;
        } else {
            $mtime = $time2;
        }
    }

    # XXX parse update dates (mtime_er, mtime_ttc, mtime_bn)
    [200, "OK", {
        mtime => $mtime,
        currencies => \%currencies,
    }];
}

# used for testing only
our $_get_res;

$SPEC{convert_currency} = {
    v => 1.1,
    summary => 'Convert currency using GMC',
    description => <<'_',

Currently can only handle conversion `to` IDR. Dies if given other currency.

Will warn if failed getting currencies from the webpage.

Currency rate is not cached (retrieved from the website every time). Employ your
own caching.

Will return undef if no conversion rate is available for the requested currency.

Use `get_currencies()`, which actually retrieves and scrapes the source web
page, if you need the more complete result.

_
    args => {
        n => {
            schema=>'float*',
            req => 1,
            pos => 0,
        },
        from => {
            schema=>'str*',
            req => 1,
            pos => 1,
        },
        to => {
            schema=>'str*',
            req => 1,
            pos => 2,
        },
        which => {
            summary => 'Select which rate to use (default is `sell`)',
            schema => ['str*', in=>['buy', 'sell']],
            default => 'sell',
            pos => 3,
        },
    },
    args_as => 'array',
    result_naked => 1,
};
sub convert_currency {
    my ($n, $from, $to, $which) = @_;

    $which //= 'sell';

    if (uc($to) ne 'IDR') {
        die "Currently only conversion to IDR is supported".
            " (you asked for conversion to '$to')\n";
    }

    unless ($_get_res) {
        $_get_res = get_currencies();
        unless ($_get_res->[0] == 200) {
            warn "Can't get currencies: $_get_res->[0] - $_get_res->[1]\n";
            return undef;
        }
    }

    my $c = $_get_res->[2]{currencies}{uc $from} or return undef;

    my $rate;
    #if ($which =~ /\Aavg_(.+)/) {
    #    $rate = ($c->{"buy_$1"} + $c->{"sell_$1"}) / 2;
    #} else {
    $rate = $c->{$which};
    #}

    $n * $rate;
}

1;
# ABSTRACT:

=head1 SYNOPSIS

 use Finance::Currency::Convert::GMC qw(convert_currency);

 printf "1 USD = Rp %.0f\n", convert_currency(1, 'USD', 'IDR');

=cut
