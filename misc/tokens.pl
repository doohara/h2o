#! /bin/sh
exec perl -x $0 "$@"
#! perl

# Copyright (c) 2014 DeNA Co., Ltd.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

use strict;
use warnings;
use List::Util qw(max);
use List::MoreUtils qw(uniq);
use Text::MicroTemplate;

use constant LICENSE => << 'EOT';
/*
 * Copyright (c) 2014 DeNA Co., Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */
EOT

my %tokens;
my (@hpack, @qpack);

while (my $line = <DATA>) {
    chomp $line;
    last if $line eq '';
    next if $line =~ /^#/;
    my ($hpack_index, $proxy_should_drop_for_req, $proxy_should_drop_for_res, $is_init_header_special, $is_hpack_special, $copy_for_push_request, $dont_compress, $likely_to_repeat, $name, $value) =
        split /\s+/, $line, 10;
    die "unexpected input:$line"
        if $name eq '';
    $tokens{$name} = [ $hpack_index, $proxy_should_drop_for_req, $proxy_should_drop_for_res, $is_init_header_special, $is_hpack_special, $copy_for_push_request, $dont_compress, $likely_to_repeat ]
        unless defined $tokens{$name};
    if ($hpack_index != 0) {
        $hpack[$hpack_index - 1] = [ $name, $value ];
    }
}

while (my $line = <DATA>) {
    chomp $line;
    last if $line eq '';
    next if $line =~ /^#/;
    my ($qpack_index, $name, $value) = split /\s+/, $line, 3;
    $value = '' unless defined $value;
    die "unexpected input:$line"
        if $name eq '';
    die "missing entry in token table: $name $value"
        unless defined $tokens{$name};
    $qpack[$qpack_index] = [$name, $value];
}

my @tokens = map { [ $_, @{$tokens{$_}} ] } uniq sort keys %tokens;

# generate include/h2o/token_table.h
open my $fh, '>', 'include/h2o/token_table.h'
    or die "failed to open include/h2o/token_table.h:$!";
print $fh render(<< 'EOT', \@tokens, \@hpack, \@qpack, LICENSE)->as_string;
? my ($tokens, $hpack, $qpack, $license) = @_;
<?= $license ?>
/* DO NOT EDIT! generated by tokens.pl */
#ifndef h2o__token_table_h
#define h2o__token_table_h

? for my $i (0..$#$tokens) {
#define <?= normalize_name($tokens->[$i][0]) ?> (h2o__tokens + <?= $i ?>)
? }

extern const h2o_hpack_static_table_entry_t h2o_hpack_static_table[<?= scalar @$hpack ?>];
extern const h2o_qpack_static_table_entry_t h2o_qpack_static_table[<?= scalar @$qpack ?>];

typedef int32_t (*h2o_qpack_lookup_static_cb)(h2o_iovec_t value, int *is_exact);
extern const h2o_qpack_lookup_static_cb h2o_qpack_lookup_static[<?= scalar @$tokens ?>];

? for (my $token_index = 0; $token_index < @$tokens; ++$token_index) {
int32_t <?= qpack_lookup_funcname($tokens->[$token_index][0]) ?>(h2o_iovec_t value, int *is_exact);
? }

#endif
EOT
close $fh;

# generate lib/common/token_table.h
open $fh, '>', 'lib/common/token_table.h'
    or die "failed to open lib/core/token_table.h:$!";
