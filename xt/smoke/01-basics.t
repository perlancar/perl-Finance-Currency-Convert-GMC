#!perl

use 5.010;
use strict;
use warnings;

use Perinci::Import 'Finance::Currency::Convert::GMC',
    get_currencies => {exit_on_error=>1};
use Test::More 0.98;

my $res = get_currencies();
is($res->[0], 200, "get_currencies() succeeds")
    or diag explain $res;

done_testing;
