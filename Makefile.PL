use 5.8.8;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME               => 'Replay',
    AUTHOR             => q{David Ihnen <davidihnen@gmail.com>},
    VERSION_FROM       => 'lib/Replay.pm',
    ABSTRACT_FROM      => 'lib/Replay.pm',
    LICENSE            => 'Artistic_2_0',
    PL_FILES           => {},
    MIN_PERL_VERSION   => 5.8.8,
    CONFIGURE_REQUIRES => { 'ExtUtils::MakeMaker' => 0, },
    TEST_REQUIRES      => {
        'Test::Continuous'  => 0,
        'Test::Mock::Class' => 0,
        'Test::MockObject'  => 1.20161202,
        'Test::More'        => 1.001003,
        'Test::Most'        => 0.33,
        'Test::Pod' => 1.22,
        'Test::Pod::Coverage' => 1.08,
    },
    PREREQ_PM => {
        'AnyEvent'                             => '7.12',
        'Carp'                                 => '1.3301',
        'Data::Dumper'                         => '2.121_08',
        'Data::UUID'                           => '1.217',
        'Digest::MD5'                          => '2.36',
        'EV'                                   => '4.17',
        'File::Spec'                           => '3.40',
        'JSON'                                 => '2.53',
        'JSON::Any'                            => '1.29',
        'List::Util'                           => '1.21',
        'Moose'                                => '2.1209',
        'Moose::Util::TypeConstraints'         => '2.1209',
        'MooseX::MetaDescription::Meta::Trait' => '0.06',
        'MooseX::Storage'                      => '0.46',
        'Perl::Version'                        => '1.013',
        'POSIX'                                => '1.09',
        'Readonly'                             => '1.04',
        'Scalar::Util'                         => '1.21',
        'Storable'                             => '2.45',
        'Time::HiRes'                          => '1.9717',
        'Try::Tiny'                            => '0.11',
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES    => 'Replay-*' },
);
