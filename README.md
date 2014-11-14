# NAME

merge-ngx-conf.pl - Assemble a set of nginx configuration files

# USAGE

merge-ngx-conf.pl `/path/sites-available/filename`

merge-ngx-conf.pl \[__\-dcearxhmv__\] \[__\-n__ _N_\] \[__\-i__ _value_\] `/path/sites-available/filename`

NOTE: Path _must_ be an absolute path and include the sites-available subdirectory.

Examples:

    merge-ngx-conf.pl /path/to/sites-available/domain.conf
    merge-ngx-conf.pl -dac /path/to/sites-available/domain.conf
    merge-ngx-conf.pl -n 3 -i rules /path/to/sites-available/domain.conf
    merge-ngx-conf.pl -x /path/to/sites-available/domain.conf
    merge-ngx-conf.pl -x -i mime -n 4 /path/to/sites-available/domain.conf

For explanations of the above, see the EXAMPLES section of the manual.

__Help Options:__

__\-h__, __\--help__     Show the help information and exit.

__\-m__, __\--manual__   Show the manual and exit.

__\-v__, __\--version__  Show the version number and exit.

# DESCRIPTION

This Perl script outputs an assembled nginx configuration file.

It was developed on a Debian Wheezy server with Perl v5.14.2 so any examples below use `/etc/nginx` as the configuration directory. Substitute yours.

## Normal Usage

Using `nginx.conf` and `domain.conf` (or just `domain.conf`), the script iterates through the include directives in the files and inserts the text from the referenced file. 

The script handles wildcard masks and follows include directives down multiple levels (i.e. nested levels). It will also follow referenced files in directories external to the nginx configuration directory.

Output is the assembled configuration file with an optional report to \<STDOUT>.

The script does not write to any file or alter existing files in any way so I would consider it safe to use on a production system. In fact, the script doesn't even care if nginx is running. What it does care about is that the directory structure has, at a minimum:

    /some_directory/nginx.conf
    /some_directory/sites-available/domain.conf

Several options are included to limit the output to the domain configuration only, to vary the format of the output, to create a report, etc. 

### Nested Files

The use of nginx include directives makes for cleaner configuraion files. Directives repeated numerous times across other files can be written once and then inserted wherever needed.  It also unclutters the configuration file by allowing a particularly lengthy configuration section (like `mime-types`) to be inserted.

Complex configurations can contain many include directives, with some files referenced in the include directive containg include directives themselves.  In essence, the include directives are "nested".  It then becomes increasingly difficult to pinpoint the source of a problem as you may have to go several "nest levels" down.

