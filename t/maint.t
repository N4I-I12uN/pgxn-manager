#!/usr/bin/env perl -w

use 5.12.0;
use utf8;
use Test::More tests => 79;
#use Test::More 'no_plan';
use Test::File;
use File::Path qw(remove_tree);
use File::Basename qw(basename);
use Test::MockModule;
use lib 't/lib';
use TxnTest;

my $CLASS;

BEGIN {
    $CLASS = 'PGXN::Manager::Maint';
    use_ok $CLASS or die;
}

can_ok $CLASS => qw(
    new
    go
    run
    verbosity
    workdir
    update_stats
    reindex
    reindex_all
    _write_json_to
    DEMOLISH
    _pod2usage
    _config
);

my $tmpdir = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');
my $root   = PGXN::Manager->new->config->{mirror_root};

END {
    remove_tree $tmpdir, $root;
}

##############################################################################
# Instantiate and test config.
my $maint = new_ok $CLASS;
my %defopts = (
    help      => undef,
    man       => undef,
    verbosity => 0,
    version   => undef,
);

DEFAULT: {
    local @ARGV;
    is_deeply { $maint->_config }, \%defopts,
        'Default options should be correct';
}

##############################################################################
# Test run().
RUN: {
    my $mocker = Test::MockModule->new($CLASS);
    my $params;
    $mocker->mock(update_stats => sub { shift; $params = \@_ });
    ok $maint->run('update_stats'), 'Run update_stats';
    is_deeply $params, [], 'Should have called update_stats method';

    # Try a dashed command.
    ok $maint->run('update-stats', 'now'), 'Run update-stats';
    is_deeply $params, ['now'], 'Should have called update_stats';

    # Make sure we croak for an unknown command.
    local $@;
    eval { $maint->run('nonexistent') };
    like $@, qr{PGXN Maint: "nonexistent" is not a command},
        'Should get an error for an unknown command';
};

##############################################################################
# Tetst go().
GO: {
    my $mocker = Test::MockModule->new($CLASS);
    my $params;
    $mocker->mock(run => sub { shift; $params = \@_ });
    local @ARGV = qw(--verbose update_stats now);
    ok $maint->go, 'Go!';
    is_deeply $params, [qw(update_stats now)],
        'Should have called run with command and args';

    # Try with a dashed task.
    @ARGV = qw(--verbose update-stats now);
    ok $maint->go, 'Go!';
    is_deeply $params, [qw(update-stats now)],
        'Should have called run with command and args';
};

##############################################################################
# Okay, we need some distributions in the database.
my $user = TxnTest->user; # Create user.
PGXN::Manager->instance->conn->run(sub {
    my $dbh = shift;
    $dbh->do(
        'SELECT * FROM add_distribution(?, ?, ?)',
        undef, $user, 'the-sha1-hash',
        '{
        "name": "pair",
        "version": "0.0.01",
        "license": "postgresql",
        "maintainer": "theory",
        "abstract": "Ordered pair",
        "description": "An ordered pair for PostgreSQL",
        "tags": ["foo", "bar", "baz"],
        "no_index": null,
        "provides": {
            "pair": { "file": "pair.sql.in", "version": "0.02.02" },
            "trip": { "file": "trip.sql.in", "version": "0.02.01" }
        },
        "tags": ["foo", "bar", "baz"],
        "release_status": "testing",
        "resources": {
          "homepage": "http://pgxn.org/dist/pair/"
        }
    }'
    );
    $dbh->do(
        'SELECT * FROM add_distribution(?, ?, ?)',
        undef, $user, 'the-sha1-hash2',
        '{
        "name": "pair",
        "version": "0.0.2",
        "license": "postgresql",
        "maintainer": "theory",
        "abstract": "Ordered pair",
        "description": "An ordered pair for PostgreSQL",
        "tags": ["foo", "bar", "baz"],
        "no_index": null,
        "tags": ["foo", "bar", "baz", "yo"],
        "provides": {
            "pair": { "file": "pair.sql.in", "version": "0.2.2" },
            "trip": { "file": "trip.sql.in", "version": "0.2.2" }
        },
        "release_status": "testing",
        "resources": {
          "homepage": "http://pgxn.org/dist/pair/"
        }
    }'
    );

    $dbh->do(
        'SELECT * FROM add_distribution(?, ?, ?)',
        undef, $user, 'the-sha1-hash3',
        '{
        "name":        "foo",
        "version":     "0.0.2",
        "license":     "postgresql",
        "maintainer":  "strongrrl",
        "abstract":    "whatever",
        "tags": ["Foo", "PAIR", "pair"]
    }'
    );

    $dbh->do(
        'SELECT * FROM add_distribution(?, ?, ?)',
        undef, $user, 'the-sha1-hash4',
        '{
        "name":        "bar",
        "version":     "0.3.2",
        "license":     "postgresql",
        "maintainer":  "someone else",
        "abstract":    "whatever"
    }'
    );
});

