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
    BUILD_REQUIRES =>
        { 'Test::More' => 0, 'Test::More' => 1.001003, 'Test::Most' => 0.33, },
    PREREQ_PM => {
        'Amazon::SNS'                  => '1.3',
        'Amazon::SQS::Simple'          => '2.03',
        'AnyEvent'                     => '7.07',
        'CgtConfig'                    => '1.0',
        'Data::Dumper'                 => '2.121_08',
        'Data::UUID'                   => '1.217',
        'EV'                           => '4.17',
        'JSON'                         => '2.53',
        'MongoDB'                      => 'v0.704.1.0',
        'MongoDB::OID'                 => 'v0.704.1.0',
        'Moose'                        => '2.1209',
        'Moose::Util::TypeConstraints' => '2.1209',
        'MooseX::Storage'              => '0.46',
        'Readonly'                     => '1.04',
        'Scalar::Util'                 => '1.21',
        'Try::Tiny'                    => '0.11',
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES    => 'Replay-*' },
);