print $fh render(<< 'EOT', \@tokens, \@hpack, \@qpack, LICENSE)->as_string;
? my ($tokens, $hpack, $qpack, $license) = @_;
<?= $license ?>
/* DO NOT EDIT! generated by tokens.pl */
h2o_token_t h2o__tokens[] = {
? for my $i (0..$#$tokens) {
    { { H2O_STRLIT("<?= $tokens->[$i][0] ?>") }, { <?= join(", ", map { $tokens->[$i][$_] } (1..$#{$tokens->[$i]})) ?> } }<?= $i == $#$tokens ? '' : ',' ?>
? }
};
size_t h2o__num_tokens = <?= scalar @$tokens ?>;

const h2o_hpack_static_table_entry_t h2o_hpack_static_table[<?= scalar @$hpack ?>] = {
? for my $i (0..$#$hpack) {
    { <?= normalize_name($hpack->[$i][0]) ?>, { H2O_STRLIT("<?= $hpack->[$i][1] // "" ?>") } }<?= $i == $#$hpack ? "" : "," ?>
? }
};

const h2o_qpack_static_table_entry_t h2o_qpack_static_table[<?= scalar @$qpack ?>] = {
? for my $i (0..$#$qpack) {
    { <?= normalize_name($qpack->[$i][0]) ?>, { H2O_STRLIT("<?= $qpack->[$i][1] // "" ?>") } }<?= $i == $#$qpack ? "" : "," ?>
? }
};

const h2o_token_t *h2o_lookup_token(const char *name, size_t len)
{
    switch (len) {
? for my $len (uniq sort { $a <=> $b } map { length $_->[0] } @$tokens) {
    case <?= $len ?>:
        switch (name[<?= $len - 1 ?>]) {
?  my @tokens_of_len = grep { length($_->[0]) == $len } @$tokens;
?  for my $end (uniq sort map { substr($_->[0], length($_->[0]) - 1) } @tokens_of_len) {
        case '<?= $end ?>':
?   my @tokens_of_end = grep { substr($_->[0], length($_->[0]) - 1) eq $end } @tokens_of_len;
?   for my $token (@tokens_of_end) {
            if (memcmp(name, "<?= substr($token->[0], 0, length($token->[0]) - 1) ?>", <?= length($token->[0]) - 1 ?>) == 0)
                return <?= normalize_name($token->[0]) ?>;
?   }
            break;
?  }
        }
        break;
? }
    }

    return NULL;
}

? for (my $token_index = 0; $token_index < @$tokens; ++$token_index) {
int32_t <?= qpack_lookup_funcname($tokens->[$token_index][0]) ?>(h2o_iovec_t value, int *is_exact)
{
?     my $first_index = -1;
?     for (my $i = 0; $i < @$qpack; $i++) {
?         next if $qpack->[$i][0] ne $tokens->[$token_index][0];
?         $first_index = $i if $first_index == -1;
    if (h2o_memis(value.base, value.len, H2O_STRLIT("<?= $qpack->[$i][1] ?>"))) {
        *is_exact = 1;
        return <?= $i ?>;
    }
?     }
    *is_exact = 0;
    return <?= $first_index ?>;
}

? }
const h2o_qpack_lookup_static_cb h2o_qpack_lookup_static[<?= scalar @$tokens ?>] = {
    <?= join ",", map { qpack_lookup_funcname($_->[0]) } @$tokens ?>
};
EOT
close $fh;

sub normalize_name {
    my $n = shift;
    $n =~ s/^://;
    $n =~ s/-/_/g;
    $n =~ tr/a-z/A-Z/;
    "H2O_TOKEN_$n";
}

sub qpack_lookup_funcname {
    my $n = shift;
    $n =~ s/^://;
    $n =~ s/-/_/g;
    "h2o_qpack_lookup_$n";
}

sub render {
    my $mt = Text::MicroTemplate->new(
        template    => shift,
        escape_func => undef,
    );
    $mt->build->(@_);
}

__DATA__
# Meaning of the fields:
# - HTTP/2 static table index (non-zero if present)
# - Proxy should drop in request
# - Proxy should drop in response
# - Is init header special
# - Is HPACK special
# - Copy for push request
# - Disable compression (non-zero)
# - Likely to repeat (for QPACK)
1 0 0 0 0 0 0 1 :authority
2 0 0 0 0 0 0 0 :method GET
3 0 0 0 0 0 0 0 :method POST
4 0 0 0 0 0 0 0 :path /
5 0 0 0 0 0 0 0 :path /index.html
6 0 0 0 0 0 0 0 :scheme http
7 0 0 0 0 0 0 0 :scheme https
8 0 0 0 0 0 0 0 :status 200
9 0 0 0 0 0 0 0 :status 204
10 0 0 0 0 0 0 0 :status 206
11 0 0 0 0 0 0 0 :status 304
12 0 0 0 0 0 0 0 :status 400
13 0 0 0 0 0 0 0 :status 404
14 0 0 0 0 0 0 0 :status 500
15 0 0 0 0 1 0 1 accept-charset
16 0 0 0 0 1 0 1 accept-encoding gzip, deflate
17 0 0 0 0 1 0 1 accept-language
18 0 0 0 0 0 0 1 accept-ranges
19 0 0 0 0 1 0 1 accept
20 0 0 0 0 0 0 1 access-control-allow-origin
21 0 0 0 0 0 0 0 age
22 0 0 0 0 0 0 1 allow
23 0 0 0 0 0 0 0 authorization
24 0 0 0 0 0 0 1 cache-control
25 0 0 0 0 0 0 1 content-disposition
26 0 0 0 0 0 0 1 content-encoding
27 0 0 0 0 0 0 1 content-language
28 0 0 1 1 0 0 0 content-length
29 0 0 0 0 0 0 0 content-location
30 0 0 0 0 0 0 0 content-range
31 0 0 0 0 0 0 1 content-type
32 0 0 0 0 0 1 0 cookie
33 0 0 0 0 0 0 1 date
34 0 0 0 0 0 0 0 etag
35 0 0 1 0 0 0 1 expect
36 0 0 0 0 0 0 0 expires
37 0 0 0 0 0 0 1 from
38 0 0 1 1 0 0 0 host
39 0 0 0 0 0 0 0 if-match
40 0 0 0 0 0 0 0 if-modified-since
41 0 0 0 0 0 0 0 if-none-match
42 0 0 0 0 0 0 0 if-range
43 0 0 0 0 0 0 0 if-unmodified-since
44 0 0 0 0 0 0 0 last-modified
45 0 0 0 0 0 0 1 link
46 0 0 0 0 0 0 0 location
47 0 0 0 0 0 0 0 max-forwards
48 1 0 0 0 0 0 0 proxy-authenticate
49 1 0 0 0 0 0 0 proxy-authorization
50 0 0 0 0 0 0 0 range
51 0 0 0 0 0 0 1 referer
52 0 0 0 0 0 0 0 refresh
53 0 0 0 0 0 0 1 retry-after
54 0 0 0 0 0 0 1 server
55 0 0 0 0 0 1 0 set-cookie
56 0 0 0 0 0 0 1 strict-transport-security
57 1 1 1 1 0 0 0 transfer-encoding
58 0 0 0 0 1 0 1 user-agent
59 0 0 0 0 0 0 1 vary
60 0 0 0 0 0 0 0 via
61 0 0 0 0 0 0 0 www-authenticate
62 0 0 0 0 0 0 0 :protocol
0 1 1 0 1 0 0 0 connection
0 0 0 0 0 0 0 0 x-reproxy-url
0 1 1 1 1 0 0 0 upgrade
0 1 0 0 1 0 0 0 http2-settings
0 1 0 0 1 0 0 1 te
0 1 1 0 0 0 0 0 keep-alive
0 0 0 0 0 0 0 1 x-forwarded-for
0 0 0 0 0 0 0 0 x-traffic
0 0 0 0 1 0 0 0 cache-digest
0 0 0 0 0 0 0 0 x-compress-hint
0 0 0 0 0 0 0 0 early-data
0 0 0 0 0 0 0 1 access-control-allow-headers
0 0 0 0 0 0 0 1 x-content-type-options
0 0 0 0 0 0 0 1 x-xss-protection
0 0 0 0 0 0 0 0 access-control-allow-credentials
0 0 0 0 0 0 0 1 access-control-allow-headers
0 0 0 0 0 0 0 1 access-control-allow-methods
0 0 0 0 0 0 0 1 access-control-expose-headers
0 0 0 0 0 0 0 1 access-control-request-headers
0 0 0 0 0 0 0 1 access-control-request-method
0 0 0 0 0 0 0 1 alt-svc clear
0 0 0 0 0 0 0 1 content-security-policy
0 0 0 0 0 0 0 1 expect-ct
0 0 0 0 0 0 0 1 forwarded
0 0 0 0 0 0 0 1 origin
0 0 0 0 0 0 0 1 purpose
0 0 0 0 0 0 0 1 timing-allow-origin
0 0 0 0 0 0 0 1 upgrade-insecure-requests
0 0 0 0 0 0 0 1 x-frame-options
0 0 0 0 0 0 0 1 priority
0 0 0 0 0 0 0 1 no-early-hints
0 1 1 0 1 0 0 0 datagram-flow-id
0 1 1 0 0 0 0 0 proxy-connection

# QPACK static table (index, name, value)
0 :authority
1 :path /
2 age 0
3 content-disposition
4 content-length 0
5 cookie
6 date
7 etag
8 if-modified-since
9 if-none-match
10 last-modified
11 link
12 location
13 referer
14 set-cookie
15 :method CONNECT
16 :method DELETE
17 :method GET
18 :method HEAD
19 :method OPTIONS
20 :method POST
21 :method PUT
22 :scheme http
23 :scheme https
24 :status 103
25 :status 200
26 :status 304
27 :status 404
28 :status 503
29 accept */*
30 accept application/dns-message
31 accept-encoding gzip, deflate, br
32 accept-ranges bytes
33 access-control-allow-headers cache-control
34 access-control-allow-headers content-type
35 access-control-allow-origin *
36 cache-control max-age=0
37 cache-control max-age=2592000
38 cache-control max-age=604800
39 cache-control no-cache
40 cache-control no-store
41 cache-control public, max-age=31536000
42 content-encoding br
43 content-encoding gzip
44 content-type application/dns-message
45 content-type application/javascript
46 content-type application/json
47 content-type application/x-www-form-urlencoded
48 content-type image/gif
49 content-type image/jpeg
50 content-type image/png
51 content-type text/css
52 content-type text/html; charset=utf-8
53 content-type text/plain
54 content-type text/plain;charset=utf-8
55 range bytes=0-
56 strict-transport-security max-age=31536000
57 strict-transport-security max-age=31536000; includesubdomains
58 strict-transport-security max-age=31536000; includesubdomains; preload
59 vary accept-encoding
60 vary origin
61 x-content-type-options nosniff
62 x-xss-protection 1; mode=block
63 :status 100
64 :status 204
65 :status 206
66 :status 302
67 :status 400
68 :status 403
69 :status 421
70 :status 425
71 :status 500
72 accept-language
73 access-control-allow-credentials FALSE
74 access-control-allow-credentials TRUE
75 access-control-allow-headers *
76 access-control-allow-methods get
77 access-control-allow-methods get, post, options
78 access-control-allow-methods options
79 access-control-expose-headers content-length
80 access-control-request-headers content-type
81 access-control-request-method get
82 access-control-request-method post
83 alt-svc clear
84 authorization
85 content-security-policy script-src 'none'; object-src 'none'; base-uri 'none'
86 early-data 1
87 expect-ct
88 forwarded
89 if-range
90 origin
91 purpose prefetch
92 server
93 timing-allow-origin *
94 upgrade-insecure-requests 1
95 user-agent
96 x-forwarded-for
97 x-frame-options deny
98 x-frame-options sameorigin