##############################################################################
# Test update_stats().
my %files = map { join('/', @{ $_ }) => File::Spec->catfile($root, @{ $_ } ) } (
   ['stats', 'tag.json'      ],
   ['stats', 'user.json'     ],
   ['stats', 'extension.json'],
   ['stats', 'dist.json'     ],
   ['stats', 'summary.json'  ],
);
file_not_exists_ok $files{$_}, "File $_ should not yet exist" for keys %files;

# Generate 'em.
ok $maint->update_stats, 'Update the stats';
file_exists_ok $files{$_}, "File $_ should now exist" for keys %files;

##############################################################################
# Test reindex(). First, we need some distributions.
REINDEX: {
    my $mocker = Test::MockModule->new('PGXN::Manager::Distribution');
    my $pgz = File::Spec->catfile($root, qw(dist pair 0.0.1 pair-0.0.1.pgz));
    $mocker->mock(reindex => sub {
        my $dist = shift;
        pass 'Distribution->reindex should be called';
        is $dist->archive, $pgz, 'Dist should have archive';
        is $dist->basename, 'pair-0.0.1.pgz', 'Dist should have basename';
        is $dist->creator, $user, 'Dist should have user as creator';
    });

    ok $maint->reindex('pair', '0.0.1'), 'Reindex pair 0.0.1';

    # Reindex two different distributions.
    my $pgz2 = File::Spec->catfile($root, qw(dist foo 0.0.2 foo-0.0.2.pgz));
    my @exp = ($pgz, $pgz2);

    $mocker->mock(reindex => sub {
        my $dist = shift;
        pass 'Distribution->reindex should be called';
        my $exp = shift @exp;
        my $base = basename($exp);
        is $dist->archive, $exp, "Dist $base should have archive";
        is $dist->basename, $base, "Dist $base should have basename";
        is $dist->creator, $user, "Dist $base should have user as creator";

    });

    ok $maint->reindex( pair => '0.0.1', foo => '0.0.2' ),
        'Reindex pair 0.0.1 and foo 0.0.2';

    # Make sure we warn for an unknown release.
    local $SIG{__WARN__} = sub {
        is shift, "nonexistent 0.0.1 is not a known release\n",
            'Should get warning for non-existant distribution';
    };
    ok $maint->reindex(nonexistent => '0.0.1'), 'Reindex nonexistent release';
}

##############################################################################
# Test reindex_all.

REINDEX: {
    my $pgz1 = File::Spec->catfile($root, qw(dist bar 0.3.2 bar-0.3.2.pgz));
    my $pgz2 = File::Spec->catfile($root, qw(dist foo 0.0.2 foo-0.0.2.pgz));
    my $pgz3 = File::Spec->catfile($root, qw(dist pair 0.0.2 pair-0.0.2.pgz));
    my $pgz4 = File::Spec->catfile($root, qw(dist pair 0.0.1 pair-0.0.1.pgz));

    # Reindex *everything*.
    my $mocker = Test::MockModule->new('PGXN::Manager::Distribution');
    my @exp = ($pgz1, $pgz2, $pgz3, $pgz4);
    $mocker->mock(reindex => sub {
        my $dist = shift;
        pass 'Distribution->reindex should be called';
        my $exp = shift @exp;
        my $base = basename($exp);
        is $dist->archive, $exp, "Dist $base should have archive";
        is $dist->basename, $base, "Dist $base should have basename";
        is $dist->creator, $user, "Dist $base should have user as creator";
    });

    ok $maint->reindex_all, 'Reindex everything';

    # Just reindex all pair distributions.
    @exp = ($pgz3, $pgz4);
    ok $maint->reindex_all('pair'), 'Reindex all pairs';

    # Reindex named distros.
    @exp = ($pgz2, $pgz3, $pgz4);
    ok $maint->reindex_all('pair', 'foo'), 'Reindex all pairs and foos';
}