See [nginx documentation for include directives](http://nginx.org/en/docs/ngx\_core\_module.html\#include) for further information.

An example of nested files:

The file, `nginx.conf` (calling file), contains the following include directive:

    include   example.conf;

The file, `example.conf` (included file), also contains an include directive as well.  `example.conf` becomes the calling file.

    include   nest.conf; # This is a nested include directive

In this example, `nest.conf` (included file) is inserted into `example.conf` and then the altered `example.conf` is inserted into `nginx.conf`.

    nginx.conf <-- example.conf <-- nest.conf

By default, the script will follow include directives to 5 levels. The option '__\-n__ _N_' (where '_N_' is a number) alters the default behavior. Please set this to a sane option as the value controls a do loop. The script does contain a hard-coded limit of 10, just in case. If the include directives are nested to a level higher than 10, you'll need to modify the script itself (see the Modifying Nest Limits section below). A level of 0 is useless and is disabled.

At the default level of 5 for nesting, the included files from `nginx.conf` are level 1. (This includes `domain.conf`.) Files included from `domain.conf` and any nested included files from `nginx.conf` are level 2 and so forth.

An example:

                Level 1                    	Level 2           Level 3
	nginx.conf <-- test1.conf              	<-- test2.conf    <-- test3.conf
	nginx.conf <-- sites-available/domain.conf <-- fastcgi_params

This flow diagram is best read from right to left. In line 1, `test3.conf` is called by `test2.conf` which is called by `test1.conf` which is called by `nginx.conf`. Files are nested to the third level. In line 2, `fastcgi\_params` is called by `domain.conf` which is called by `nginx.conf`. These files are nested to the second level.

With the __\-r__ or __\-x__ option, the script outputs a report, detailing the level of include directives processed and whether any include directives weren't processed because the nest level was set too low. 
## Modifying Nest Limits

The defaults for nest limits are set in the %NEST\_LIMIT hash at the beginning of the script. To change the defaults, modify the hash values.

## Advanced Features

A variety of options exist.  Please see the OPTIONS section below.

# REQUIRED ARGUMENTS

The only required argument is a domain configuration file. The path must be absolute and include _sites-available_, i.e.

    /etc/nginx/sites-available/domain.conf

# OPTIONS

## General

For options with no value, the options may be bundled, i.e. __\-dcear__.

## Help Options

- __\-h__, __\--help__

Show the brief help information and exit.

- __\-m__, __\--manual__

Read the manual, with examples and exit.

- __\-v__, __\--version__

Show the version number and exit.

## Expand or Limit Processing Options

- __\-d__, __\--domain__

Default - process both `nginx.conf` and `domain.conf`

Limit processing to `domain.conf` (excludes `nginx.conf`). Only include directives in `domain.conf` and any referenced files in `domain.conf` will be followed, including any nested files.

- __\-i__ _value_, __\--include__ _value_

Default - exclude `mime.types` and naxsi `.rules` files from processing

Use this option to include what you want. Values are 'mime' (include `mime.types`), 'rules' (include naxsi `.rules` files) or 'all' (include both `mime.types` and naxsi `.rules` files).

- __\-n__ _N_, __\--nest-level__ _N_

Default is 5.  Minimum is 1 and maximum is 10.

The default of 5 is a reasonably sane option for most nginx configurations. A hard-coded limit of 10 exists since the value controls a do loop. If you need more than 10 levels of nesting, perhaps it's time to rethink your configuration or change the script.

## Output Format Options

Default ouput keeps comments and empty lines with no annotation.

- __\-c__, __\--no-comments__

Remove comments from the output.

- __\-e__, __\--no-empty__

Remove empty lines from the output.

- __\-a__, __\--annotate__

Mark the beginning and end of inserted file contents in output.

    Example of annotation:
        INSERT FROM: /etc/nginx/sites-available/domain.conf
        some text
        some text
        some text
        INSERT END: /etc/nginx/sites-available/domain.conf

## Report Options

Default is no report.

- __\-r__, __\--report__

Output a report before the assembled configuration file. See the ["REPORT"](#REPORT) section for an example and explanation of a report.

- __\-x__, __\--report-only__

Outputs only the report. Overrides __\-c__, __\-e__ and __\-a__. Does not override __\-n__ and __\-i__ options. In other words, it may be used in conjunction with __\-d__, __\-n__ and __\-i__ options.

# EXAMPLES

The following are examples of this script:

Run with all defaults

    merge-ngx-conf.pl /path/to/sites-available/domain.conf

      * no report,
      * both nginx.conf and domain.conf included and followed,
      * mime.types and naxsi .rules files excluded,
      * default nest level of 5 used,
      * comments, empty lines kept, and
      * no annotation.

Run for domain.conf only with annotations added and comments removed.

    merge-ngx-conf.pl -dac /path/to/sites-available/domain.conf

      * no report,
      * nginx.conf excluded,
      * domain.conf included and followed,
      * mime.types and naxsi .rules files excluded,
      * default nest level of 5 used, and
      * empty lines kept.

Run with a nest level of 3 and include naxsi .rules files.

    merge-ngx-conf.pl -n 3 -i rules /path/to/sites-available/domain.conf

- no report,
- both nginx.conf and domain.conf included and followed,
- mime.types excluded,
- comments, empty lines kept, and
- no annotation.

Output report only.

    merge-ngx-conf.pl -x /path/to/sites-available/domain.conf

- both nginx.conf and domain.conf included and followed,
- mime.types and naxsi .rules files excluded, and
- default nest level of 5 used.

Output report only, with data limited to a nest level of 4 and mime.types included.

    merge-ngx-conf.pl -x -i mime -n 4 /path/to/sites-available/domain.conf

- both nginx.conf and domain.conf included and followed, and
- naxsi .rules files excluded.


Help and Version

    merge-ngx-conf.pl -h  Read help
    merge-ngx-conf.pl -m  Read manual
    merge-ngx-conf.pl -v  Show version

# DIAGNOSTICS

Here, %s represents information that will vary. __(F)__ indicates a fatal message and the script will exit. __(W)__ indicates a warning message and the script will continue.

## Processing errors

While processing the include directives from a file, the following messages may be displayed.

- __The file referenced in the include directive could not be found.__

__(F)__ The file referenced in the include directive currently being processed by the script doesn't exist in the location specified by the include directive. Check your configuration files for any reference to the file indicated in the error message and ensure that the file exists and that the path to the file is set correctly.

The name of the file with the include directive, the include directive and the file name that couldn't be found will print below the message.

    Calling file: %s
    Directive: %s
    Referenced file missing: %s

- __The directory for the wildcard mask could not be opened.__

__(F)__ The directory referenced in an include directive with a wildcard mask couldn't be found. Check your configuration files for any reference to the directory indicated in the error message and ensure that the directory exists and that the path is set correctly.

The name of the file with the wildcard include directive, the include directive and the file name that couldn't be found will print below the message.

    Calling file: %s
    Directive: %s
    Referenced file missing: %s

- __Unable to open file referenced in directive.__

__(F)__ The file name that couldn't be opened will print below the message.

    File name: %s

- __Unable to open directory while processing wildcard mask.__

__(F)__ The directory that couldn't be opened will print below the message.

    Directory: %s

- __Unable to close file %s__

__(W)__ The script was unable to close the file it had opened.

- __Couldn't close directory %s while processing wildcard mask__

__(W)__ The script was unable to close the directory it had opened.

## Command line options and arguments errors

The following messages relate to command line options and arguments.

- __Unknown option in the command line__

__(F)__ A usage message will print. Check the manual for a more extensive explanation of valid options.

- __Invalid option value: %s. Use mime, rules or all.__

__(F)__ Check the manual for valid option values. for the __\-i__, __\--include__ option.

- __Too many arguments in the command line__

__(F)__ Only one argument is necessary - the absolute path to the domain configuration file.

- __No argument in the command line__

__(F)__ One argument must be supplied (except with __\-h, -m or -v__ options) - the absolute path to the domain configuration file.

- __The domain configuration file %s can't be found__

__(F)__ The script was unable to locate the domain configuration file supplied on the command line. Check to ensure the file exists and the path was spelled correctly.

- __The nginx.conf file %s can't be found__

__(F)__The script was unable to locate the nginx.conf file. Check to ensure the file exists.

- __Warning: Nest level too high. %s given. Script using default %s.__

(W) The script continues using a nest level of 10, the default maximum level unless you have changed the values in the %nest\_level hash. In this case, the script will default to the maximum level you set.

- __Warning: Nest level too low. %s given. Script using default %s.__

__(W)__ The script will continue using a nest level of 1, the default minimum level unless you have changed the values in the %nest\_level hash. In this case, the script will default to the minimum level you set.

# REPORT

This is an example of a report generated from a set of nginx configuration files used for testing the script.  This report was generated using the defaults with the __\-x__ option.

__Note__: Because I was testing various conditions, the test files I used contained some directives which you may or may not see in production configurations.  

1\. `conf.d/*`

Two files were in the `conf.d` directory - `confdtest1.conf` and `confdtest2.conf`  Both are included in `nginx.conf` because of the `conf.d/* `wildcard mask.  Additionally, an include directive in `confdtest1.conf` also calls `confdtest2.conf`.  Therefore, `confdtest2.conf` was included twice.  While this was expected behavior for the test files, it might not be what you intended.  I left this in the sample report because it's an example of how to troubleshoot a problem.  Nginx would not pick up something like this in configtest.  

2\. `extend/\*.conf` in test files

The include directive `include extend/\*.conf;` appears in both `nginx.conf` and `example.domain.conf`. Therefore, in the FILE RELATIONSHIP section of the report, it will appear twice, once at Level 2 and once at Level 3.


    Nginx Configuration Report
    generated: Tue Sep  2 07:14:41 2014

    Configuration directory: /etc/nginx
    Starting file:        /etc/nginx/nginx.conf
    Filtered: mime.types and naxsi .rules excluded

	------------------------------------------------------------------------

	NESTING

    Nest level used:    5 (default)
    Actual nest level:  3

	The level set was sufficient to process *all* unfiltered include directives.

	------------------------------------------------------------------------

	STATS

	Unique files in configuration:        8

    Total files processed:                9
      -- containing include directives:   5
      -- from wildcard mask(s):           5

    Total include directives processed:   9
      -- with wildcard mask:              4

	------------------------------------------------------------------------

	FILE LIST

	Files with include directives (relative to /etc/nginx):
	 (count of processed directives - filename)

    1 - conf.d/confdtest1.conf
    1 - extend/extend.conf
    3 - nginx.conf
    3 - sites-available/example.domain.conf

	Files without include directives (relative to /etc/nginx):

    --conf.d/confdtest2.conf
    --extend/extend1/extend1.conf
    --fastcgi_params
    --glob/globtest.conf

	------------------------------------------------------------------------

	FILE RELATION

    Level 1
     nginx.conf
           <-- conf.d/confdtest1.conf
           <-- conf.d/confdtest2.conf
           <-- extend/extend.conf
           <-- sites-available/example.domain.conf

    Level 2
     sites-available/example.domain.conf
           <-- extend/extend.conf
           <-- fastcgi_params
           <-- glob/globtest.conf

    conf.d/confdtest1.conf
          <-- conf.d/confdtest2.conf

    extend/extend.conf
          <-- extend/extend1/extend1.conf

    Level 3
     extend/extend.conf
           <-- extend/extend1/extend1.conf

	------------------------------------------------------------------------

	FILE FLOW

    nginx.conf <-- conf.d/confdtest1.conf <-- conf.d/confdtest2.conf

    nginx.conf <-- conf.d/confdtest2.conf

    nginx.conf <-- extend/extend.conf <-- extend/extend1/extend1.conf

    nginx.conf <-- sites-available/example.domain.conf <-- extend/extend.conf
                           <-- extend/extend1/extend1.conf

    nginx.conf <-- sites-available/example.domain.conf <-- fastcgi_params

    nginx.conf <-- sites-available/example.domain.conf <-- glob/globtest.conf



## Interpretation of the report

Uses the above report as an example.

### Header Section

This section of the report displays the:

- the local time the report was generated,
- the configuration directory used,
- the starting file (either nginx.conf or example.domain.conf if run with the __\-d__ option), and
- the include directives that were filtered:
	- The default message is "mime.types and naxsi .rules excluded".
	- The __\-i__ option messages:
		- __\-i__ _mime_    -  "naxsi .rules directives excluded"
		- __\-i__ _rules_   -  "mime.types excluded"
		- __\-i__ _all_     -  "none"

Commented include directives are always filtered.

### Nesting Section

This section displays the:

- nest level used by the script. This may be the default of 5 or changed with the __\-n__ _N_ switch. The maximum level is 5 and the minimum level is 1. When a value out of this range is given, the script will default to either 1 if __\-n__ _0_ was used or 10 if __\-n__ _>10_ was used.

- actual nest level the script found, and a
- message indicating whether all unfiltered directives were processed at the nest level used.

	- If all unfiltered directives were processed, this message appears: 
 
	    	The level set was sufficient to process *all* unfiltered 
	    	include directives.

	- If all the unfiltered directives were not processed, this message appears:

			Unfiltered include directives were processed to the level set. 
			Additional include directive(s) were not processed. Consider
			increasing the nesting level using the -n N option if you want
			all levels to be processed.

Note that if you intentionally set the nest level using the __\-n _N___ option to a lower level, this message may still appear. If your intention was to limit output to a certain level only, then you can ignore this message. For example, you might only want to see the output for nginx.conf include directives only. In this case, setting __\-n _1___ will give you that information but will cause the message to appear.

### Stats Section

The script will process a file each time it appears in an include directive so if the same file is referenced in more than one include directive, it is counted twice. This is necessary because a file may be included at different nesting levels. For example, in the `/etc/nginx` configuration, the file `extend.conf` is referenced in include directives in both `nginx.conf` and `example.domain.conf`.

__Special treatment of sites-enabled include directive:__  As stated in Note 1 below, the sites-enabled wildcard mask is not counted as a wildcard mask, however the include directive itself is counted. The files count from wildcard masks does not count `example.domain.conf`.

### File List Section

This section lists the files with include directives, including the count of the filtered directives that were processed, and files with no include directives.

### File Relation Section

This section lists the relation of the files at each level of nesting. As stated in Note 3 below, the directive `include extend/*.conf;` appears in both `nginx.conf` and `example.domain.conf`. Therefore, the relation will appear twice, once at Level 2 and once at Level 3.

### File Flow Section

This section attempts to present a view of how the files "flow" into one another. The flow is read from right to left. As stated in Note 2 below, `confdtest2.conf` is included twice, which is expected behavior, although possibly unintended in a production environment. 

A file may be included in another file more than once. For example, `example.domain.conf` may have several include directives referencing `fastcgi_params`. The file flow does not represent the number of times a file may be included. In this example, `fastcgi_params` will appear only once.

### Report Tips and Tricks

Assemble `nginx.conf` only - use __\-n _1___ option

Assemble `example.domain.conf` only - use __\-d -n _1___' options

# EXIT STATUS

The script will exit with 0 if successful.

# CONFIGURATION

Configuration is done entirely through command line options.  There is no associated configuration file.

# DEPENDENCIES

This script uses only core Perl modules.

# INCOMPATIBILITIES

No known incompatibilities.

# BUGS AND LIMITATIONS

The minimum required version is Perl v5.11.0.

The script assumes the standard nginx directory structure:

- 1\. Nginx configuration files under a base directory.
- 2\. The domain configuration file located in the sites-available/
subdirectory.

__A Note on the Output:__

What you see is what your include directives have indicated should happen. If something looks off, then check your include directives first before filing a bug report.  

For example, a file can be included multiple times within another file. Often, this is the intention. However, sometimes you may inadvertantly include a file more than once, such as when a wildcard mask includes all files in a subdirectory and one of those files contains an include directive referencing a file in that same subdirectory. Was that your intention? The script won't know. It just puts everything where the configuration files tell it to.

Please report any bugs or feature requests through the [GitHub web interface](https://github.com/troubleshooter/merge-ngx-conf/issues).

# NOTES

1\. sites-enabled/*

The sites-enabled/* wildcard mask is not treated as a wildcard mask by the script because the domain configuration file is substituted there. In any report generated, the wildcard mask count will not include this directive. Additionally, any file counts for wildcard masks will not include example.domain.conf.

2\. Commented include directives are _never processed_.

3\. The script was tested on various configurations, including test configurations, production configurations and [perusio's Github repository](drupal-with-nginx|https://github.com/perusio/drupal-with-nginx).

# AUTHOR

[Terry Roy](https://github.com/troubleshooter)

# LICENSE AND COPYRIGHT

Copyright 2014-to present Terry Roy

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See [License](http://dev.perl.org/licenses/artistic.html).

# DISCLAIMER OF WARRANTY

This software is provided "as is" and you use at your own risk.

See [License](http://dev.perl.org/licenses/artistic.html).