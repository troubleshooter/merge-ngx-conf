#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4; cperl-continued-statement-offset: 4 -*-

use strict;
use warnings;
use 5.011;
use autodie;
use Getopt::Long;
use Pod::Usage;
our $VERSION = 1.00;

## User Options - Defaults
## Nest Level
my %NEST_LEVEL = (
    NEST_MIN => '1',
    NEST_MAX => '10',
    NEST_DEF => '5',
);

### DO NOT ALTER BELOW ###
## for F variables, 0 is off, 1 is on
my $F_ANN         = 0;
my $F_DOMAIN      = 0;
my $F_NOCOMMENTS  = 0;
my $F_NOEMPTY     = 0;
my $F_REPORT      = 0;
my $F_REPORT_ONLY = 0;

## Other defaults
my $COLON         = q{:};
my $CNT_INC_DIRS  = 0;           # count of directives
my $CNT_PROCESSED = 0;           # count of files processed
my $NEST_TYPE     = 'default';
my $REP_ON        = 0;
my $RPT_FILTER    = 'default';
my $LEVEL         = 0;

## Strings set from arguments & options
my $DOM_ABS;                     # set in command line args
my $NEST_LEVEL;
my $NEST_WARN;
my $NGX_ABS;
my $NGX_DIR;
my $OUTPUT_RE;
my $START_FILE;

