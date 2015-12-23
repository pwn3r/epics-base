#!/usr/bin/env perl
#*************************************************************************
# Copyright (c) 2013 UChicago Argonne LLC, as Operator of Argonne
#     National Laboratory.
# Copyright (c) 2002 The Regents of the University of California, as
#     Operator of Los Alamos National Laboratory.
# EPICS BASE is distributed subject to a Software License Agreement found
# in the file LICENSE that is included with this distribution. 
#*************************************************************************
#  Revision-Id: anj@aps.anl.gov-20130425220036-2d5pngyj0wk98nqs
#
# Creates a ctdt.c file of C++ static constructors and destructors,
# as required for all vxWorks binaries containing C++ code.

use strict;
use warnings;
use Getopt::Std;

our ($opt_o);

$Getopt::Std::OUTPUT_HELP_VERSION = 1;
&HELP_MESSAGE if !getopts('o:') || @ARGV != 1;

# Is exception handler frame info required?
my $need_eh_frame = 0;

# Is module destructor needed?
my $need_mod_dtor = 0;

# Constructor and destructor names:
#   Array contains names from input file.
#   Hash is used to skip duplicate names.
my (@ctors, %ctors);
my (@dtors, %dtors);

while (<>)
{
    chomp;
    $need_eh_frame++ if m/__? gxx_personality_v [0-9]/x;
    $need_mod_dtor++ if m/__? cxa_atexit $/x;
    next if m/__? GLOBAL_. (F | I._GLOBAL_.D) .+/x;
    if (m/__? GLOBAL_ . D .+/x) {
        my ($addr, $type, $name) = split ' ', $_, 3;
        push @dtors, $name unless exists $dtors{$name};
        $dtors{$name} = 1;
    }
    if (m/__? GLOBAL_ . I .+/x) {
        my ($addr, $type, $name) = split ' ', $_, 3;
        push @ctors, $name unless exists $ctors{$name};
        $ctors{$name} = 1;
    }
}

push my @out,
    '/* C++ static constructor and destructor lists */',
    '/* This is generated by munch.pl, do not edit! */',
    '',
    '#include <vxWorks.h>',
    '',
    '/* Declarations */',
    (map {cDecl($_)} @ctors, @dtors),
    '',
    'char __dso_handle = 0;',
    '';

moduleDestructor() if $need_mod_dtor;
exceptionHandlerFrame() if $need_eh_frame;

push @out,
    '/* List of Constructors */',
    'void (*_ctors[])(void) = {',
    (join ",\n", (map {'    ' . cName($_)} @ctors), '    NULL'),
    '};',
    '',
    '/* List of Destructors */',
    'void (*_dtors[])(void) = {',
    (join ",\n", (map {'    ' . cName($_)} @dtors), '    NULL'),
    '};',
    '';

if ($opt_o) {
    open(my $OUT, '>', $opt_o)
        or die "Can't create $opt_o: $!\n";
    print $OUT join "\n", @out;
    close $OUT
        or die "Can't close $opt_o: $!\n";
} else {
    print join "\n", @out;
}

# Outputs the C code for registering a module destructor
sub moduleDestructor {
    my $mod_dtor = 'mod_dtor';
    push @dtors, $mod_dtor;
    push @out,
        '/* Module destructor */',
        "static void $mod_dtor(void) {",
        '    extern void __cxa_finalize(void *);',
        '',
        '    __cxa_finalize(&__dso_handle);',
        '}',
        '';
}

# Outputs the C code for registering exception handler frame info
sub exceptionHandlerFrame {
    my $eh_ctor = 'eh_ctor';
    my $eh_dtor = 'eh_dtor';

    # Add EH ctor/dtor to _start_ of arrays
    unshift @ctors, $eh_ctor;
    unshift @dtors, $eh_dtor;

    push @out,
        '/* Exception handler frame */',
        'extern const unsigned __EH_FRAME_BEGIN__[];',
        '',
        "static void $eh_ctor(void) {",
        '    extern void __register_frame_info (const void *, void *);',
        '    static struct {',
        '        void *a, *b, *c, *d;',
        '        unsigned long e;',
        '        void *f, *g;',
        '    } object;',
        '',
        '    __register_frame_info(__EH_FRAME_BEGIN__, &object);',
        '}',
        '',
        "static void $eh_dtor(void) {",
        '    extern void *__deregister_frame_info (const void *);',
        '',
        '    __deregister_frame_info(__EH_FRAME_BEGIN__);',
        '}',
        '';
}

sub cName {
    my ($name) = @_;
    $name =~ s/^__/_/;
    $name =~ s/\./\$/g;
    return $name;
}

sub cDecl {
    my ($name) = @_;
    my $decl = 'extern void ' . cName($name) . '(void)';
    # 68k and MIPS targets allow periods in symbol names, which
    # can only be reached using an assembler string.
    if (m/\./) {
        $decl .= "\n    __asm__ (\"" . $name . "\");";
    } else {
        $decl .= ';';
    }
    return $decl;
}

sub HELP_MESSAGE {
    print STDERR "Usage: munch.pl [-o file_ctdt.c] file.nm\n";
    exit 2;
}