## Regular Expressions
my $FILTER_RE = qr{
                    (
                    ^[#]
                    |[.]rules
                    |mime[.]types
                    )
                    }msx;    # default filter
my $MASK_RE    = qr/[*?]/ms;
my $INCLUDE_RE = qr{
                    ^
                    (\s+)?
                    include
                    \s+
                    (\S+)
                    \;
                    (.*)?
                    $
                    }msx;

## For report
my $r_cnt_calling    = '0';    # count of files with include directives
my $r_cnt_mask_dirs  = '0';    # count of directives with wildcard mask
my $r_cnt_mask_files = '0';    # count of files from wildcard masks
my $r_final_level    = '0';    # actual nesting level

## Strings used in various routines
my ( $c_file, $i_file, $line, $main_text );

## Arrays
my ( @directives, @eval_text, @mask_files, @r_flow, @warnings );

## Hashes
my (
    %processed, %to_process, %mask_files, %mask_text,    %r_files,
    %r_flow,    %r_match,    %r_relate,   %r_rev_relate, %sub_text
);

my %err_msgs = (
    err1 => 'The file referenced in the include directive could not be found.',
    err2 => 'The directory for the wildcard mask could not be opened.',
    err3 => 'Unknown option in the command line.',
);

## Subroutines
sub file_to_array;
sub get_directives;
sub handle_errs;
sub handle_opts;
sub mask_filelist;
sub process_directives;
sub r_begin;
sub r_file_list;
sub r_flow;
sub r_nesting;
sub r_relate;
sub r_stats;
sub text_assembly;
sub valid_args;
sub valid_opts;

########### Start ###########

## validate options
valid_opts;

## validate arguments and set some strings
## Returns: $NGX_DIR, $NGX_ABS, $DOM_ABS, $START_FILE, %to_process
valid_args;

PROCESS:
## initial data for nginx.conf and/or domain.conf loaded in %to_process
## during valid_args. Load data for all related files with final results
## in @directives, %processed, %to_process, %sub_text
while ( $LEVEL < $NEST_LEVEL ) {

    do {
        $LEVEL++;

        foreach my $c_file ( sort keys %to_process ) {
            get_directives($c_file);
            delete $to_process{$c_file};
        }
      }
}
## Add final %to_process files (if any) to %sub_text
if ( ( keys %to_process ) > 0 ) {
    foreach my $i_file ( keys %to_process ) {

        my $text_str;

        file_to_array($i_file);

        ## create string, add to hash
        $text_str = join q{ }, @eval_text;
        $sub_text{$i_file} .= $text_str if ( !exists $sub_text{$i_file} );
    }
}

ASSEMBLE:
## Assemble file text.  Skip if report only (-x, --report-only)
if ( 0 == $F_REPORT_ONLY ) {
    text_assembly;
}

REPORT:
if ( 1 == $REP_ON ) {

    my $r_separator = q{-} x '72';

    ## Header
    r_begin;

    ## Separator
    print "\n$r_separator\n\n";

    ## Nesting
    print "NESTING\n\n";

    r_nesting;

    ## Separator
    print "\n$r_separator\n\n";

    ## File and directive stats
    r_stats;

    ## Separator
    print "\n$r_separator\n\n";

    ## File list
    print "FILE LIST\n\n";
    r_file_list;

    ## Separator
    print "\n$r_separator\n\n";

    ## File relationship
    print "FILE RELATION\n";
    r_relate;

    ## Separator
    print "\n$r_separator\n\n";

    ## File flow
    print "FILE FLOW\n\n";
    r_flow;
}

OUTPUT:
## Print report end
if ( 1 == $F_REPORT ) {
    ## Report end
    print "\n\t\tASSEMBLED CONFIGURATION FILE BELOW\n";
    print q{#} x '72' . "\n\n";
}

## Print assembled file
if ( 0 == $F_REPORT_ONLY ) {
    ## Filter lines
    if ( 1 == $F_NOCOMMENTS or 1 == $F_NOEMPTY ) {
        my @lines = split /\n/ms, $main_text;
        foreach my $line (@lines) {
            print "$line\n" if ( $line !~ /$OUTPUT_RE/ms );
        }
    }
    ## Default
    else {
        print $main_text;
    }
}

## Print any warnings
if (@warnings) {
    print "The script generated some warnings:\n";

    foreach my $line (@warnings) {
        print "$line\n";
    }
}

exit;

#######################################################################
##                           Subroutines                             ##
#######################################################################
## Load file contents into array
## Usage: file_to_array(/path/to/file)
sub file_to_array {

    my $filename = shift;

    open my $FILE, '<', $filename;
    @eval_text = <$FILE>;
    close $FILE;

    return;
}

## Extract the directives from a file
## Usage:  get_directives($filename)
sub get_directives {

    my (
        $cnt_file_dirs, $cur_file,      $last_fs,  $mask,
        $mask_line,     $mask_inc_file, $new_line, $path,
        $r_line,        $text_str
    );

    $cur_file = shift;    # from %to_process

    ## File is marked as processed with count as key
    $CNT_PROCESSED++;
    $processed{$CNT_PROCESSED} .= $cur_file;

    ## get file contents, returns @eval_text
    file_to_array($cur_file);

    ## Create string, add to hash if not exists and is not first file
    $text_str = join q{ }, @eval_text;

    if ( $cur_file =~ m/$NGX_ABS/ms
        or ( 1 == $F_DOMAIN and $cur_file =~ m/$DOM_ABS/ms ) )
    {
        $main_text = $text_str;
    }
    else {
        $sub_text{$cur_file} .= $text_str if ( !exists $sub_text{$cur_file} );
    }

    #Find include directives, if any, and filter unwanted
    @eval_text = grep { $_ =~ m/$INCLUDE_RE/ms } @eval_text;
    @eval_text = grep { $_ !~ m/$FILTER_RE/ms } @eval_text;

    ## Count directives in @eval_text
    $cnt_file_dirs = @eval_text;
    $r_files{$cur_file} .= $cnt_file_dirs
      if ( 1 == $REP_ON and ( !exists $r_files{$cur_file} ) );

    ## Process any include directives
    if ( $cnt_file_dirs > 0 ) {

        ## For reports only
        if ( 1 == $REP_ON ) {
            $r_cnt_calling++;
            $r_final_level = $LEVEL;
        }

        foreach my $directive (@eval_text) {
            chomp $directive;
            process_directives( $cur_file, $directive );
        }
    }
    return;
}

## Handle config file errors
sub handle_errs {

    #    my @errs    = @_;
    my $err_num = shift;
    my $msg     = $err_msgs{$err_num};

    my ( $cur_file, $err_file, $err_path, $inc_dir, $path );

    if ( 'err1' eq $err_num or 'err2' eq $err_num ) {
        $err_file = shift;
        $cur_file = shift;
        $inc_dir  = shift;

        print "$msg\n";
        print "Calling file: $cur_file\n";
        print "Directive: $inc_dir\n";
        print "Referenced file missing: $err_file\n";
    }
    ## Command line options error
    if ( 'err3' eq $err_num ) {
        $err_path = shift;
        print "$msg\n";
        pod2usage( -verbose => 1 );
    }

    exit;
}

## Handle option values - called from valid_opts
sub handle_opts {
    my ( $opt_name, $opt_value ) = @_;

    ## Set filter
    if ( $opt_name =~ m/(^i$|^include$)/ms ) {
        if ( $opt_value =~ m/(mime|rules|all)/ms ) {
            $RPT_FILTER = $opt_value;

            $FILTER_RE = qr/(^#|[.]rules)/ms     if ( 'mime' eq $opt_value );
            $FILTER_RE = qr/(^#|mime[.]types)/ms if ( 'rules' eq $opt_value );
            $FILTER_RE = qr/^#/ms                if ( 'all' eq $opt_value );
        }
        else {
            pod2usage(
                -msg =>
"Invalid option value: $opt_value. Use mime, rules or all.\nExiting....\n",
                -verbose => 1,
                -exitval => 2
            );
        }
    }

    ## Nest level
    ## Need to force $LEVEL for nginx.conf and level 1
    ## otherwise the insertions aren't done.  So minimum level
    if ( $opt_name =~ m/(^n$|nest-level)/ms ) {

        $NEST_TYPE = 'custom';

        my $nest_min = $NEST_LEVEL{NEST_MIN};
        my $nest_max = $NEST_LEVEL{NEST_MAX};

        if ( $opt_value > $nest_max ) {
            $NEST_WARN =
"**Warning**: Nest level too high. $opt_value given. Script used $nest_max.";
            push @warnings, $NEST_WARN;
            $NEST_LEVEL = $nest_max;
        }
        elsif ( $opt_value < $nest_min ) {
            $NEST_WARN =
"**Warning**: Nest level too low. $opt_value given. Script used $nest_min.";
            push @warnings, $NEST_WARN;
            $NEST_LEVEL = $nest_min;
        }
        else {
            $NEST_LEVEL = $opt_value;
        }
    }
    ## Version
    if ( $opt_name =~ m/(^v$|^version$)/ms ) {
        print "merge-ngx-conf.pl $VERSION\n";
        exit;
    }
}

## Retrieve matching wildcard mask filenames
## Usage: mask_filelist($filename,$mask)
sub mask_filelist {
    my $path = shift;
    my $mask = shift;

    my @files;
    my $file;

    opendir DIR, $path;

    while ( $file = readdir DIR ) {

        # match wildcard mask
        if ( $file =~ m/$mask$/ms and -f "$path/$file" ) {
            push @files, $file;
        }
    }

    closedir DIR;

    ## Rename to @mask_files otherwise error
    @mask_files = @files;

    my $mask_cnt = @mask_files;

    if ( 0 == $mask_cnt ) {
        carp("No mask files matching $mask were found in $path.");
    }

    return;
}

## Called from get_directives if include
## directives are present in a file
## Usage: process_directives($cur_file,@eval_text);
sub process_directives {

    my $cur_file = shift;
    my $inc_dir  = shift;

    my ( $last_fs, $mask, $mask_inc_file, $new_line, $path, $r_line,
        $sort_key );

    ## count directives, used in $sort_key, report
    $CNT_INC_DIRS++;

    ## Extract inc_file name and change to absolute path
    $i_file = $inc_dir;
    $i_file =~ s/$INCLUDE_RE/$2/ms;

    $i_file = $NGX_DIR . $i_file if ( $i_file !~ m/^\//ms );

    ## Handle sites enabled - force $DOM_ABS to get processed
    $i_file = $DOM_ABS
      if ( $i_file =~ m/sites-enabled/ms and $cur_file eq $NGX_ABS );

    ## Build line and add to @directives
    $sort_key = "$CNT_PROCESSED-$LEVEL-$CNT_INC_DIRS";
    $new_line = "$sort_key:$cur_file:$inc_dir:$i_file";
    push @directives, $new_line;

    ## Handle wildcard masks
    ## Doesn't match mask
    if ( $i_file !~ m/$MASK_RE/ms ) {

        ## to process
        if ( -f $i_file ) {
            $to_process{$i_file}++;
            if ( 1 == $REP_ON ) {
                $r_relate{$LEVEL}{$cur_file}{$i_file}++;
                $r_rev_relate{$LEVEL}{$i_file}{$cur_file}++;
                $r_line = "$LEVEL:$cur_file:$i_file";
                push @r_flow, $r_line;
            }
        }
        else {
            handle_errs( 1, $i_file, $cur_file, $inc_dir );
        }
    }
    ## Matches mask
    else {
        $r_cnt_mask_dirs++ if ( 1 == $REP_ON );
        ## extract the mask
        $last_fs = rindex $i_file, q{/};
        $path = substr $i_file, 0, ( $last_fs + 1 );
        $mask = substr $i_file, ( $last_fs + 1 );

        $mask =~ s/[*]/\.\*/msg;    # sub for *
        $mask =~ s/[?]/\./msg;      # sub for ?

        # get matching files from directory
        if ( -d $path ) {
            mask_filelist( $path, $mask );    # returns @mask_files
        }
        else {
            handle_errs( 2, $path, $cur_file, $inc_dir );
        }
        ## process @mask_files from mask_filelist()
        ## filename only is returned
        foreach my $mask_line (@mask_files) {

            # increment count
            $r_cnt_mask_files++;

            # add directory to the filename
            $mask_inc_file = $path . $mask_line;
            ## add to hashes
            $mask_files{$i_file}{$mask_inc_file}++
              if ( !exists $mask_files{$i_file}{$mask_inc_file} );

            $to_process{$mask_inc_file}++;
            if ( 1 == $REP_ON ) {
                $r_relate{$LEVEL}{$cur_file}{$mask_inc_file}++;
                $r_line = "$LEVEL:$cur_file:$mask_inc_file";
                push @r_flow, $r_line;
            }
        }
    }
    return;
}

## Report section - Header
sub r_begin {
    my $r_time = localtime;

    ## Header
    print "\n\nNginx Configuration Report\n";
    print "generated: $r_time\n\n";

    print "Configuration directory: $NGX_DIR\n";
    print "Starting file:\t\t $START_FILE\n";

    ## Directives filter
    print "Filtered: mime.types and naxsi .rules excluded\n"
      if ( 'default' eq $RPT_FILTER );
    print "Filtered: naxsi .rules directives excluded\n"
      if ( 'mime' eq $RPT_FILTER );
    print "Filtered: mime.types excluded\n" if ( 'rules' eq $RPT_FILTER );
    print "Filtered: none\n"                if ( 'all' eq $RPT_FILTER );

    return;
}

## Report section - Print file list
sub r_file_list {
    my $r_file;
    ## Calling files
    print "Files with include directives \(relative to $NGX_DIR\):\n";
    print "\(count of processed directives - filename\)\n\n";

    foreach my $c_file ( sort keys %r_files ) {
        if ( $r_files{$c_file} > 0 ) {
            $r_file = $c_file;
            $r_file =~ s/$NGX_DIR//ms;

            printf "%5d - %s \n", $r_files{$c_file}, $r_file
              if ( $r_files{$c_file} > 0 );

            $r_match{$c_file}++
              if ( $c_file ne $NGX_ABS and $c_file ne $DOM_ABS );
        }
    }

    ## Include only files
    print "\nFiles without include directives \(relative to $NGX_DIR\):\n\n";
    foreach my $i_file ( sort keys %r_files ) {
        $r_file = $i_file;
        $r_file =~ s/$NGX_DIR//ms;
        print "  --$r_file\n" if ( 0 == $r_files{$i_file} );
    }
    return;
}

## Report section - File Flow
sub r_flow {

    my ( $c_file1, $i_file1, $line1, $r_level, $r_level1 );
    my %r_remove;
    ## This takes care of matches at multiple levels
    foreach my $c_file (%r_match) {
        foreach my $line (@r_flow) {
            next if $line !~ m/:$c_file:/ms;
            my ( $level, $subst, $inc ) = split $COLON, $line, '3';
            $r_remove{$line}++;
            foreach my $line1 (@r_flow) {
                next if ( $line1 !~ m/:$c_file$/ms );
                $line1 = $line1 . ' <-- ' . $inc;
            }
        }
    }

    ## Copy to new array for substitution
    my @r_flow_print = @r_flow;

    ## This takes care of level 1 matches
    foreach my $line ( sort @r_flow ) {
        chomp $line;
        next if ( $line !~ m/^1:/ms );
        ( $r_level, $c_file, $i_file ) = split $COLON, $line, '3';

        foreach my $line1 (@r_flow_print) {
            chomp $line1;
            next if ( $line1 !~ m/^\d+:$i_file:/ms );
            next if ( exists $r_remove{$line1} );

            ( $r_level1, $c_file1, $i_file1 ) = split $COLON, $line1, '3';
            ## Since we're substituting in the $inc_file $line1
            ## rather than the $call_file $line, we need to remove
            ## the $inc_file line later.
            $r_remove{$line}++;
            $line1 = $line . $COLON . $i_file1;
        }
    }

    ## Remove substituted lines and clean up text
    foreach my $line (@r_flow_print) {
        chomp $line;
        next if ( exists $r_remove{$line} );

        # remove $r_level:
        $line =~ s/^\d+://ms;

        # sub for :
        $line =~ s/:/ <-- /msg;

        # sub for directory
        $line =~ s/$NGX_DIR//msg;
        $r_flow{$line}++;
    }

    foreach my $line ( sort keys %r_flow ) {
        print "$line\n";
    }

    return;
}

## Report section -  Nesting
sub r_nesting {

    my $r_nest_msg;

    ## set the message
    if ( 0 == ( keys %to_process ) ) {
        $r_nest_msg =
            qq{The level set was sufficient to process *all*\n}
          . q{unfiltered include directives.};
    }
    else {
        $r_nest_msg =
            qq{Unfiltered include directives were processed to the level\n}
          . qq{set. Additional include directive(s) were not processed.\n}
          . qq{Consider increasing the nesting level using -n option if\n}
          . qq{you want all levels to be processed.\n};
    }

    print "$NEST_WARN\n\n" if ( defined $NEST_WARN );

    print "Nest level used:\t$NEST_LEVEL \($NEST_TYPE\)\n";
    print "Actual nest level:\t$r_final_level\n\n";

    print $r_nest_msg;

    return;
}

## Report section - File Relation
sub r_relate {

    my $r_level;
    my $r_file;

    foreach my $r_level ( sort keys %r_relate ) {

        print "\nLevel $r_level";

        foreach my $c_file ( keys %{ $r_relate{$r_level} } ) {

            ## Calling file
            $r_file = $c_file;
            $r_file =~ s/$NGX_DIR//ms;
            print "\n  $r_file\n";

            ## Include files
            foreach my $i_file ( sort keys %{ $r_relate{$r_level}{$c_file} } ) {

                #               $r_file = $i_file;
                $i_file =~ s/$NGX_DIR//ms;
                print "\t<-- $i_file\n";
            }
        }
    }
    return;
}

## Report section - Stats
sub r_stats {
    ## get unique count of files
    my %r_uniq     = reverse %processed;
    my $r_uniq_cnt = scalar keys %r_uniq;

    print "STATS\n\n";

    print "Unique files in configuration:\t\t$r_uniq_cnt\n\n";

    print "Total files processed:\t\t\t$CNT_PROCESSED\n";
    print "-- containing include directives:\t$r_cnt_calling\n";
    print "-- from wildcard mask(s):\t\t$r_cnt_mask_files\n";

    print "\nTotal include directives processed:\t$CNT_INC_DIRS\n";
    print "-- with wildcard mask:\t\t\t$r_cnt_mask_dirs\n";

    return;
}

## Assemble file text
sub text_assembly {

    my $directive;

    ## Assemble mask file strings first
    if ( ( keys %mask_files ) > 0 ) {

        foreach my $c_file ( sort keys %mask_files ) {

            foreach my $i_file ( sort keys %{ $mask_files{$c_file} } ) {
                my $mask_text_str = q{};
                my $text_str      = q{};
                if ( 1 == $F_ANN ) {
                    $mask_text_str =
"\nINSERT FROM:\t$i_file\n$sub_text{$i_file}\nINSERT END:\t$i_file\n";
                    $text_str = "$text_str\n$mask_text_str";
                }
                else {
                    $mask_text_str = $sub_text{$i_file};
                    $text_str      = "$text_str\n$mask_text_str";
                }
                $mask_text{$c_file} .= $text_str;
            }
        }
    }

    ## Match directives and insert text
    foreach my $line ( sort @directives ) {
        chomp $line;

        my ( $match_qstr, $sort_key, $text_str );

        ( $sort_key, $c_file, $directive, $i_file ) = split $COLON, $line, '4';
        $match_qstr = quotemeta $directive;

        ## Handle sites-enabled
        if ( $directive =~ m/sites-enabled/msi ) {
            $text_str = $sub_text{$i_file};
        }
        ## Handle masks
        elsif ( exists $mask_text{$i_file} ) {

            # create sub_text_str from all files
            $text_str = $mask_text{$i_file};
        }
        ## All other files
        else {
            $text_str = $sub_text{$i_file};
        }
        ## Annotate or not
        if ( 1 == $F_ANN ) {
            my $begin_str = "\n\tINSERT FROM:\t$i_file";
            my $end_str   = "\n\tINSERT END:\t$i_file";
            $main_text =~ s/$match_qstr/$begin_str\n$text_str$end_str\n/ms;
        }
        else {
            $main_text =~ s/$match_qstr/\n$text_str\n/ms;
        }
    }
    return;
}

## Check for valid arguments
## Usage: valid_args;
sub valid_args {

    $DOM_ABS = $ARGV[0];

    ## Extract config directory and test filenames and path
    ## Valid domain.conf file
    if ( -f $DOM_ABS ) {
        $NGX_DIR = $DOM_ABS;
        $NGX_DIR =~ s/^(.*\/)sites-available\/.*/$1/msx;
    }
    else {
        pod2usage(
            -msg => "The domain configuration file $DOM_ABS can't be found.",
            -verbose => 0,
            -exitval => 2
        );
        exit;
    }
    ## Valid nginx.conf file
    $NGX_ABS = $NGX_DIR . 'nginx.conf';
    if ( !-f $NGX_ABS ) {
        pod2usage(
            -msg     => "The nginx.conf file $NGX_ABS can't be found.",
            -verbose => 0,
            -exitval => 2
        );
        exit;
    }
    ## Set output filter
    if ( 1 == $F_NOCOMMENTS or 1 == $F_NOEMPTY ) {

        $OUTPUT_RE = qr{
                        (
                        ^[#]
                        |^\s+[#]
                        )
                        }msx
          if ( 1 == $F_NOCOMMENTS );

        $OUTPUT_RE = qr{
                        (
                        ^$
                        |^\s+$
                        )
                        }msx
          if ( 1 == $F_NOEMPTY );

        $OUTPUT_RE = qr{
                        (
                        ^[#]
                        |^\s+[#]
                        |^$
                        |^\s+$
                        )
                        }msx
          if ( 1 == $F_NOCOMMENTS and 1 == $F_NOEMPTY );
    }

    ## Set start file
    if ( 0 == $F_DOMAIN ) {
        $START_FILE = $NGX_ABS;
        $to_process{$NGX_ABS}++;
    }
    else {
        $START_FILE = $DOM_ABS;
        $to_process{$DOM_ABS}++;
    }

    ## Set report trigger
    if ( 1 == $F_REPORT or 1 == $F_REPORT_ONLY ) {
        $REP_ON = 1;
    }
    return;
}

## Validate options
## Usage: valid_opts;
sub valid_opts {

    my $HELP = 0;    # Show help overview
    my $MAN  = 0;    # Show manual

    $NEST_LEVEL = $NEST_LEVEL{NEST_DEF};    # set default

    Getopt::Long::Configure('bundling');

    eval {
        GetOptions(
            'i|include:s'    => \&handle_opts,
            'n|nest-level:i' => \&handle_opts,
            'v|version'      => \&handle_opts,
            'h|help'         => \$HELP,
            'm|manual'       => \$MAN,
            'd|domain'       => \$F_DOMAIN,
            'c|no-comments'  => \$F_NOCOMMENTS,
            'e|no-empty'     => \$F_NOEMPTY,
            'a|annotate'     => \$F_ANN,
            'r|report'       => \$F_REPORT,
            'x|report-only'  => \$F_REPORT_ONLY
        );
    } or handle_errs('err3');

    ## Help
    pod2usage( -verbose => 0 ) if $HELP;

    ## Manual
    pod2usage(
        -noperldoc => 1,
        -verbose   => 2
    ) if $MAN;

    ## No argument
    pod2usage(
        -msg     => "No argument in the command line. Script exiting....\n",
        -verbose => 0
    ) if ( 0 == @ARGV );

    ## Too many arguments
    pod2usage(
        -msg => "Too many arguments in the command line. Script exiting....\n",
        -verbose => 0
    ) if ( 1 < @ARGV );

    return;
}

__END__

=pod

=head1 NAME

merge-ngx-conf.pl - Assemble a set of nginx configuration files

=head1 USAGE

merge-ngx-conf.pl F</path/sites-available/filename>

merge-ngx-conf.pl [B<-dcearxhmv>] [B<-n> I<N>] [B<-i> I<value>] F</path/sites-available/filename>

NOTE: Path I<must> be an absolute path and include the sites-available subdirectory.

Examples:

 merge-ngx-conf.pl /path/sites-available/domain.conf
 merge-ngx-conf.pl -dac /path/sites-available/domain.conf
 merge-ngx-conf.pl -n 3 -i rules /path/sites-available/domain.conf
 merge-ngx-conf.pl -x /path/sites-available/domain.conf
 merge-ngx-conf.pl -x -i mime -n 4 /path/sites-available/domain.conf

For explanations of the above, see the EXAMPLES section of the manual.

B<Help Options:>

B<-h>, B<--help>     Show the help information and exit.

B<-m>, B<--manual>   Show the manual and exit.

B<-v>, B<--version>  Show the version number and exit.

=head1 DESCRIPTION

This Perl script outputs an assembled nginx configuration file.  

It was developed on a Debian Wheezy server with Perl v5.14.2 so any 
examples below use F</etc/nginx> as the configuration directory. 
Substitute yours.

=head2 Normal Usage

Using F<nginx.conf> and F<domain.conf> (or just F<domain.conf>), the
script iterates through the include directives of the files and inserts
the text from the referenced file. It handles wildcard masks and follows
include directives down multiple levels (i.e. nested levels). It will
also follow referenced files in directories external to the nginx
configuration directory.

Output is the assembled configuration file with an optional report to
E<lt>STDOUTE<gt>.

The script does not write to any file or alter existing files in any
way so I would consider it safe to use on a production system. In fact,
the script doesn't even care if nginx is running. What it does care
about is that the directory structure has at a minimum:

  /some_directory/nginx.conf
  /some_directory/sites-available/domain.conf

Several options are included to limit the output to the domain
configuration only, to vary the format of the output, to create a
report, etc. Please read, at the very minimum, the Nested Files section
below which applies to the B<-n> option.

=head3 Nested Files

The use of nginx include directives makes for cleaner configuraion
files.  Directives repeated numerous times across other files can be
written once and then inserted wherever needed.  It also unclutters
the configuration file by allowing a particularly lengthy configuration
section (like F<mime-types>) to be inserted.  

Complex configurations can contain many include directives, with some
files referenced in the include directive containg include directives
themselves.  In essence, the include directives are "nested".  It then
becomes increasingly difficult to pinpoint the source of a problem as
you may have to go several "nest levels" down.

See L<nginx documentation for include
directives|http://nginx.org/en/docs/ngx_core_module.html#include> for
further information.

An example of nested files:

The file, F<nginx.conf> (calling file), contains the following include
directive:

    include   example.conf;

The file, F<example.conf> (included file), also contains an include
directive as well.  F<example.conf> becomes the calling file.

    include   nest.conf; # This is a nested include directive

In this example, F<nest.conf> (included file) is inserted into
F<example.conf> and then the altered F<example.conf> is inserted into
F<nginx.conf>.

    nginx.conf <-- example.conf <-- nest.conf

By default, the script will follow include directives to 5 levels. The
option 'B<-n> I<N>' (where 'I<N>' is a number) alters the default
behavior. Please set this to a sane option as the value controls a do
loop. The script does contain a hard-coded limit of 10, just in case. If
the include directives are nested to a level higher than 10, you'll need
to modify the script itself (see the Modifying Nest Limits section
below). A level of 0 is useless and is disabled.

At the default level of 5 for nesting, the included files from
F<nginx.conf> are level 1. (This includes F<domain.conf>.) Files included
from F<domain.conf> and any nested included files from F<nginx.conf> are
level 2 and so forth. 

An example:

                Level 1                    Level 2           Level 3
nginx.conf <-- test1.conf                  <-- test2.conf    <-- test3.conf
nginx.conf <-- sites-available/domain.conf <-- fastcgi_params

This flow diagram is best read from right to left. In line 1,
F<test3.conf> is called by F<test2.conf> which is called by F<test1.conf>
which is called by F<nginx.conf>. Files are nested to the third level. In
line 2, F<fastcgi_params> is called by F<domain.conf> which is called by
F<nginx.conf>. These files are nested to the second level.

With the B<-r> or B<-x> option, the script outputs a report, detailing
the level of include directives processed and whether any include
directives weren't processed because the nest level was set too low.

=head2 Modifying Nest Limits

The defaults for nest limits are set in the %NEST_LIMIT hash at the
beginning of the script. To change the defaults, modify the hash values.

=head2 Advanced Features

A variety of options exist.  Please see the OPTIONS section below.

=head1 REQUIRED ARGUMENTS

The only required argument is a domain configuration file. The path must
be absolute and include I<sites-available>, i.e.

    /etc/nginx/sites-available/domain.conf

=head1 OPTIONS

=head2 General

For options with no value, the options may be bundled, i.e. B<-dcear>.

=head2 Help Options

=over 4

=item B<-h>, B<--help>

Show the brief help information and exit.

=item B<-m>, B<--manual>

Read the manual, with examples and exit.

=item B<-v>, B<--version>

Show the version number and exit.

=back

=head2 Expand or Limit Processing Options

=over 4

=item B<-d>, B<--domain>

Default - process both F<nginx.conf> and F<domain.conf>

Limit processing to F<domain.conf> (excludes F<nginx.conf>). Only
include directives in F<domain.conf> and any referenced files in
F<domain.conf> will be followed, including any nested files.

=item B<-i> I<value>, B<--include> I<value>

Default - exclude F<mime.types> and naxsi F<.rules> files from
processing

Use this option to include what you want. Values are 'mime' (include
F<mime.types>), 'rules' (include naxsi F<.rules> files) or 'all' (include
both F<mime.types> and naxsi F<.rules> files).

=item  B<-n> I<N>, B<--nest-level> I<N>

Default is 5.  Minimum is 1 and maximum is 10.

The default of 5 is a reasonably sane option for most nginx
configurations. A hard-coded limit of 10 exists since the value controls
a do loop. If you need more than 10 levels of nesting, perhaps it's time
to rethink your configuration or change the script. 

=back

=head2 Output Format Options

Default ouput keeps comments and empty lines with no annotation.

=over 4

=item B<-c>, B<--no-comments>

Remove comments from the output.

=item B<-e>, B<--no-empty>

Remove empty lines from the output.

=item B<-a>, B<--annotate>

Mark the beginning and end of inserted file contents in output.

    Example of annotation:
        INSERT FROM: /etc/nginx/sites-available/domain.conf
        some text
        some text
        some text
        INSERT END: /etc/nginx/sites-available/domain.conf

=back

=head2 Report Options

Default is no report.

=over 4

=item B<-r>, B<--report>

Output a report before the assembled configuration file. See the L</REPORT>
section for an example and explanation of a report.

=item B<-x>, B<--report-only>

Outputs only the report. Overrides B<-c>, B<-e> and B<-a>. Does not
override B<-n> and B<-i> options. In other words, it may be used in
conjunction with B<-d>, B<-n> and B<-i> options. 

=back

=head1 EXAMPLES

  The following are examples of this script:

  merge-ngx-conf.pl /path/sites-available/domain.conf
  
  Run with all defaults:
    * no report,
    * both nginx.conf and domain.conf included and followed,
    * mime.types and naxsi .rules files excluded,
    * default nest level of 5 used,
    * comments, empty lines kept, and
    * no annotation.
  
  merge-ngx-conf.pl -dac /path/sites-available/domain.conf
  
  Run for domain.conf only with annotations added and comments removed.
    * no report,
    * nginx.conf excluded,
    * domain.conf included and followed,
    * mime.types and naxsi .rules files excluded,
    * default nest level of 5 used, and
    * empty lines kept.

  merge-ngx-conf.pl -n 3 -i rules /path/sites-available/domain.conf
  
  Run with a nest level of 3 and include naxsi .rules files
    * no report,
    * both nginx.conf and domain.conf included and followed,
    * mime.types excluded,
    * comments, empty lines kept, and
    * no annotation.
 
  merge-ngx-conf.pl -x /path/sites-available/domain.conf
  
  Only report is output.
    * both nginx.conf and domain.conf included and followed,
    * mime.types and naxsi .rules files excluded, and
    * default nest level of 5 used.
  
  merge-ngx-conf.pl -x -i mime -n 4 /path/sites-available/domain.conf
  
    Only report is output, with data limited to a nest level of 4 and
    mime.types is included.  
    * both nginx.conf and domain.conf included and followed, and 
    * naxsi .rules files excluded.
  
  merge-ngx-conf.pl -h  Read help
  merge-ngx-conf.pl -m  Read manual
  merge-ngx-conf.pl -v  Show version

=head1 DIAGNOSTICS

Here, %s represents information that will vary. B<(F)> indicates a fatal
message and the script will exit. B<(W)> indicates a warning message and
the script will continue.

=head2 Processing errors

While processing the include directives from a file, the following
messages may be displayed.

=over 4

=item B<The file referenced in the include directive could not be found.>

B<(F)> The file referenced in the include directive currently being
processed by the script doesn't exist in the location specified by the
include directive. Check your configuration files for any reference to
the file indicated in the error message and ensure that the file exists
and that the path to the file is set correctly.

The name of the file with the include directive, the include directive
and the file name that couldn't be found will print out below the
message.

 Calling file: %s
 Directive: %s
 Referenced file missing: %s

=item B<The directory for the wildcard mask could not be opened.>

B<(F)> The directory referenced in an include directive with a wildcard
mask couldn't be found. Check your configuration files for any reference
to the directory indicated in the error message and ensure that the
directory exists and that the path is set correctly.

The name of the file with the wildcard include directive, the include
directive and the file name that couldn't be found will print out below
the message.

 Calling file: %s
 Directive: %s
 Referenced file missing: %s

=item B<Unable to open file referenced in directive.>

B<(F)> The file name that couldn't be opened will print out below the message.

 File name: %s

=item B<Unable to open directory while processing wildcard mask.>

B<(F)> The directory that couldn't be opened will print out below the message.

 Directory: %s

=item B<Unable to close file %s>

B<(W)> The script was unable to close the file it had opened.

=item B<Couldn't close directory %s while processing wildcard mask>

B<(W)> The script was unable to close the directory it had opened.

=back

=head2 Command line options and arguments errors

The following messages relate to command line options and arguments.

=over 4

=item B<Unknown option in the command line>

B<(F)> A usage message will print. Check the manual for a more extensive
explanation of valid options.

=item B<Invalid option value: %s. Use mime, rules or all.>

B<(F)> Check the manual for valid option values. for the B<-i>, B<--include> option.

=item B<Too many arguments in the command line>

B<(F)> Only one argument is necessary - the absolute path to the domain
configuration file.

=item B<No argument in the command line>

B<(F)> One argument must be supplied (except with B<-h, -m or -v> options) - the
absolute path to the domain configuration file.

=item B<The domain configuration file %s can't be found>

B<(F)> The script was unable to locate the domain configuration file
supplied on the command line. Check to ensure the file exists and the
path was spelled correctly.

=item B<The nginx.conf file %s can't be found>

B<(F)>The script was unable to locate the nginx.conf file. Check to ensure the
file exists.

=item B<Warning: Nest level too high. %s given. Script using default %s.>

(W) The script continues using a nest level of 10, the default maximum
level unless you have changed the values in the %nest_level hash. In
this case, the script will default to the maximum level you set.

=item B<Warning: Nest level too low. %s given. Script using default %s.>

B<(W)> The script will continue using a nest level of 1, the default
minimum level unless you have changed the values in the %nest_level
hash. In this case, the script will default to the minimum level you
set.

=back

=head1 REPORT

An example of the report is included in the README.md.
L<Github|https://github.com/troubleshooter/merge-ngx-conf>  

=head2 Header Section

This section of the report displays the:

=over 4

=item * local time the report was generated,

=item * configuration directory used,

=item * starting file

either nginx.conf or example.domain.conf if run with the B<-d> option

=item * include directives that were filtered:

With the default, the message that displays is:

    "mime.types and naxsi .rules excluded"

When using the B<-i> option, the message that displays for the value:

  mime      "naxsi .rules directives excluded"
  rules     "mime.types excluded"
  all       "none"

Commented include directives are always filtered.

=back

=head2 Nesting Section

This section displays the:

=over 4

=item * nest level used by the script.

This may be the default of 5 or changed with the B<-n> I<N> switch. The
maximum level is 5 and the minimum level is 1. When a value out of this
range is given, the script will default to either 1 if B<-n> I<0> was
used or 10 if B<-n> I<E<gt>10> was used.

=item * actual nest level the script found, and a

=item * message indicating whether all unfiltered directives were
processed at the nest level used.

If all unfiltered directives were processed, this message appears:

The level set was sufficient to process *all* unfiltered include directives.

If all the unfiltered directives were not processed, this message
appears:

Unfiltered include directives were processed to the level set.
Additional include directive(s) were not processed. Consider
increasing the nesting level using the B<-n> option if you want
all levels to be processed.

Note that if you intentionally set the nest level using the B<-n> option
to a lower level, this message may still appear. If your intention was
to limit output to a certain level only, then you can ignore this
message. For example, you might only want to see the output for
nginx.conf include directives only. In this case, setting B<-n I<1>>
will give you that information but will cause the message to appear.

=back

=head2 Stats Section

The script will process a file each time it appears in an include
directive so if the same file is referenced in more than one include
directive, it is counted twice. This is necessary because a file may be
included at different nesting levels. 

B<Special treatment of sites-enabled include directive:> As stated in
Note 1 below, the sites-enabled wildcard mask is not counted as a
wildcard mask, however the include directive itself is counted. The
files count from wildcard masks does not count F<example.domain.conf>.

=head2 File List Section

This section lists the files with include directives, including the
count of the filtered directives that were processed, and files with
no include directives.

=head2 File Relation Section

This section lists the relation of the files at each level of nesting.

=head2 File Flow Section

This section attempts to present a view of how the files "flow" into one
another. 

A file may be included in another file more than once. For example,
F<example.domain.conf> may have several include directives referencing
F<fastcgi_params>. The file flow does not represent the number of times
a file may be included so F<fastcgi_params> will appear only once.

=head2 Report Tips and Tricks

Assemble F<nginx.conf> only - use B<-n I<1>> option

Assemble F<example.domain.conf> only - use B<-d -n I<1>>' options

=head1 EXIT STATUS

The script will exit with 0 if successful.

=head1 CONFIGURATION

Configuration is done entirely through command line options.  There is
no associated configuration file.

=head1 DEPENDENCIES

This script uses only core Perl modules.

=head1 INCOMPATIBILITIES

No known incompatibilities.

=head1 BUGS AND LIMITATIONS

The minimum required version is Perl v5.11.0.

The script assumes the standard nginx directory structure:

=over 4

=item 1. Nginx configuration files under a base directory.

=item 2. The domain configuration file located in the sites-available/
subdirectory.

=back

What you see is what your include directives have indicated should
happen. If something looks off, check your include directives first
before filing a bug report.

For example, a file can be included multiple times within another file.
Often, this is the intention. However, a file can be inadvertantly
included twice. For example, if you used a wildcard mask to
include all files in a subdirectory and one of those files contains an
include directive referencing a file in that same subdirectory, the file
will be included twice.

Was that your intention? The script won't know. It just puts everything
where the configuration files tell it to.

Please report any bugs or feature requests through the web interface
at L<GitHub|https://github.com/troubleshooter/merge-ngx-conf>.

=head1 NOTES

=over 4

=item 1. sites-enabled/*

The sites-enabled/* wildcard mask is not treated as a wildcard mask by
the script because the domain configuration file is substituted there.
In any report generated, the wildcard mask count will not include this
directive. Additionally, any file counts for wildcard masks will not
include example.domain.conf.

=item 2. Commented include directives are I<never processed>.

=back

=head1 AUTHOR

Terry Roy
--
https://github.com/troubleshooter/merge-ngx-conf

=head1 LICENSE AND COPYRIGHT

Copyright 2014-to present Terry Roy

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://dev.perl.org/licenses/artistic.html

=head1 DISCLAIMER OF WARRANTY

This software is provided "as is" and you use at your own risk.

See http://dev.perl.org/licenses/artistic.html

=cut
