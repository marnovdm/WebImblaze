#!/usr/bin/perl

# $Id$
# $Revision$
# $Date$

use strict;
use warnings;
use vars qw/ $VERSION /;

$VERSION = '1.97';

#removed the -w parameter from the first line so that warnings will not be displayed for code in the packages

#    Copyright 2004-2006 Corey Goldberg (corey@goldb.org)
#    Extensive updates 2015-2016 Tim Buckland
#
#    This file is part of WebInject.
#
#    WebInject is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    WebInject is distributed in the hope that it will be useful,
#    but without any warranty; without even the implied warranty of
#    merchantability or fitness for a particular purpose.  See the
#    GNU General Public License for more details.

my $driver; ## support for Selenium WebDriver test cases

use LWP;
use URI::URL; ## So gethrefs can determine the absolute URL of an asset, and the asset name, given a page url and an asset href
use File::Basename; ## So gethrefs can determine the filename of the asset from the path
use File::Spec;
use File::Slurp;
use HTTP::Request::Common;
use HTTP::Cookies;
use XML::Simple;
use Time::HiRes 'time','sleep';
use Getopt::Long;
use Crypt::SSLeay;  #for SSL/HTTPS (you may comment this out if you don't need it)
local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 'false';
use IO::Socket::SSL qw( SSL_VERIFY_NONE );
use Socket qw( PF_INET SOCK_STREAM INADDR_ANY sockaddr_in );
use File::Copy qw(copy), qw(move);

local $| = 1; #don't buffer output to STDOUT


## Variable declarations
my ($timestamp, $testfilename);
my (%parsedresult);
my (%varvar);
my ($useragent, $request, $response);
my ($latency, $verificationlatency, $screenshotlatency);
my (%teststeptime); ## record in a hash the latency for every step for later use
my ($cookie_jar, @httpauth);
my ($runcount, $totalruncount, $casepassedcount, $casefailedcount, $passedcount, $failedcount);
my ($totalresponse, $avgresponse, $maxresponse, $minresponse);
my ($currentcasefile, $currentcasefilename, $casecount, $isfailure, $verifynegativefailed);
my (%case, %casesave);
my (%config);
my ($currentdatetime, $totalruntime, $starttimer, $endtimer);
my ($opt_configfile, $opt_version, $opt_output, $opt_autocontroller, $opt_port, $opt_proxy);
my ($opt_driver, $opt_proxyrules, $opt_ignoreretry, $opt_help, $opt_chromedriver_binary, $opt_publish_full);

my ($testnum, $xmltestcases); ## $testnum made global
my ($testnum_display, $previous_test_step, $delayed_file_full, $delayed_html); ## individual step file html logging
my ($retry, $retries, $globalretries, $retrypassedcount, $retryfailedcount, $retriesprint, $jumpbacks, $jumpbacksprint); ## retry failed tests
my ($forcedretry); ## force retry when specific http error code received
my ($sanityresult); ## if a sanity check fails, execution will stop (as soon as all retries are exhausted on the current test case)
my ($starttime); ## to store a copy of $startruntimer in a global variable
my ($cmdresp); ## response from running a terminal command
my ($selresp); ## response from a Selenium command
my ($element); ## for element selectors
my (@verifyparms); ## friendly error message to show when an assertion fails
my (@verifycountparms); ## regex match occurences must much a particular count for the assertion to pass
my ($output, $outputfolder); ## output path including possible filename prefix, output path without filename prefix
my ($outsum); ## outsum is a checksum calculated on the output directory name. Used to help guarantee test data uniqueness where two WebInject processes are running in parallel.
my ($userconfig); ## support arbirtary user defined config
my ($convert_back_ports, $convert_back_ports_null); ## turn {:4040} into :4040 or null
my $totalassertionskips = 0;
my (@pages); ## page source of previously visited pages
my (@pagenames); ## page name of previously visited pages
my (@pageupdatetimes); ## last time the page was updated in the cache
my $chromehandle = 0; ## windows handle of chrome browser window - for screenshots
my $assertionskips = 0;
my $assertionskipsmessage = q{}; ## support tagging an assertion as disabled with a message
my (@hrefs, @srcs, @bg_images); ## substitute in grabbed assets to step results html

## put the current date and time into variables - startdatetime - for recording the start time in a format an xsl stylesheet can process
my @MONTHS = qw(01 02 03 04 05 06 07 08 09 10 11 12);
my @MONTHS_TEXT = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my @WEEKDAYS = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
my ($SECOND, $MINUTE, $HOUR, $DAYOFMONTH, $MONTH, $YEAROFFSET, $DAYOFWEEK, $DAYOFYEAR, $DAYLIGHTSAVINGS) = localtime;
my $YEAR = 1900 + $YEAROFFSET;
my $YY = substr $YEAR, 2; #year as 2 digits
my $MONTH_TEXT = $MONTHS_TEXT[$MONTH];
$DAYOFMONTH = sprintf '%02d', $DAYOFMONTH;
my $WEEKOFMONTH = int(($DAYOFMONTH-1)/7)+1;
my $STARTDATE = "$YEAR-$MONTHS[$MONTH]-$DAYOFMONTH";
$MINUTE = sprintf '%02d', $MINUTE; #put in up to 2 leading zeros
$SECOND = sprintf '%02d', $SECOND;
$HOUR = sprintf '%02d', $HOUR;
my $TIMESECONDS = ($HOUR * 60 * 60) + ($MINUTE * 60) + $SECOND;
$currentdatetime = "$WEEKDAYS[$DAYOFWEEK] $DAYOFMONTH $MONTH_TEXT $YEAR, $HOUR:$MINUTE:$SECOND";

my $this_script_folder_full = dirname(__FILE__);
chdir $this_script_folder_full;

my $counter = 0; ## keeping track of the loop we are up to

my $concurrency = 'null'; ## current working directory - not full path
my $png_base64; ## Selenium full page grab screenshot

my ( $results_html, $results_xml, $results_xml_file_name );
my ($startruntimer, $endruntimer, $repeat, $start);
my ($is_testcases_tag_already_written);

my $hostname = `hostname`; ##no critic(ProhibitBacktickOperators) ## hostname should work on Linux and Windows
$hostname =~ s/\r|\n//g; ## strip out any rogue linefeeds or carriage returns

my $is_windows = $^O eq 'MSWin32' ? 1 : 0;

## Startup
getoptions();  #get command line options
startsession(); #starts, or restarts the webinject session
processcasefile();
writeinitialstdout();  #write opening tags for STDOUT.

_whack($opt_publish_full.'http.txt');
_whack($opt_publish_full.'results.html');

write_initial_xml();
writeinitialhtml();  #write opening tags for results file

$totalruncount = 0;
$casepassedcount = 0;
$casefailedcount = 0;
$passedcount = 0;
$failedcount = 0;
$totalresponse = 0;
$avgresponse = 0;
$maxresponse = 0;
$minresponse = 10_000_000; #set to large value so first minresponse will be less

$globalretries=0; ## total number of retries for this run across all test cases

$startruntimer = time;  #timer for entire test run
$starttime = $startruntimer; ## need a global variable to make a copy of the start run timer

$currentcasefilename = basename($currentcasefile); ## with extension
$testfilename = fileparse($currentcasefile, '.xml'); ## without extension

read_test_case_file();

$repeat = $xmltestcases->{repeat};  #grab the number of times to iterate test case file
if (!$repeat) { $repeat = 1; }  #set to 1 in case it is not defined in test case file

$start = $xmltestcases->{start};  #grab the start for repeating (for restart)
if (!$start) { $start = 1; }  #set to 1 in case it is not defined in test case file

$counter = $start - 1; #so starting position and counter are aligned

if ($opt_driver) { startseleniumbrowser(); }  ## start selenium browser if applicable. If it is already started, close browser then start it again.

print {*STDOUT} "-------------------------------------------------------\n";

## Repeat Loop
foreach ($start .. $repeat) {

    $counter = $counter + 1;
    $runcount = 0;
    $jumpbacksprint = q{}; ## we do not indicate a jump back until we actually jump back
    $jumpbacks = 0;

    my @teststeps = sort {$a<=>$b} keys %{$xmltestcases->{case}};
    my $numsteps = scalar @teststeps;

    ## Loop over each of the test cases (test steps)
    TESTCASE:   for (my $stepindex = 0; $stepindex < $numsteps; $stepindex++) {  ## no critic(ProhibitCStyleForLoops)

        $testnum = $teststeps[$stepindex];

        $testnum_display = get_testnum_display($testnum, $counter);

        $isfailure = 0;
        $retries = 1; ## we increment retries after writing to the log
        $retriesprint = q{}; ## the printable value is used before writing the results to the log, so it is one behind, 0 being printed as null

        $timestamp = time;  #used to replace parsed {timestamp} with real timestamp value

        set_useragent($xmltestcases->{case}->{$testnum}->{useragent});

        my $skip_message = get_test_step_skip_message();
        if ( $skip_message ) {
            print {*STDOUT} "Skipping Test Case $testnum... ($skip_message)\n";
            print {*STDOUT} qq|------------------------------------------------------- \n|;
            next TESTCASE; ## skip running this test step
        }

        # populate variables with values from testcase file, do substitutions, and revert converted values back
        substitute_variables();

        $retry = get_number_of_times_to_retry_this_test_step(); # 0 means do not retry this step

        do ## retry loop
        {
            ## for each retry, there are a few substitutions that we need to redo - like the retry number
            substitute_retry_variables();

            set_var_variables(); ## finally set any variables after doing all the static and dynamic substitutions
            substitute_var_variables();
            
            set_retry_to_zero_if_global_limit_exceeded();

            $isfailure = 0;
            $verifynegativefailed = 'false';
            $retrypassedcount = 0;
            $retryfailedcount = 0;

            $timestamp = time;  #used to replace parsed {timestamp} with real timestamp value

            if ($case{description1} and $case{description1} =~ /dummy test case/) {  #if we hit a dummy record, skip it
                next;
            }

            $results_html .= qq|<b>Test:  $currentcasefile - <a href="$testnum_display$jumpbacksprint$retriesprint.html"> $testnum_display$jumpbacksprint$retriesprint </a> </b><br />\n|;

            print {*STDOUT} qq|Test:  $currentcasefile - $testnum_display$jumpbacksprint$retriesprint \n|;

            if (!$is_testcases_tag_already_written) { # Only write the testcases opening tag once in the results.xml
                $results_xml .= qq|    <testcases file="$currentcasefile">\n\n|;
                $is_testcases_tag_already_written = 'true';
            }

            $results_xml .= qq|        <testcase id="$testnum_display$jumpbacksprint$retriesprint">\n|;

            for (qw/section description1 description2/) { ## support section breaks
                next unless defined $case{$_};
                $results_html .= qq|$case{$_} <br />\n|;
                print {*STDOUT} qq|$case{$_} \n|;
                $results_xml .= qq|            <$_>|._sub_xml_special($case{$_}).qq|</$_>\n|;
            }

            $results_html .= qq|<br />\n|;

            ## display and log the verifications to do to stdout and html - xml output is done with the verification itself
            ## verifypositive, verifypositive1, ..., verifypositive9999 (or even higher)
            ## verifynegative, verifynegative2, ..., verifynegative9999 (or even higher)
            foreach my $case_attribute ( sort keys %{ $xmltestcases->{case}->{$testnum} } ) {
                if ( (substr $case_attribute, 0, 14) eq 'verifypositive' || (substr $case_attribute, 0, 14) eq 'verifynegative') {
                    my $verifytype = substr $case_attribute, 6, 8; ## so we get the word positive or negative
                    $verifytype = ucfirst $verifytype; ## change to Positive or Negative
                    @verifyparms = split /[|][|][|]/, $case{$case_attribute} ; ## index 0 contains the actual string to verify
                    $results_html .= qq|Verify $verifytype: "$verifyparms[0]" <br />\n|;
                    print {*STDOUT} qq|Verify $verifytype: "$verifyparms[0]" \n|;
                }
            }

            if ($case{verifyresponsecode}) {
                $results_html .= qq|Verify Response Code: "$case{verifyresponsecode}" <br />\n|;
                print {*STDOUT} qq|Verify Response Code: "$case{verifyresponsecode}" \n|;
                $results_xml .= qq|            <verifyresponsecode>$case{verifyresponsecode}</verifyresponsecode>\n|;
            }

            if ($case{verifyresponsetime}) {
                $results_html .= qq|Verify Response Time: at most "$case{verifyresponsetime} seconds" <br />\n|;
                print {*STDOUT} qq|Verify Response Time: at most "$case{verifyresponsetime}" seconds\n|;
                $results_xml .= qq|            <verifyresponsetime>$case{verifyresponsetime}</verifyresponsetime>\n|;
            }

            if ($case{retryresponsecode}) {## retry if a particular response code was returned
                $results_html .= qq|Retry Response Code: "$case{retryresponsecode}" <br />\n|;
                print {*STDOUT} qq|Will retry if we get response code: "$case{retryresponsecode}" \n|;
                $results_xml .= qq|            <retryresponsecode>$case{retryresponsecode}</retryresponsecode>\n|;
            }


            if ($case{method}) {
                if ($case{method} eq 'delete') { httpdelete(); }
                if ($case{method} eq 'get') { httpget(); }
                if ($case{method} eq 'post') { httppost(); }
                if ($case{method} eq 'put') { httpput(); }
                if ($case{method} eq 'cmd') { cmd(); }
                if ($case{method} eq 'selenium') { selenium(); }
            }
            else {
               httpget();  #use "get" if no method is specified
            }

            searchimage(); ## search for images within actual screen or page grab

            decode_quoted_printable();

            verify(); #verify result from http response

            gethrefs(); ## get specified web page href assets
            getsrcs(); ## get specified web page src assets
            getbackgroundimages(); ## get specified web page src assets

            parseresponse();  #grab string from response to send later

            httplog();  #write to http.txt file
            $previous_test_step = $testnum_display.$jumpbacksprint.$retriesprint;

            ## check max jumpbacks - globaljumpbacks - i.e. retryfromstep usages before we give up - otherwise we risk an infinite loop
            if ( (($isfailure > 0) && ($retry < 1) && !($case{retryfromstep})) || (($isfailure > 0) && ($case{retryfromstep}) && ($jumpbacks > ($config{globaljumpbacks}-1) )) || ($verifynegativefailed eq 'true')) {  #if any verification fails, test case is considered a failure UNLESS there is at least one retry available, or it is a retryfromstep case. However if a verifynegative fails then the case is always a failure
                $results_xml .= qq|            <success>false</success>\n|;
                if ($case{errormessage}) { #Add defined error message to the output
                    $results_html .= qq|<b><span class="fail">TEST CASE FAILED : $case{errormessage}</span></b><br />\n|;
                    $results_xml .= '            <result-message>'._sub_xml_special($case{errormessage})."</result-message>\n";
                    print {*STDOUT} qq|TEST CASE FAILED : $case{errormessage}\n|;
                }
                else { #print regular error output
                    $results_html .= qq|<b><span class="fail">TEST CASE FAILED</span></b><br />\n|;
                    $results_xml .= qq|            <result-message>TEST CASE FAILED</result-message>\n|;
                    print {*STDOUT} qq|TEST CASE FAILED\n|;
                }
                $casefailedcount++;
            }
            elsif (($isfailure > 0) && ($retry > 0)) {#Output message if we will retry the test case
                $results_html .= qq|<b><span class="pass">RETRYING... $retry to go</span></b><br />\n|;
                print {*STDOUT} qq|RETRYING... $retry to go \n|;
                $results_xml .= qq|            <success>false</success>\n|;
                $results_xml .= qq|            <result-message>RETRYING... $retry to go</result-message>\n|;

                ## all this is for ensuring correct behaviour when retries occur
                $retriesprint = ".$retries";
                $retries++;
                $globalretries++;
                $passedcount = $passedcount - $retrypassedcount;
                $failedcount = $failedcount - $retryfailedcount;
            }
            elsif (($isfailure > 0) && $case{retryfromstep}) {#Output message if we will retry the test case from step
                my $jumpbacksleft = $config{globaljumpbacks} - $jumpbacks;
                $results_html .= qq|<b><span class="pass">RETRYING FROM STEP $case{retryfromstep} ... $jumpbacksleft tries left</span></b><br />\n|;
                print {*STDOUT} qq|RETRYING FROM STEP $case{retryfromstep} ...  $jumpbacksleft tries left\n|;
                $results_xml .= qq|            <success>false</success>\n|;
                $results_xml .= qq|            <result-message>RETRYING FROM STEP $case{retryfromstep} ...  $jumpbacksleft tries left</result-message>\n|;
                $jumpbacks++; ## increment number of times we have jumped back - i.e. used retryfromstep
                $jumpbacksprint = "-$jumpbacks";
                $globalretries++;
                $passedcount = $passedcount - $retrypassedcount;
                $failedcount = $failedcount - $retryfailedcount;

                ## find the index for the test step we are retrying from
                $stepindex = 0;
                my $foundindex = 'false';
                foreach (@teststeps) {
                    if ($teststeps[$stepindex] eq $case{retryfromstep}) {
                        $foundindex = 'true';
                        last;
                    }
                    $stepindex++
                }
                if ($foundindex eq 'false') {
                    print {*STDOUT} qq|ERROR - COULD NOT FIND STEP $case{retryfromstep} - TESTING STOPS \n|;
                }
                else
                {
                    $stepindex--; ## since we increment it at the start of the next loop / end of this loop
                }
            }
            else {
                $results_html .= qq|<b><span class="pass">TEST CASE PASSED</span></b><br />\n|;
                print {*STDOUT} qq|TEST CASE PASSED \n|;
                $results_xml .= qq|            <success>true</success>\n|;
                $results_xml .= qq|            <result-message>TEST CASE PASSED</result-message>\n|;
                $casepassedcount++;
                $retry = 0; # no need to retry when test case passes
            }

            $results_html .= qq|Response Time = $latency sec <br />\n|;

            print {*STDOUT} qq|Response Time = $latency sec \n|;

            $results_xml .= qq|            <responsetime>$latency</responsetime>\n|;

            if ($case{method} eq 'selenium') {
                $results_html .= qq|Verification Time = $verificationlatency sec <br />\n|;
                $results_html .= qq|Screenshot Time = $screenshotlatency sec <br />\n|;

                print {*STDOUT} qq|Verification Time = $verificationlatency sec \n|;
                print {*STDOUT} qq|Screenshot Time = $screenshotlatency sec \n|;

                $results_xml .= qq|            <verificationtime>$verificationlatency</verificationtime>\n|;
                $results_xml .= qq|            <screenshottime>$screenshotlatency</screenshottime>\n|;
            }


            $results_xml .= qq|        </testcase>\n\n|;
            _write_xml (\$results_xml);
            undef $results_xml;

            $results_html .= qq|<br />\n------------------------------------------------------- <br />\n\n|;
            _write_html (\$results_html);
            undef $results_html;

            print {*STDOUT} qq|------------------------------------------------------- \n|;

            $endruntimer = time;
            $totalruntime = (int(1000 * ($endruntimer - $startruntimer)) / 1000);  #elapsed time rounded to thousandths

            #if (($isfailure > 0) && ($retry > 0)) {  ## do not increase the run count if we will retry
            if ( (($isfailure > 0) && ($retry > 0) && !($case{retryfromstep})) || (($isfailure > 0) && ($case{retryfromstep}) && ($jumpbacks < $config{globaljumpbacks}  ) && ($verifynegativefailed eq 'false') ) ) {
                ## do not count this in run count if we are retrying, again maximum usage of retryfromstep has been hard coded
            }
            else {
                $runcount++;
                $totalruncount++;
            }

            if ($latency > $maxresponse) { $maxresponse = $latency; }  #set max response time
            if ($latency < $minresponse) { $minresponse = $latency; }  #set min response time
            $totalresponse = ($totalresponse + $latency);  #keep total of response times for calculating avg
            if ($totalruncount > 0) { #only update average response if at least one test case has completed, to avoid division by zero
                $avgresponse = (int(1000 * ($totalresponse / $totalruncount)) / 1000);  #avg response rounded to thousandths
            }

            $teststeptime{$testnum_display}=$latency; ## store latency for step

            if ($case{restartbrowseronfail} && ($isfailure > 0)) { ## restart the Selenium browser session and also the WebInject session
                print {*STDOUT} qq|RESTARTING SESSION DUE TO FAIL ... \n|;
                if ($opt_driver) { startseleniumbrowser(); }
                startsession();
            }

            if ($case{restartbrowser}) { ## restart the Selenium browser session and also the WebInject session
                print {*STDOUT} qq|RESTARTING BROWSER ... \n|;
                if ($opt_driver) {
                        print {*STDOUT} "RESTARTING SESSION ...\n";
                        startseleniumbrowser();
                    }
                startsession();
            }

            if ( (($isfailure < 1) && ($case{retry})) || (($isfailure < 1) && ($case{retryfromstep})) )
            {
                ## ignore the sleep if the test case worked and it is a retry test case
            }
            else
            {
                if ($case{sleep})
                {
                    if ( (($isfailure > 0) && ($retry < 1)) || (($isfailure > 0) && ($jumpbacks > ($config{globaljumpbacks}-1))) )
                    {
                        ## do not sleep if the test case failed and we have run out of retries or jumpbacks
                    }
                    else
                    {
                        ## if a sleep value is set in the test case, sleep that amount
                        sleep $case{sleep};
                    }
                }
            }

            $retry = $retry - 1;
        } ## end of retry loop
        until ($retry < 0); ## no critic(ProhibitNegativeExpressionsInUnlessAndUntilConditions])

        if ($case{sanitycheck} && ($casefailedcount > 0)) { ## if sanitycheck fails (i.e. we have had any error at all after retries exhausted), then execution is aborted
            print {*STDOUT} qq|SANITY CHECK FAILED ... Aborting \n|;
            last;
        }
    } ## end of test case loop

    $testnum = 1;  #reset testcase counter so it will reprocess test case file if repeat is set
} ## end of repeat loop

finaltasks();  #do return/cleanup tasks

## shut down the Selenium server last - it is less important than closing the files
shutdown_selenium();

my $status = $casefailedcount cmp 0;
exit $status;
## End main code

#------------------------------------------------------------------
#  SUBROUTINES
#------------------------------------------------------------------

sub get_testnum_display {
    my ($_testnum, $_counter) = @_;

        ## use $testnum_display for all testnum output, add 10,000 in case of repeat loop
        my $_testnum_display = $_testnum + ($_counter*10_000) - 10_000;
        $_testnum_display = sprintf '%.2f', $_testnum_display; ## maximul of 2 decimal places
        $_testnum_display =~ s/0+\z// if $_testnum_display =~ /[.]/; ## remove trailing non significant zeros
        if (not ($_testnum_display =~ s/[.]\z//) ) { ## remove decimal point if nothing after
            $_testnum_display = sprintf '%.2f', $_testnum_display; ## put back the non significant zero if we have a decimal point
        }

    return $_testnum_display;
}

#------------------------------------------------------------------
sub set_useragent {
    my ($_useragent) = @_;

    if (not $_useragent) { return; }

    $useragent->agent($_useragent);

    return;
}

#------------------------------------------------------------------
sub get_test_step_skip_message {

    $case{runon} = $xmltestcases->{case}->{$testnum}->{runon}; ## skip test cases not flagged for this environment
    if ($case{runon}) { ## is this test step conditional on the target environment?
        if ( _run_this_step($case{runon}) ) {
            ## run this test case as normal since it is allowed
        }
        else {
            return "run on $case{runon}";
        }
    }

    $case{donotrunon} = $xmltestcases->{case}->{$testnum}->{donotrunon}; ## skip test cases flagged not to run on this environment
    if ($case{donotrunon}) { ## is this test step conditional on the target environment?
        if ( not _run_this_step($case{donotrunon}) ) {
            ## run this test case as normal since it is allowed
        }
        else {
            return "do not run on $case{donotrunon}";
        }
    }

    $case{autocontrolleronly} = $xmltestcases->{case}->{$testnum}->{autocontrolleronly}; ## only run this test case on the automation controller, e.g. test case may involve a test virus which cannot be run on a regular corporate desktop
    if ($case{autocontrolleronly}) { ## is the autocontrolleronly value set for this testcase?
        if ($opt_autocontroller) { ## if so, was the auto controller option specified?
            ## run this test case as normal since it is allowed
        }
        else {
              return 'This is not the automation controller';
        }
    }

    $case{firstlooponly} = $xmltestcases->{case}->{$testnum}->{firstlooponly}; ## only run this test case on the first loop
    if ($case{firstlooponly}) { ## is the firstlooponly value set for this testcase?
        if ($counter == 1) { ## counter keeps track of what loop number we are on
            ## run this test case as normal since it is the first pass
        }
        else {
              return 'firstlooponly';
        }
    }

    $case{lastlooponly} = $xmltestcases->{case}->{$testnum}->{lastlooponly}; ## only run this test case on the last loop
    if ($case{lastlooponly}) { ## is the lastlooponly value set for this testcase?
        if ($counter == $repeat) { ## counter keeps track of what loop number we are on
            ## run this test case as normal since it is the first pass
        }
        else {
              return 'lastlooponly';
        }
    }

    return;
}

#------------------------------------------------------------------
sub substitute_variables {

    ## "method", "description1", "description2", "url", "postbody", "posttype", "addheader", "command", "command1", ... "command20", "parms", "verifytext",
    ## "verifypositive", "verifypositive1", ... "verifypositive9999",
    ## "verifynegative", "verifynegative1", ... "verifynegative9999",
    ## "parseresponse", "parseresponse1", ... , "parseresponse40", ... , "parseresponse9999", "parseresponseORANYTHING", "verifyresponsecode",
    ## "verifyresponsetime", "retryresponsecode", "sleep", "errormessage", "ignorehttpresponsecode", "ignoreautoassertions", "ignoresmartassertions",
    ## "retry", "sanitycheck", "logastext", "section", "assertcount", "searchimage", ... "searchimage5", "screenshot", "formatxml", "formatjson",
    ## "logresponseasfile", "addcookie", "restartbrowseronfail", "restartbrowser", "commandonerror", "gethrefs", "getsrcs", "getbackgroundimages",
    ## "firstlooponly", "lastlooponly", "decodequotedprintable"

    undef %casesave; ## we need a clean array for each test case
    undef %case; ## do not allow values from previous test cases to bleed over
    foreach my $case_attribute ( keys %{ $xmltestcases->{case}->{$testnum} } ) {
        #print "DEBUG: $case_attribute", ": ", $xmltestcases->{case}->{$testnum}->{$case_attribute};
        #print "\n";
        $case{$case_attribute} = $xmltestcases->{case}->{$testnum}->{$case_attribute};
        convertbackxml($case{$case_attribute});
        $casesave{$case_attribute} = $case{$case_attribute}; ## in case we have to retry, some parms need to be resubbed
    }

    return;
}

#------------------------------------------------------------------
sub get_number_of_times_to_retry_this_test_step {

    $case{retryfromstep} = $xmltestcases->{case}->{$testnum}->{retryfromstep}; ## retry from a [previous] step
    if ($case{retryfromstep}) { ## retryfromstep parameter found
        return 0; ## we will not do a regular retry
    }

    my $_retry;
    $case{retry} = $xmltestcases->{case}->{$testnum}->{retry}; ## optional retry of a failed test case
    if ($case{retry}) { ## retry parameter found
        $_retry = $case{retry}; ## assume we can retry as many times as specified
        if ($config{globalretry}) { ## ensure that the global retry limit won't be exceeded
            if ($_retry > ($config{globalretry} - $globalretries)) { ## we can't retry that many times
                $_retry =  $config{globalretry} - $globalretries; ## this is the most we can retry
                if ($_retry < 0) {
                    return 0; ## if less than 0 then make 0
                }
            }
        }
        print {*STDOUT} qq|Retry $_retry times\n|;
        return $_retry;
    }
    else {
        return 0; #no retry parameter found, don't retry this case
    }

    return; ## impossible to execute this statement
}

#------------------------------------------------------------------
sub substitute_retry_variables {

    foreach my $_case_attribute ( keys %{ $xmltestcases->{case}->{$testnum} } ) {
        if (defined $casesave{$_case_attribute}) ## defaulted parameters like posttype may not have a saved value on a subsequent loop
        {
            $case{$_case_attribute} = $casesave{$_case_attribute}; ## need to restore to the original partially substituted parameter
            convertbackxmldynamic($case{$_case_attribute}); ## now update the dynamic components
        }
    }

    return;
}

#------------------------------------------------------------------
sub set_retry_to_zero_if_global_limit_exceeded {

    if ($config{globalretry}) {
        if ($globalretries >= $config{globalretry}) {
            $retry = 0; ## globalretries value exceeded - not retrying any more this run
        }
    }

    return;
}


#------------------------------------------------------------------
sub writeinitialhtml {  #write opening tags for results file

    $results_html .= qq|<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"\n|;
    $results_html .= qq|    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">\n\n|;

    $results_html .= qq|<html xmlns="http://www.w3.org/1999/xhtml">\n|;
    $results_html .= qq|<head>\n|;
    $results_html .= qq|    <title>WebInject Test Results</title>\n|;
    $results_html .= qq|    <meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" />\n|;
    $results_html .= qq|    <style type="text/css">\n|;
    $results_html .= qq|        body {\n|;
    $results_html .= qq|            background-color: #F5F5F5;\n|;
    $results_html .= qq|            color: #000000;\n|;
    $results_html .= qq|            font-family: Verdana, Arial, Helvetica, sans-serif;\n|;
    $results_html .= qq|            font-size: 10px;\n|;
    $results_html .= qq|        }\n|;
    $results_html .= qq|        .pass {\n|;
    $results_html .= qq|            color: green;\n|;
    $results_html .= qq|        }\n|;
    $results_html .= qq|        .fail {\n|;
    $results_html .= qq|            color: red;\n|;
    $results_html .= qq|        }\n|;
    $results_html .= qq|        .skip {\n|;
    $results_html .= qq|            color: orange;\n|;
    $results_html .= qq|        }\n|;
    $results_html .= qq|    </style>\n|;
    $results_html .= qq|</head>\n|;
    $results_html .= qq|<body>\n|;
    $results_html .= qq|<hr />\n|;
    $results_html .= qq|-------------------------------------------------------<br />\n\n|;

    return;
}

#------------------------------------------------------------------
sub _whack {
    my ($_goner) = @_;

    if (-e $_goner ) {
        unlink $_goner or die "Could not unlink $_goner\n";
    }

    return;
}

#------------------------------------------------------------------
sub write_initial_xml {  #write opening tags for results file

    # put a reference to the stylesheet in the results file
    my $_results_xml = '<?xml version="1.0" encoding="ISO-8859-1"?>'."\n";
    $_results_xml .= '<?xml-stylesheet type="text/xsl" href="../../../../../../../content/Results.xsl"?>'."\n";
    $_results_xml .= "<results>\n\n";
    $results_xml_file_name = 'results.xml';
    if ( defined $userconfig->{wif}->{dd} && defined $userconfig->{wif}->{run_number} ) { # presume if this info is present, webinject.pl has been called by wif.pl
        $results_xml_file_name = 'results_'.$userconfig->{wif}->{run_number}.'.xml';
        $_results_xml .= "    <wif>\n";
        $_results_xml .= "        <environment>$userconfig->{wif}->{environment}</environment>\n";
        $_results_xml .= "        <yyyy>$userconfig->{wif}->{yyyy}</yyyy>\n";
        $_results_xml .= "        <mm>$userconfig->{wif}->{mm}</mm>\n";
        $_results_xml .= "        <dd>$userconfig->{wif}->{dd}</dd>\n";
        $_results_xml .= "        <batch>$userconfig->{wif}->{batch}</batch>\n";
        $_results_xml .= "    </wif>\n";
    }
    _whack($opt_publish_full.$results_xml_file_name);
    _write_xml(\$_results_xml);

    return;
}

#------------------------------------------------------------------
sub _write_xml {
    my ($_xml) = @_;

    open my $_RESULTS_XML, '>>', "$opt_publish_full".$results_xml_file_name or die "\nERROR: Failed to open results.xml file\n\n";
    print {$_RESULTS_XML} ${$_xml};
    close $_RESULTS_XML or die "\nCould not close xml results file\n\n";

    return;
}

#------------------------------------------------------------------
sub _write_html {
    my ($_html) = @_;

    open my $_RESULTS_HTML, '>>', $opt_publish_full.'results.html' or die "\nERROR: Failed to open results.html file\n\n";
    print {$_RESULTS_HTML} ${$_html};
    close $_RESULTS_HTML or die "\nCould not close html results file\n\n";

    return;
}

#------------------------------------------------------------------
sub writeinitialstdout {  #write initial text for STDOUT

    print {*STDOUT} "\n";
    print {*STDOUT} "Starting WebInject Engine...\n\n";

    return;
}

#------------------------------------------------------------------
sub writefinalhtml {  #write summary and closing tags for results file

    $results_html .= qq|<br /><hr /><br />\n|;
    $results_html .= qq|<b>\n|;
    $results_html .= qq|Start Time: $currentdatetime <br />\n|;
    $results_html .= qq|Total Run Time: $totalruntime seconds <br />\n|;
    $results_html .= qq|<br />\n|;
    $results_html .= qq|Test Cases Run: $totalruncount <br />\n|;
    $results_html .= qq|Test Cases Passed: $casepassedcount <br />\n|;
    $results_html .= qq|Test Cases Failed: $casefailedcount <br />\n|;
    $results_html .= qq|Verifications Passed: $passedcount <br />\n|;
    $results_html .= qq|Verifications Failed: $failedcount <br />\n|;
    $results_html .= qq|<br />\n|;
    $results_html .= qq|Average Response Time: $avgresponse seconds <br />\n|;
    $results_html .= qq|Max Response Time: $maxresponse seconds <br />\n|;
    $results_html .= qq|Min Response Time: $minresponse seconds <br />\n|;
    $results_html .= qq|</b>\n|;
    $results_html .= qq|<br />\n\n|;

    $results_html .= qq|</body>\n|;
    $results_html .= qq|</html>\n|;

    _write_html(\$results_html);
    undef $results_html;

    return;
}

#------------------------------------------------------------------
sub writefinalxml {  #write summary and closing tags for XML results file

    if ($case{sanitycheck} && ($casefailedcount > 0)) { ## sanitycheck
        $sanityresult = 'false';
    }
    else {
        $sanityresult = 'true';
    }

    $results_xml .= qq|    </testcases>\n\n|;

    $results_xml .= qq|    <test-summary>\n|;
    $results_xml .= qq|        <start-time>$currentdatetime</start-time>\n|;
    $results_xml .= qq|        <start-seconds>$TIMESECONDS</start-seconds>\n|;
    $results_xml .= qq|        <start-date-time>$STARTDATE|;
    $results_xml .= qq|T$HOUR:$MINUTE:$SECOND</start-date-time>\n|;
    $results_xml .= qq|        <total-run-time>$totalruntime</total-run-time>\n|;
    $results_xml .= qq|        <test-cases-run>$totalruncount</test-cases-run>\n|;
    $results_xml .= qq|        <test-cases-passed>$casepassedcount</test-cases-passed>\n|;
    $results_xml .= qq|        <test-cases-failed>$casefailedcount</test-cases-failed>\n|;
    $results_xml .= qq|        <verifications-passed>$passedcount</verifications-passed>\n|;
    $results_xml .= qq|        <verifications-failed>$failedcount</verifications-failed>\n|;
    $results_xml .= qq|        <assertion-skips>$totalassertionskips</assertion-skips>\n|;
    $results_xml .= qq|        <average-response-time>$avgresponse</average-response-time>\n|;
    $results_xml .= qq|        <max-response-time>$maxresponse</max-response-time>\n|;
    $results_xml .= qq|        <min-response-time>$minresponse</min-response-time>\n|;
    $results_xml .= qq|        <sanity-check-passed>$sanityresult</sanity-check-passed>\n|;
    $results_xml .= qq|        <test-file-name>$testfilename</test-file-name>\n|;
    $results_xml .= qq|    </test-summary>\n\n|;

    $results_xml .= qq|</results>\n|;

    _write_xml(\$results_xml);
    undef $results_xml;

    return;
}

#------------------------------------------------------------------
sub writefinalstdout {  #write summary and closing text for STDOUT

    print {*STDOUT} qq|Start Time: $currentdatetime\n|;
    print {*STDOUT} qq|Total Run Time: $totalruntime seconds\n\n|;

    print {*STDOUT} qq|Test Cases Run: $totalruncount\n|;
    print {*STDOUT} qq|Test Cases Passed: $casepassedcount\n|;
    print {*STDOUT} qq|Test Cases Failed: $casefailedcount\n|;
    print {*STDOUT} qq|Verifications Passed: $passedcount\n|;
    print {*STDOUT} qq|Verifications Failed: $failedcount\n\n|;

    return;
}

#------------------------------------------------------------------
sub _run_this_step {
    my ($_runon_parm) = @_;

    my @_run_on = split /[|]/, $_runon_parm; ## get the list of environments that this test step can be run on
    foreach (@_run_on) {
        if (defined $userconfig->{wif}->{environment}) {
            if ( $_ eq $userconfig->{wif}->{environment} ) {
                return 'true';
            }
        }
    }

    return;
}

## Selenium server support
#------------------------------------------------------------------
sub selenium {  ## send Selenium command and read response
    require Selenium::Remote::Driver;
    require Selenium::Chrome;
    require Data::Dumper;

    $starttimer = time;

    my $combined_response = q{};
    $request = HTTP::Request->new('GET','WebDriver');

    ## commands must be run in this order
    for (qw/command command1 command2 command3 command4 command5 command6 command7 command8 command9 command10  command11 command12 command13 command14 command15 command16 command17 command18 command19 command20/) {
        if ($case{$_}) {#perform command
            my $command = $case{$_};
            undef $selresp;
            my $eval_response = eval { eval "$command"; }; ## no critic(ProhibitStringyEval)
            #print {*STDOUT} "EVALRESP:$eval_response\n";
            if (defined $selresp) { ## phantomjs does not return a defined response sometimes
                if (($selresp =~ m/(^|=)HASH\b/) || ($selresp =~ m/(^|=)ARRAY\b/)) { ## check to see if we have a HASH or ARRAY object returned
                    my $dumper_response = Data::Dumper::Dumper($selresp);
                    print {*STDOUT} "SELRESP: DUMPED:\n$dumper_response";
                    $selresp = "selresp:DUMPED:$dumper_response";
                } else {
                    print {*STDOUT} "SELRESP:$selresp\n";
                    $selresp = "selresp:$selresp";
                }
            } else {
                print {*STDOUT} "SELRESP:<undefined>\n";
                $selresp = 'selresp:<undefined>';
            }
            $combined_response =~ s{$}{<$_>$command</$_>\n$selresp\n\n\n}; ## include it in the response
        }
    }
    $selresp = $combined_response;

    if ($selresp =~ /^ERROR/) { ## Selenium returned an error
       $selresp =~ s{^}{HTTP/1.1 500 Selenium returned an error\n\n}; ## pretend this is an HTTP response - 100 means continue
    }
    else {
       $selresp =~ s{^}{HTTP/1.1 100 OK\n\n}; ## pretend this is an HTTP response - 100 means continue
    }
    #print $response->as_string; print "\n\n";

    $endtimer = time; ## we only want to measure the time it took for the commands, not to do the screenshots and verification
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  ## elapsed time rounded to thousandths

    _get_verifytext(); ## will be injected into $selresp
    $response = HTTP::Response->parse($selresp); ## pretend the response is an http response - inject it into the object

    _screenshot();

    return;
} ## end sub

sub _get_verifytext {
    $starttimer = time; ## measure latency for the verification
    sleep 0.020; ## Sleep for 20 milliseconds

    ## multiple verifytexts are separated by commas
    if ($case{verifytext}) {
        my @parseverify = split /,/, $case{verifytext} ;
        foreach (@parseverify) {
            my $verifytext = $_;
            print {*STDOUT} "$verifytext\n";
            my @verfresp;

            if ($verifytext eq 'get_body_text') {
                print "GET_BODY_TEXT:$verifytext\n";
                eval { @verfresp =  $driver->find_element('body','tag_name')->get_text(); };
            } else {
                eval { @verfresp = $driver->$verifytext(); }; ## sometimes Selenium will return an array
            }

            $selresp =~ s{$}{\n\n\n\n}; ## put in a few carriage returns after any Selenium server message first
            my $idx = 0;
            foreach my $vresp (@verfresp) {
                $vresp =~ s/[^[:ascii:]]+//g; ## get rid of non-ASCII characters in the string element
                $idx++; ## we number the verifytexts from 1 onwards to tell them apart in the tags
                $selresp =~ s{$}{<$verifytext$idx>$vresp</$verifytext$idx>\n}; ## include it in the response
                if (($vresp =~ m/(^|=)HASH\b/) || ($vresp =~ m/(^|=)ARRAY\b/)) { ## check to see if we have a HASH or ARRAY object returned
                    my $dumper_response = Data::Dumper::Dumper($vresp);
                    my $dumped = 'dumped';
                    $selresp =~ s{$}{<$verifytext$dumped$idx>$dumper_response</$verifytext$dumped$idx>\n}; ## include it in the response
                    ## ^ means match start of string, $ end of string
                }
            }
        }
    }

    $endtimer = time; ## we only want to measure the time it took for the commands, not to do the screenshots and verification
    $verificationlatency = (int(1000 * ($endtimer - $starttimer)) / 1000);  ## elapsed time rounded to thousandths

    return;
}

sub _screenshot {
    $starttimer = time; ## measure latency for the screenshot

    my $_abs_screenshot_full = File::Spec->rel2abs( "$opt_publish_full$testnum_display$jumpbacksprint$retriesprint.png" );

    if ($case{screenshot} && (lc($case{screenshot}) eq 'false' || lc($case{screenshot}) eq 'no')) #lc = lowercase
    {
        ## take a very fast screenshot - visible window only, only works for interactive sessions
        if ($chromehandle > 0) {
            print {*STDOUT} "Taking Fast WindowCapture Screenshot\n";
            my $minicap = (`WindowCapture "$_abs_screenshot_full" $chromehandle`);
            #my $minicap = (`minicap -save "$_abs_screenshot_full" -capturehwnd $chromehandle -exit`);
            #my $minicap = (`screenshot-cmd -o "$_abs_screenshot_full" -wh "$hexchromehandle"`);
        }
    } else {
        ## take a full pagegrab - works for interactive and non interactive, but is slow i.e > 2 seconds

        ## do the screenshot, needs to be in eval in case modal popup is showing (screenshot not possible)
        eval { $png_base64 = $driver->screenshot(); };

        ## if there was an error in taking the screenshot, $@ will have content
        if ($@) {
            print {*STDOUT} "Selenium full page grab failed.\n";
            print {*STDOUT} "ERROR:$@";
        } else {
            require MIME::Base64;
            open my $FH, '>', slash_me($_abs_screenshot_full) or die "\nCould not open $_abs_screenshot_full for writing\n";
            binmode $FH; ## set binary mode
            print {$FH} MIME::Base64::decode_base64($png_base64);
            close $FH or die "\nCould not close page capture file handle\n";
        }
    }

    $endtimer = time; ## we only want to measure the time it took for the commands, not to do the screenshots and verification
    $screenshotlatency = (int(1000 * ($endtimer - $starttimer)) / 1000);  ## elapsed time rounded to thousandths

    return;
}

sub custom_select_by_text { ## usage: custom_select_by_label(Search Target, Locator, Label);
                            ##        custom_select_by_label('candidateProfileDetails_ddlCurrentSalaryPeriod','id','Daily Rate');

    my ($search_target, $locator, $labeltext) = @_;

    my $elem1 = $driver->find_element("$search_target", "$locator");
    #my $child = $driver->find_child_element($elem1, "./option[\@value='4']")->click();
    my $child = $driver->find_child_element($elem1, "./option[. = '$labeltext']")->click();

    return $child;
}

sub custom_clear_and_send_keys { ## usage: custom_clear_and_send_keys(Search Target, Locator, Keys);
                                 ##        custom_clear_and_send_keys('candidateProfileDetails_txtPostCode','id','WC1X 8TG');

    my ($search_target, $locator, $sendkeys) = @_;

    my $elem1 = $driver->find_element("$search_target", "$locator")->clear();
    my $resp1 = $driver->find_element("$search_target", "$locator")->send_keys("$sendkeys");

    return $resp1;
}

sub custom_mouse_move_to_location { ## usage: custom_mouse_move_to_location(Search Target, Locator, xoffset, yoffset);
                                    ##        custom_mouse_move_to_location('closeBtn','id',3,4);
                                    ##        custom_mouse_move_to_location('closeBtn','id'); # offsets are optional 

    my ($_search_target, $_locator, $_xoffset, $_yoffset) = @_;
    $_xoffset = int $_xoffset;
    $_yoffset = int $_yoffset;

    my $_element = $driver->find_element("$_search_target", "$_locator");
    my $_child = $driver->mouse_move_to_location(element => $_element, xoffset => $_xoffset, yoffset => $_yoffset);

    return $_child;
}

sub custom_switch_to_window { ## usage: custom_switch_to_window(window number);
                              ##        custom_switch_to_window(0);
                              ##        custom_switch_to_window(1);
    my ($_window_number) = @_;

    require Data::Dumper;

    my $handles = $driver->get_window_handles;
    print Data::Dumper::Dumper($handles);
    my $_resp =  $driver->switch_to_window($handles->[$_window_number]);

    return $_resp;
}

sub custom_js_click { ## usage: custom_js_click(id);
                      ##        custom_js_click('btnSubmit');

    my ($id_to_click) = @_;

    my $script = q{
        var arg1 = arguments[0];
        var elem = window.document.getElementById(arg1).click();
        return elem;
    };
    my $resp1 = $driver->execute_script($script,$id_to_click);

    return $resp1;
}

sub custom_js_set_value {  ## usage: custom_js_set_value(id,value);
                           ##        custom_js_set_value('cvProvider_filCVUploadFile','{CWD}\testdata\MyCV.doc');
                           ##
                           ##        Single quotes will not treat \ as escape codes

    my ($id_to_set_value, $value_to_set) = @_;

    my $script = q{
        var arg1 = arguments[0];
        var arg2 = arguments[1];
        var elem = window.document.getElementById(arg1).value=arg2;
        return elem;
    };
    my $resp1 = $driver->execute_script($script,$id_to_set_value,$value_to_set);

    return $resp1;
}

sub custom_js_make_field_visible_to_webdriver {     ## usage: custom_js_make_field_visible(id);
                                                    ##        custom_js_make_field_visible('cvProvider_filCVUploadFile');

    my ($id_to_set_css) = @_;

    my $script = q{
        var arg1 = arguments[0];
        window.document.getElementById(arg1).style.width = '5px';
        var elem = window.document.getElementById(arg1).style.height = '5px';
        return elem;
    };
    my $resp1 = $driver->execute_script($script,$id_to_set_css);

    return $resp1;
}

sub custom_check_element_within_pixels {     ## usage: custom_check_element_within_pixels(searchTarget,id,xBase,yBase,pixelThreshold);
                                             ##        custom_check_element_within_pixels('txtEmail','id',193,325,30);

    my ($search_target, $locator, $x_base, $y_base, $pixel_threshold) = @_;

    ## get_element_location will return a reference to a hash associative array
    ## http://www.troubleshooters.com/codecorn/littperl/perlscal.htm
    ## the array will look something like this
    # { 'y' => 325, 'hCode' => 25296896, 'x' => 193, 'class' => 'org.openqa.selenium.Point' };
    my ($location) = $driver->find_element("$search_target", "$locator")->get_element_location();

    ## if the element doesn't exist, we get an empty output, so presumably this subroutine just dies and the program carries on

    ## we use the -> operator to get to the underlying values in the hash array
    my $x = $location->{x};
    my $y = $location->{y};

    my $x_diff = abs $x_base - $x;
    my $y_diff = abs $y_base - $y;

    my $message = "Pixel threshold check passed - $search_target is $x_diff,$y_diff (x,y) pixels removed from baseline of $x_base,$y_base; actual was $x,$y";

    if ($x_diff > $pixel_threshold || $y_diff > $pixel_threshold) {
        $message = "Pixel threshold check failed - $search_target is $x_diff,$y_diff (x,y) pixels removed from baseline of $x_base,$y_base; actual was $x,$y";
    }

    return $message;
}

sub custom_wait_for_text_present { ## usage: custom_wait_for_text_present('Search Text',Timeout);
                                   ##        custom_wait_for_text_present('Job title',10);
                                   ##
                                   ## waits for text to appear in page source

    my ($searchtext, $timeout) = @_;

    print {*STDOUT} "SEARCHTEXT:$searchtext\n";
    print {*STDOUT} "TIMEOUT:$timeout\n";

    my $timestart = time;
    my @resp1;
    my $foundit = 'false';

    while ( (($timestart + $timeout) > time) && $foundit eq 'false' ) {
        eval { @resp1 = $driver->get_page_source(); };
        foreach my $resp (@resp1) {
            if ($resp =~ m{$searchtext}si) {
                $foundit = 'true';
            }
        }
        if ($foundit eq 'false')
        {
            sleep 0.1; # Sleep for 0.1 seconds
        }
    }
    my $trytime = ( int( (time - $timestart) *10 ) / 10);

    my $returnmsg;
    if ($foundit eq 'true') {
        $returnmsg = "Found sought text in page source after $trytime seconds";
    }
    else
    {
        $returnmsg = "Did not find sought text in page source, timed out after $trytime seconds";
    }

    return $returnmsg;
}

sub custom_wait_for_text_not_present { ## usage: custom_wait_for_text_not_present('Search Text',Timeout);
                                       ##        custom_wait_for_text_not_present('Job title',10);
                                       ##
                                       ## waits for text to disappear from page source

    my ($searchtext, $timeout) = @_;

    print {*STDOUT} "DO NOT WANT TEXT:$searchtext\n";
    print {*STDOUT} "TIMEOUT:$timeout\n";

    my $timestart = time;
    my @resp1;
    my $foundit = 'true';

    while ( (($timestart + $timeout) > time) && $foundit eq 'true' ) {
        eval { @resp1 = $driver->get_page_source(); };
        foreach my $resp (@resp1) {
            if ($resp =~ m{$searchtext}si) {
                sleep 0.1; ## sleep for 0.1 seconds
            } else {
                $foundit = 'false';
            }
        }
    }

    my $trytime = ( int( (time - $timestart) *10 ) / 10);

    my $returnmsg;
    if ($foundit eq 'true') {
        $returnmsg = "TIMEOUT: Text was *still* in page source after $trytime seconds";
    } else {
        $returnmsg = "SUCCESS: Did not find sought text in page source after $trytime seconds";
    }

    return $returnmsg;
}

sub custom_wait_for_text_visible { ## usage: custom_wait_for_text_visible('Search Text','target', 'locator', Timeout);
                                   ##         custom_wait_for_text_visible('Job title', 'body', 'tag_name', 10);
                                   ##
                                   ## Waits for text to appear visible in the body text. This function can sometimes be very slow on some pages.

    my ($searchtext, $target, $locator, $timeout) = @_;

    print {*STDOUT} "VISIBLE SEARCH TEXT:$searchtext\n";
    print {*STDOUT} "TIMEOUT:$timeout\n";

    my $timestart = time;
    my @resp1;
    my $foundit = 'false';

    while ( (($timestart + $timeout) > time) && $foundit eq 'false' ) {
        eval { @resp1 = $driver->find_element($target,$locator)->get_text(); };
        foreach my $resp (@resp1) {
            if ($resp =~ m{$searchtext}si) {
                $foundit = 'true';
            }
        }
        if ($foundit eq 'false')
        {
            sleep 0.5; ## sleep for 0.5 seconds
        }
    }

    my $trytime = ( int( (time() - $timestart) *10 ) / 10);

    my $returnmsg;
    if ($foundit eq 'true') {
        $returnmsg = "Found sought text visible after $trytime seconds";
    }
    else
    {
        $returnmsg = "Did not find sought text visible, timed out after $trytime seconds";
    }

    return $returnmsg;
}

sub custom_wait_for_text_not_visible { ## usage: custom_wait_for_text_not_visible('Search Text',Timeout);
                                       ##        custom_wait_for_text_not_visible('This job has been emailed to',10);
                                       ##
                                       ## waits for text to be not visible in the body text - e.g. closing a JavaScript popup

    my ($searchtext, $timeout) = @_;

    print {*STDOUT} "NOT VISIBLE SEARCH TEXT:$searchtext\n";
    print {*STDOUT} "TIMEOUT:$timeout\n";

    my $timestart = time;
    my @resp1;
    my $foundit = 'true'; ## we assume it is there already (from previous test step), otherwise it makes no sense to call this

    while ( (($timestart + $timeout) > time) && $foundit eq 'true' ) {
        eval { @resp1 = $driver->find_element('body','tag_name')->get_text(); };
        foreach my $resp (@resp1) {
            if (not ($resp =~ m{$searchtext}si)) {
                $foundit = 'false';
            }
        }
        if ($foundit eq 'true')
        {
            sleep 0.1; ## sleep for 0.1 seconds
        }
    }

    my $trytime = ( int( (time - $timestart) *10 ) / 10);

    my $returnmsg;
    if ($foundit eq 'false') {
        $returnmsg = "Sought text is now not visible after $trytime seconds";
    }
    else
    {
        $returnmsg = "Sought text still visible, timed out after $trytime seconds";
    }

    return $returnmsg;
}

sub custom_wait_for_element_present { ## usage: custom_wait_for_element_present('element-name','element-type','Timeout');
                                      ##        custom_wait_for_element_present('menu-search-icon','id','5');

    my ($element_name, $element_type, $timeout) = @_;

    print {*STDOUT} "SEARCH ELEMENT[$element_name], ELEMENT TYPE[$element_type], TIMEOUT[$timeout]\n";

    my $timestart = time;
    my $foundit = 'false';
    undef $element;

    while ( (($timestart + $timeout) > time) && $foundit eq 'false' )
    {
        eval { $element = $driver->find_element("$element_name","$element_type"); };
        if ($element)
        {
            $foundit = 'true';
        }
        if ($foundit eq 'false')
        {
            sleep 0.1; ## Sleep for 0.1 seconds
        }
    }

    my $trytime = ( int( (time - $timestart) *10 ) / 10);

    my $returnmsg;
    if ($foundit eq 'true') {
        $returnmsg = "Found sought element after $trytime seconds";
    }
    else
    {
        $returnmsg = "Did not find sought element, timed out after $trytime seconds";
    }

    #print {*STDOUT} "$returnmsg\n";
    return $returnmsg;
}

sub custom_wait_for_element_visible { ## usage: custom_wait_for_element_visible('element-name','element-type','Timeout');
                                      ##        custom_wait_for_element_visible('menu-search-icon','id','5');

    my ($element_name, $element_type, $timeout) = @_;

    print {*STDOUT} "SEARCH ELEMENT[$element_name], ELEMENT TYPE[$element_type], TIMEOUT[$timeout]\n";

    my $timestart = time;
    my $foundit = 'false';
    my $find_element;

    while ( (($timestart + $timeout) > time) && $foundit eq 'false' )
    {
        eval { $find_element = $driver->find_element("$element_name","$element_type")->is_displayed(); };
        if ($find_element)
        {
            $foundit = 'true';
        }
        if ($foundit eq 'false')
        {
            sleep 0.1; ## Sleep for 0.1 seconds
        }
    }
    my $trytime = ( int( (time - $timestart) *10 ) / 10);

    my $returnmsg;
    if ($foundit eq 'true') {
        $returnmsg = "Found sought element visible after $trytime seconds";
    }
    else
    {
        $returnmsg = "Did not find sought element visible, timed out after $trytime seconds";
    }

    #print {*STDOUT} "$returnmsg\n";
    return $returnmsg;
}


#------------------------------------------------------------------
sub addcookie { ## add a cookie like JBM_COOKIE=4830075
    if ($case{addcookie}) { ## inject in an additional cookie for this test step only if specified
        my $cookies = $request->header('Cookie');
        if (defined $cookies) {
            #print "[COOKIE] $cookies\n";
            $request->header('Cookie' => "$cookies; " . $case{addcookie});
            #print '[COOKIE UPDATED] ' . $request->header('Cookie') . "\n";
        } else {
            #print "[COOKIE] <UNDEFINED>\n";
            $request->header('Cookie' => $case{addcookie});
            #print "[COOKIE UPDATED] " . $request->header('Cookie') . "\n";
        }
        undef $cookies;
    }

    return;
}

#------------------------------------------------------------------
sub gethrefs { ## get page href assets matching a list of ending patterns, separate multiple with |
               ## gethrefs=".less|.css"
    if ($case{gethrefs}) {
        my $match = 'href=';
        my $delim = q{"}; #"
        getassets ($match,$delim,$delim,$case{gethrefs}, 'hrefs');
    }

    return;
}

#------------------------------------------------------------------
sub getsrcs { ## get page src assets matching a list of ending patterns, separate multiple with |
              ## getsrcs=".js|.png|.jpg|.gif"
    if ($case{getsrcs}) {
        my $match = 'src=';
        my $delim = q{"}; #"
        getassets ($match, $delim, $delim, $case{getsrcs}, 'srcs');
    }

    return;
}

#------------------------------------------------------------------
sub getbackgroundimages { ## style="background-image: url( )"

    if ($case{getbackgroundimages}) {
        my $match = 'style="background-image: url';
        my $leftdelim = '\(';
        my $rightdelim = '\)';
        getassets ($match,$leftdelim,$rightdelim,$case{getbackgroundimages}, 'bg-images');
    }

    return;
}

#------------------------------------------------------------------
sub getassets { ## get page assets matching a list for a reference type
                ## getassets ('href',q{"},q{"},'.less|.css')

    my ($match, $leftdelim, $rightdelim, $assetlist, $_type) = @_;

    my ($startassetrequest, $endassetrequest, $assetlatency);
    my ($assetref, $ururl, $asseturl, $path, $filename, $assetrequest, $assetresponse);

    my $page = $response->as_string;

    my @extensions = split /[|]/, $assetlist ;

    foreach my $extension (@extensions) {

        #while ($page =~ m{$assettype="([^"]*$extension)["\?]}g) ##" Iterate over all the matches to this extension
        print "\n $match$leftdelim([^$rightdelim]*$extension)[$rightdelim\?] \n";
        while ($page =~ m{$match$leftdelim([^$rightdelim]*$extension)[$rightdelim?]}g) ##" Iterate over all the matches to this extension
        {
            $startassetrequest = time;

            $assetref = $1;
            #print "$extension: $assetref\n";

            $ururl = URI::URL->new($assetref, $case{url}); ## join the current page url together with the href of the asset
            $asseturl = $ururl->abs; ## determine the absolute address of the asset
            #print "$asseturl\n\n";
            $path = $asseturl->path; ## get the path portion of the asset location
            $filename = basename($path); ## get the filename from the path
            print {*STDOUT} "  GET Asset [$filename] ...";

            $assetrequest = HTTP::Request->new('GET',"$asseturl");
            $cookie_jar->add_cookie_header($assetrequest); ## session cookies will be needed

            $assetresponse = $useragent->request($assetrequest);

            open my $RESPONSEASFILE, '>', "$outputfolder/$filename" or die "\nCould not open asset file $outputfolder/$filename for writing\n"; #open in clobber mode
            binmode $RESPONSEASFILE; ## set binary mode
            print {$RESPONSEASFILE} $assetresponse->content, q{}; ## content just outputs the content, whereas as_string includes the response header
            close $RESPONSEASFILE or die "\nCould not close asset file\n";

            if ($_type eq 'hrefs') { push @hrefs, $filename; }
            if ($_type eq 'srcs') { push @srcs, $filename; }
            if ($_type eq 'bg-images') { push @bg_images, $filename; }

            $endassetrequest = time;
            $assetlatency = (int(1000 * ($endassetrequest - $startassetrequest)) / 1000);  ## elapsed time rounded to thousandths
            print {*STDOUT} " $assetlatency s\n";

        } ## end while

    } ## end foreach

    return;
}

#------------------------------------------------------------------
sub savepage {## save the page in a cache to enable auto substitution of hidden fields like __VIEWSTATE and the dynamic component of variable names

    my $page_action;
    my $page_index; ## where to save the page in the cache (array of pages)

    ## decide if we want to save this page - needs a method post action
    if ( ($response->as_string =~ m{method="post" action="([^"]*)"}s) || ($response->as_string =~ m{action="([^"]*)" method="post"}s) ) { ## look for the method post action
        $page_action = $1;
        #print {*STDOUT} qq|\n ACTION $page_action\n|;
    } else {
        #print {*STDOUT} qq|\n ACTION none\n\n|;
    }

    if (defined $page_action) { ## ok, so we save this page

        #print {*STDOUT} qq| SAVING $page_action (BEFORE)\n|;
        $page_action =~ s{[?].*}{}si; ## we only want everything to the left of the ? mark
        $page_action =~ s{http.?://}{}si; ## remove http:// and https://
        #print {*STDOUT} qq| SAVING $page_action (AFTER)\n\n|;

        ## we want to overwrite any page with the same name in the cache to prevent weird errors
        my $match_url = $page_action;
        $match_url =~ s{^.*?/}{/}s; ## remove everything to the left of the first / in the path

        ## check to see if we already have this page in the cache, if so, just overwrite it
        $page_index = _find_page_in_cache($match_url);

        my $max_cache_size = 5; ## maximum size of the cache (counting starts at 0)
        ## decide if we need a new cache entry, or we must overwrite the oldest page in the cache
        if (not defined $page_index) { ## the page is not in the cache
            if ($#pagenames == $max_cache_size) {## the cache is full - so we need to overwrite the oldest page in the cache
                $page_index = _find_oldest_page_in_cache();
                #print {*STDOUT} qq|\n Overwriting - Oldest Page Index: $page_index\n\n|; #debug
            } else {
                $page_index = $#pagenames + 1;
                #out print {*STDOUT} qq| Index $page_index available \n\n|;
            }
        }

        ## update the global variables
        $pageupdatetimes[$page_index] = time; ## save time so we overwrite oldest when cache is full
        $pagenames[$page_index] = $page_action; ## save page name
        $pages[$page_index] = $response->as_string; ## save page source

        #print {*STDOUT} " Saved $pageupdatetimes[$page_index]:$pagenames[$page_index] \n\n";

        ## debug - write out the contents of the cache
        #for my $i (0 .. $#pagenames) {
        #    print {*STDOUT} " $i:$pageupdatetimes[$i]:$pagenames[$i] \n"; #debug
        #}
        #print {*STDOUT} "\n";

    } # end if - action found

    return;
}

sub _find_oldest_page_in_cache {

    ## assume the first page in the cache is the oldest
    my $oldest_index = 0;
    my $oldest_page_time = $pageupdatetimes[0];

    ## if we find an older updated time, use that instead
    for my $i (0 .. $#pageupdatetimes) {
        if ($pageupdatetimes[$i] < $oldest_page_time) { $oldest_index = $i; $oldest_page_time = $pageupdatetimes[$i]; }
    }

    return $oldest_index;
}

#------------------------------------------------------------------
sub autosub {## auto substitution - {DATA} and {NAME}
## {DATA} finds .NET field value from a previous test case and puts it in the postbody - no need for manual parseresponse
## Example: postbody="txtUsername=testuser&txtPassword=123&__VIEWSTATE={DATA}"
##
## {NAME} matches a dynamic component of a field name by looking at the page source of a previous test step
##        This is very useful if the field names change after a recompile, or a Content Management System is in use.
## Example: postbody="txtUsername{NAME}=testuser&txtPassword=123&__VIEWSTATE=456"
##          In this example, the actual user name field may have been txtUsername_xpos5_ypos8_33926509
##

    my ($postbody, $posttype, $posturl) = @_;

    my @postfields;

    ## separate the fields
    if ($posttype eq 'normalpost') {
        @postfields = split /\&/, $postbody ; ## & is separator
    } else {
        ## assumes that double quotes on the outside, internally single qoutes
        ## enhancements needed
        ##   1. subsitute out blank space first between the field separators
        @postfields = split /\'\,/, $postbody ; #separate the fields
    }

    ## debug - print the array
    #print {*STDOUT} " \n There are ".($#postfields+1)." fields in the postbody: \n"; #debug
    #for my $i (0 .. $#postfields) {
    #    print {*STDOUT} ' Field '.($i+1).": $postfields[$i] \n";
    #}

    ## work out pagename to use for matching purposes
    $posturl =~ s{[?].*}{}si; ## we only want everything to the left of the ? mark
    $posturl =~ s{http.?://}{}si; ## remove http:// and https://
    $posturl =~ s{^.*?/}{/}s; ## remove everything to the left of the first / in the path
    print {*STDOUT} qq| POSTURL $posturl \n|; #debug

    my $pageid = _find_page_in_cache($posturl.q{$});
    if (not defined $pageid) {
        $posturl =~ s{^.*/}{/}s; ## remove the path entirely, except for the leading slash
        #print {*STDOUT} " TRY WITH PAGE NAME ONLY    : $posturl".'$'."\n";
        $pageid = _find_page_in_cache($posturl.q{$}); ## try again without the full path
    }
    if (not defined $pageid) {
        $posturl =~ s{^.*/}{/}s; ## remove the path entirely, except for the page name itself
        #print {*STDOUT} " REMOVE PATH                : $posturl".'$'."\n";
        $pageid = _find_page_in_cache($posturl.q{$}); ## try again without the full path
    }
    if (not defined $pageid) {
        $posturl =~ s{^.*/}{}s; ## remove the path entirely, except for the page name itself
        #print {*STDOUT} " REMOVE LEADING /           : $posturl".'$'."\n";
        $pageid = _find_page_in_cache($posturl.q{$}); ## try again without the full path
    }
    if (not defined $pageid) {
        #print {*STDOUT} " DESPERATE MODE - NO ANCHOR : $posturl\n";
        _find_page_in_cache($posturl);
    }

    ## there is heavy use of regex in this sub, we need to ensure they are optimised
    #my $startlooptimer = time;

    ## time for substitutions
    if (defined $pageid) { ## did we find match?
        #print {*STDOUT} " ID MATCH $pageid \n";
        for my $i (0 .. $#postfields) { ## loop through each of the fields being posted
            ## substitute {NAME} for actual
            $postfields[$i] = _substitute_name($postfields[$i], $pageid, $posttype);

            ## substitute {DATA} for actual
            $postfields[$i] = _substitute_data($postfields[$i], $pageid, $posttype);
        }
    }

    ## done all the substitutions, now put it all together again
    if ($posttype eq 'normalpost') {
        $postbody = join q{&}, @postfields;
    } else {
        ## assumes that double quotes on the outside, internally single qoutes
        ## enhancements needed
        ##   1. subsitute out blank space first between the field separators
        $postbody = join q{',}, @postfields; #'
    }
    #out print {*STDOUT} qq|\n\n POSTBODY is $postbody \n|;

    #my $looplatency = (int(1000 * (time - $startlooptimer)) / 1000);  ## elapsed time rounded to thousandths
    ## debug - make sure all the regular expressions are efficient
    #print {*STDOUT} qq| Looping took $looplatency \n|; #debug

    return $postbody;
}

sub _substitute_name {
    my ($post_field, $page_id, $post_type) = @_;

    my $dotx;
    my $doty;

    ## does the field name end in .x e.g. btnSubmit.x? The .x bit won't be in the saved page
    if ( $post_field =~ m{[.]x[=']} ) { ## does it end in .x? #'
        #out print {*STDOUT} qq| DOTX found in $post_field \n|;
        $dotx = 'true';
        $post_field =~ s{[.]x}{}; ## get rid of the .x, we'll have to put it back later
    }

    ## does the field name end in .y e.g. btnSubmit.y? The .y bit won't be in the saved page
    if ( $post_field =~ m/[.]y[=']/ ) { ## does it end in .y? #'
        #out print {*STDOUT} qq| DOTY found in $post_field \n|;
        $doty = 'true';
        $post_field =~ s{[.]y}{}; ## get rid of the .y, we'll have to put it back later
    }

    ## look for characters to the left and right of {NAME} and save them
    if ( $post_field =~ m/([^']{0,70}?)[{]NAME[}]([^=']{0,70})/s ) { ## ' was *?, {0,70}? much quicker
        my $lhsname = $1;
        my $rhsname = $2;

        $lhsname =~ s{\$}{\\\$}g; ## protect $ with \$
        $lhsname =~ s{[.]}{\\\.}g; ## protect . with \.
        #print {*STDOUT} qq| LHS of {NAME}: [$lhsname] \n|;

        $rhsname =~ s{%24}{\$}g; ## change any encoding for $ (i.e. %24) back to a literal $ - this is what we'll really find in the html source
        $rhsname =~ s{\$}{\\\$}g; ## protect the $ with a \ in further regexs
        $rhsname =~ s{[.]}{\\\.}g; ## same for the .
        #print {*STDOUT} qq| RHS of {NAME}: [$rhsname] \n|;

        ## find out what to substitute it with, then do the substitution
        ##
        ## saved page source will contain something like
        ##    <input name="pagebody_3$left_7$txtUsername" id="pagebody_3_left_7_txtUsername" />
        ## so this code will find that {NAME}Username will match pagebody_3$left_7$txt for {NAME}
        if ($pages[$page_id] =~ m/name=['"]$lhsname([^'"]{0,70}?)$rhsname['"]/s) { ## "
            my $name = $1;
            #out print {*STDOUT} qq| NAME is $name \n|;

            ## substitute {NAME} for the actual (dynamic) value
            $post_field =~ s/{NAME}/$name/;
            #print {*STDOUT} qq| SUBBED_NAME is $post_field \n|;
        }
    }

    ## did we take out the .x? we need to put it back
    if (defined $dotx) {
        if ($post_type eq 'normalpost') {
            $post_field =~ s{[=]}{\.x\=};
        } else {
            $post_field =~ s{['][ ]?\=}{\.x\' \=}; #[ ]? means match 0 or 1 space #'
        }
        #print {*STDOUT} qq| DOTX restored to $post_field \n|;
    }

    ## did we take out the .y? we need to put it back
    if (defined $doty) {
     if ($post_type eq 'normalpost') {
        $post_field =~ s{[=]}{\.y\=};
     } else {
        $post_field =~ s{['][ ]?\=}{\.y\' \=}; #'
     }
        #print {*STDOUT} qq| DOTY restored to $post_field \n|;
    }

    return $post_field;
}

sub _substitute_data {
    my ($post_field, $page_id, $post_type) = @_;

    my $target_field;

    if ($post_type eq 'normalpost') {
        if ($post_field =~ m/(.{0,70}?)=[{]DATA}/s) {
            $target_field = $1;
            #print {*STDOUT} qq| Normal Field $fieldname has {DATA} \n|; #debug
        }
    }

    if ($post_type eq 'multipost') {
        if ($post_field =~ m/['](.{0,70}?)['].{0,70}?[{]DATA}/s) {
            $target_field = $1;
            #print {*STDOUT} qq| Multi Field $fieldname has {DATA} \n|; #debug
        }
    }

    ## find out what to substitute it with, then do the substitution
    if (defined $target_field) {
        $target_field =~ s{\$}{\\\$}; ## protect $ with \$ for final substitution
        $target_field =~ s{[.]}{\\\.}; ## protect . with \. for final substitution
        if ($pages[$page_id] =~ m/="$target_field" [^\>]*value="(.*?)"/s) {
            my $data = $1;
            #print {*STDOUT} qq| DATA is $data \n|; #debug

            ## normal post must be escaped
            if ($post_type eq 'normalpost') {
                $data = uri_escape($data);
                #print {*STDOUT} qq| URLESCAPE!! \n|; #debug
            }

            ## substitute in the data
            if ($post_field =~ s/{DATA}/$data/) {
                #print {*STDOUT} qq| SUBBED_FIELD is $postfields[$i] \n|; #debug
            }

        }
    }

    return $post_field;
}

sub _find_page_in_cache {

    my ($post_url) = @_;

    ## see if we have stored this page
    if ($pagenames[0]) { ## does the array contain at least one entry?
        for my $i (0 .. $#pagenames) {
            if ($pagenames[$i] =~ m/$post_url/si) { ## can we find the post url within the current saved action url?
            #print {*STDOUT} qq| MATCH at position $i\n|; #debug
            return $i;
            } else {
                #print {*STDOUT} qq| NO MATCH on $i:$pagenames[$i]\n|; #debug
            }
        }
    } else {
        #print {*STDOUT} qq| NO CACHED PAGES! \n|; #debug
    }

    return;
}
#------------------------------------------------------------------
sub httpget {  #send http request and read response

    $request = HTTP::Request->new('GET',"$case{url}");

    #1.42 Moved cookie management up above addheader as per httppost_form_data
    $cookie_jar->add_cookie_header($request);
    #print $request->as_string; print "\n\n";

    addcookie (); ## append additional cookies rather than overwriting with add header

    if ($case{addheader}) {  #add an additional HTTP Header if specified
        my @addheaders = split /[|]/, $case{addheader} ;  #can add multiple headers with a pipe delimiter
        foreach (@addheaders) {
            $_ =~ m/(.*): (.*)/;
            if ($1) {$request->header($1 => $2);}  #using HTTP::Headers Class
        }
    }


    $starttimer = time;
    $response = $useragent->request($request);
    $endtimer = time;
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  #elapsed time rounded to thousandths
    #print $response->as_string; print "\n\n";

    $cookie_jar->extract_cookies($response);
    #print $cookie_jar->as_string; print "\n\n";

    savepage (); ## save page in the cache for the auto substitutions

    return;
}

#------------------------------------------------------------------
sub httpdelete {

    httpsend('DELETE');

    return;
}

#------------------------------------------------------------------
sub httppost {

    httpsend('POST');

    return;
}

#------------------------------------------------------------------
sub httpput {

    httpsend('PUT');

    return;
}

#------------------------------------------------------------------
sub httpsend {  # send request based on specified encoding and method (verb)
    my ($_verb) = @_;

    if ($case{posttype}) {
         if (($case{posttype} =~ m{application/x-www-form-urlencoded}) or ($case{posttype} =~ m{application/json})) { httpsend_form_urlencoded($_verb); } ## application/json support
         elsif ($case{posttype} =~ m{multipart/form-data}) { httpsend_form_data($_verb); }
         elsif (($case{posttype} =~ m{text/xml}) or ($case{posttype} =~ m{application/soap+xml})) { httpsend_xml($_verb); }
         else { print {*STDERR} qq|ERROR: Bad Form Encoding Type, I only accept "application/x-www-form-urlencoded", "application/json", "multipart/form-data", "text/xml", "application/soap+xml" \n|; }
       }
    else {
        $case{posttype} = 'application/x-www-form-urlencoded';
        httpsend_form_urlencoded($_verb);  #use "x-www-form-urlencoded" if no encoding is specified
    }

    savepage (); ## for auto substitutions

    return;
}

#------------------------------------------------------------------
sub httpsend_form_urlencoded {  #send application/x-www-form-urlencoded or application/json HTTP request and read response
    my ($_verb) = @_;

    my $substituted_postbody; ## auto substitution
    $substituted_postbody = autosub("$case{postbody}", 'normalpost', "$case{url}");

    $request = HTTP::Request->new($_verb,"$case{url}");
    $request->content_type("$case{posttype}");
    #$request->content("$case{postbody}");
    $request->content("$substituted_postbody");

    ## moved cookie management up above addheader as per httppost_form_data
    $cookie_jar->add_cookie_header($request);

    addcookie (); ## append to additional cookies rather than overwriting with add header

    if ($case{addheader}) {  # add an additional HTTP Header if specified
        my @addheaders = split /[|]/, $case{addheader} ;  #can add multiple headers with a pipe delimiter
        foreach (@addheaders) {
            $_ =~ m{(.*): (.*)};
            if ($1) {$request->header($1 => $2);}  #using HTTP::Headers Class
        }
        #$case{addheader} = q{}; ## why is this line here? Fails with retry, so commented out
    }

    #print $request->as_string; print "\n\n";
    $starttimer = time;
    $response = $useragent->request($request);
    $endtimer = time;
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  #elapsed time rounded to thousandths
    #print $response->as_string; print "\n\n";

    $cookie_jar->extract_cookies($response);
    #print $cookie_jar->as_string; print "\n\n";

    return;
}

#------------------------------------------------------------------
sub httpsend_xml{  #send text/xml HTTP request and read response
    my ($_verb) = @_;

    my @parms;
    my $len;
    #my $idx;
    my $fieldname;
    my $fieldvalue;
    my $subname;

    #read the xml file specified in the testcase
    my @xmlbody;
    if ( $case{postbody} =~ m/file=>(.*)/i ) {
        open my $XMLBODY, '<', slash_me($1) or die "\nError: Failed to open text/xml file $1\n\n";  #open file handle
        @xmlbody = <$XMLBODY>;  #read the file into an array
        close $XMLBODY or die "\nCould not close xml file to be posted\n\n";
    }

    if ($case{parms}) { #is there a postbody for this testcase - if so need to subtitute in fields
       @parms = split /\&/, $case{parms} ; #& is separator
       $len = @parms; #number of items in the array
       #out print {*STDOUT} qq| \n There are $len fields in the parms \n|;

       #loop through each of the fields and substitute
       foreach my $idx (1..$len) {
            $fieldname = q{};
            #out print {*STDOUT} qq| \n parms $idx: $parms[$idx-1] \n |;
            if ($parms[$idx-1] =~ m/(.*?)\=/s) { #we only want everything to the left of the = sign
                $fieldname = $1;
                #out print {*STDOUT} qq| fieldname: $fieldname \n|;
            }
            $fieldvalue = q{};
            if ($parms[$idx-1] =~ m/\=(.*)/s) { #we only want everything to the right of the = sign
                $fieldvalue = $1;
                #out print {*STDOUT} qq| fieldvalue: $fieldvalue \n\n|;
            }

            #make the substitution
            foreach (@xmlbody) {
                #non escaped fields
                $_ =~ s{\<$fieldname\>.*?\<\/$fieldname\>}{\<$fieldname\>$fieldvalue\<\/$fieldname\>};

                #escaped fields
                $_ =~ s{\&lt;$fieldname\&gt;.*?\&lt;\/$fieldname\&gt;}{\&lt;$fieldname\&gt;$fieldvalue\&lt;\/$fieldname\&gt;};

                #attributes
                # ([^a-zA-Z]) says there must be a non alpha so that bigid and id and treated separately
                # $1 will put it back - otherwise it'll be eaten
                $_ =~ s{([^a-zA-Z])$fieldname\=\".*?\"}{$1$fieldname\=\"$fieldvalue\"}; ## no critic(ProhibitEnumeratedClasses)

                #variable substitution
                $subname = $fieldname;
                if ( $subname =~ s{__}{} ) {#if there are double underscores, like __salarymax__ then replace it
                    $_ =~ s{__$subname}{$fieldvalue}g;
                }

            }

       }

    }

    $request = HTTP::Request->new($_verb, "$case{url}");
    $request->content_type("$case{posttype}");
    $request->content(join q{ }, @xmlbody);  #load the contents of the file into the request body

## moved cookie management up above addheader as per httpsend_form_data
    $cookie_jar->add_cookie_header($request);

    if ($case{addheader}) {  #add an additional HTTP Header if specified
        my @addheaders = split /[|]/, $case{addheader} ;  #can add multiple headers with a pipe delimiter
        foreach (@addheaders) {
            $_ =~ m/(.*): (.*)/;
            if ($1) {$request->header($1 => $2);}  #using HTTP::Headers Class
        }
        #$case{addheader} = q{}; ## why is this line here? Fails with retry, so commented out
    }

    #print $request->as_string; print "\n\n";
    $starttimer = time;
    $response = $useragent->request($request);
    $endtimer = time;
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  #elapsed time rounded to thousandths
    #print $response->as_string; print "\n\n";

    $cookie_jar->extract_cookies($response);
    #print $cookie_jar->as_string; print "\n\n";

    return;
}

#------------------------------------------------------------------
sub httpsend_form_data {  #send multipart/form-data HTTP request and read response
    my ($_verb) = @_;

    my $substituted_postbody; ## auto substitution
    $substituted_postbody = autosub("$case{postbody}", 'multipost', "$case{url}");

    my %my_content_;
    eval "\%my_content_ = $substituted_postbody"; ## no critic(ProhibitStringyEval)
    if ($_verb eq 'POST') {
        $request = POST "$case{url}", Content_Type => "$case{posttype}", Content => \%my_content_;
    } elsif ($_verb eq 'PUT') {
        $request = PUT "$case{url}", Content_Type => "$case{posttype}", Content => \%my_content_;
    } else {
        die "HTTP METHOD of DELETE not supported for multipart/form-data \n";
    }
    $cookie_jar->add_cookie_header($request);
    #print $request->as_string; print "\n\n";

    addcookie (); ## append additional cookies rather than overwriting with add header

    if ($case{addheader}) {  #add an additional HTTP Header if specified
        my @addheaders = split /[|]/, $case{addheader} ;  #can add multiple headers with a pipe delimiter
        foreach (@addheaders) {
            $_ =~ m/(.*): (.*)/;
            if ($1) {$request->header($1 => $2);}  #using HTTP::Headers Class
        }
    }

    $starttimer = time;
    $response = $useragent->request($request);
    $endtimer = time;
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  #elapsed time rounded to thousandths
    #print $response->as_string; print "\n\n";

    $cookie_jar->extract_cookies($response);
    #print $cookie_jar->as_string; print "\n\n";

    return;
}

#------------------------------------------------------------------
sub cmd {  ## send terminal command and read response

    my $combined_response=q{};
    $request = HTTP::Request->new('GET','CMD');
    $starttimer = time;

    for (qw/command command1 command2 command3 command4 command5 command6 command7 command8 command9 command10 command11 command12 command13 command14 command15 command16 command17 command18 command19 command20/) {
        if ($case{$_}) {#perform command
            my $cmd = $case{$_};
            $cmd =~ s/\%20/ /g; ## turn %20 to spaces for display in log purposes
            _shell_adjust(\$cmd);
            #$request = new HTTP::Request('GET',$cmd);  ## pretend it is a HTTP GET request - but we won't actually invoke it
            $cmdresp = (`$cmd 2>\&1`); ## run the cmd through the backtick method - 2>\&1 redirects error output to standard output
            $combined_response =~ s{$}{<$_>$cmd</$_>\n$cmdresp\n\n\n}; ## include it in the response
        }
    }
    $combined_response =~ s{^}{HTTP/1.1 100 OK\n}; ## pretend this is an HTTP response - 100 means continue
    $response = HTTP::Response->parse($combined_response); ## pretend the response is a http response - inject it into the object
    $endtimer = time;
    $latency = (int(1000 * ($endtimer - $starttimer)) / 1000);  ## elapsed time rounded to thousandths

    return;
}

#------------------------------------------------------------------
sub _shell_adjust {
    my ($_parm) = @_;

    # {SLASH} will be a back slash if running on Windows, otherwise a forward slash
    if ($is_windows) {
        ${$_parm} =~ s{^./}{.\\};
        ${$_parm} =~ s/{SLASH}/\\/g;
        ${$_parm} =~ s/{SHELL_ESCAPE}/\^/g;
    } else {
        ${$_parm} =~ s{^.\\}{./};
        ${$_parm} =~ s{\\}{\\\\}g; ## need to double back slashes in Linux, otherwise they vanish (unlike Windows shell)
        ${$_parm} =~ s/{SLASH}/\//g;
        ${$_parm} =~ s/{SHELL_ESCAPE}/\\/g;
    }

    return;
}

#------------------------------------------------------------------
sub commandonerror {  ## command only gets run on error - it does not count as part of the test
                      ## intended for scenarios when you want to give something a kick - e.g. recycle app pool

    my $combined_response = $response->as_string; ## take the existing test response

    for (qw/commandonerror/) {
        if ($case{$_}) {## perform command

            my $cmd = $case{$_};
            $cmd =~ s/\%20/ /g; ## turn %20 to spaces for display in log purposes
            _shell_adjust(\$cmd);
            $cmdresp = (`$cmd 2>\&1`); ## run the cmd through the backtick method - 2>\&1 redirects error output to standard output
            $combined_response =~ s{$}{<$_>$cmd</$_>\n$cmdresp\n\n\n}; ## include it in the response
        }
    }
    $response = HTTP::Response->parse($combined_response); ## put the test response along with the command on error response back in the response

    return;
}


#------------------------------------------------------------------
sub searchimage {  ## search for images in the actual result

    my $_unmarked = 'true';

    for (qw/searchimage searchimage1 searchimage2 searchimage3 searchimage4 searchimage5/) {
        if ($case{$_}) {
            if (-e "$case{$_}") { ## imageinimage.py bigimage smallimage markimage
                if ($_unmarked eq 'true') {
                   copy "$opt_publish_full$testnum_display$jumpbacksprint$retriesprint.png", "$opt_publish_full$testnum_display$jumpbacksprint$retriesprint-marked.png";
                   $_unmarked = 'false';
                }

                my $_image_in_image_result = (`plugins\\search-image.py $opt_publish_full$testnum_display$jumpbacksprint$retriesprint.png "$case{$_}" $opt_publish_full$testnum_display$jumpbacksprint$retriesprint-marked.png`);

                $_image_in_image_result =~ m/primary confidence (\d+)/s;
                my $_primary_confidence;
                if ($1) {$_primary_confidence = $1;}

                $_image_in_image_result =~ m/alternate confidence (\d+)/s;
                my $_alternate_confidence;
                if ($1) {$_alternate_confidence = $1;}

                $_image_in_image_result =~ m/min_loc (.*?)X/s;
                my $location;
                if ($1) {$location = $1;}

                $results_xml .= qq|            <$_>\n|;
                $results_xml .= qq|                <assert>$case{$_}</assert>\n|;

                if ($_image_in_image_result =~ m/was found/s) { ## was the image found?
                    $results_html .= qq|<span class="found">Found image: $case{$_}</span><br />\n|;
                    $results_xml .= qq|                <success>true</success>\n|;
                    print {*STDOUT} "Found: $case{$_}\n   $_primary_confidence primary confidence\n   $_alternate_confidence alternate confidence\n   $location location\n";
                    $passedcount++;
                    $retrypassedcount++;
                }
                else { #the image was not found within the bigger image
                    $results_html .= qq|<span class="notfound">Image not found: $case{$_}</span><br />\n|;
                    $results_xml .= qq|                <success>false</success>\n|;
                    print {*STDOUT} "Not found: $case{$_}\n   $_primary_confidence primary confidence\n   $_alternate_confidence alternate confidence\n   $location location\n";
                    $failedcount++;
                    $retryfailedcount++;
                    $isfailure++;
                }
                $results_xml .= qq|            </$_>\n|;
            } else {#We were not able to find the image to search for
                $results_html .= qq|<span class="notfound">SearchImage error - was the file path correct? $case{$_}</span><br />\n|;
                $results_xml .= qq|                <success>false</success>\n|;
                print {*STDOUT} "SearchImage error - was the file path correct? $case{$_}\n";
                $failedcount++;
                $retryfailedcount++;
                $isfailure++;
            }
        } ## end first if
    } ## end for

    if ($_unmarked eq 'false') {
       #keep an unmarked image, make the marked the actual result
       move "$opt_publish_full$testnum_display$jumpbacksprint$retriesprint.png", "$opt_publish_full$testnum_display$jumpbacksprint$retriesprint-unmarked.png";
       move "$opt_publish_full$testnum_display$jumpbacksprint$retriesprint-marked.png", "$opt_publish_full$testnum_display$jumpbacksprint$retriesprint.png";
    }

    return;
} ## end sub

#------------------------------------------------------------------
sub decode_quoted_printable {

    require MIME::QuotedPrint;

	if ($case{decodequotedprintable}) {
		 my $decoded = MIME::QuotedPrint::decode_qp($response->as_string); ## decode the response output
		 $response = HTTP::Response->parse($decoded); ## inject it back into the response
	}

    return;
}

#------------------------------------------------------------------
sub verify {  #do verification of http response and print status to HTML/XML/STDOUT/UI

    ## reset the global variables
    $assertionskips = 0;
    $assertionskipsmessage = q{}; ## support tagging an assertion as disabled with a message

    ## auto assertions
    if (!$case{ignoreautoassertions}) {
        ## autoassertion, autoassertion1, ..., autoassertion4, ..., autoassertion10000 (or more)
        _verify_autoassertion();
    }

    ## smart assertions
    if (!$case{ignoresmartassertions}) {
        _verify_smartassertion();
    }

    ## verify positive
    ## verifypositive, verifypositive1, ..., verifypositive25, ..., verifypositive10000 (or more)
    _verify_verifypositive();

    ## verify negative
    ## verifynegative, verifynegative1, ..., verifynegative25, ..., verifynegative10000 (or more)
    _verify_verifynegative();

    ## assert count
    _verify_assertcount();

     if ($case{verifyresponsetime}) { ## verify that the response time is less than or equal to given amount in seconds
         if ($latency <= $case{verifyresponsetime}) {
                $results_html .= qq|<span class="pass">Passed Response Time Verification</span><br />\n|;
                $results_xml .= qq|            <verifyresponsetime-success>true</verifyresponsetime-success>\n|;
                print {*STDOUT} "Passed Response Time Verification \n";
                $passedcount++;
                $retrypassedcount++;
         }
         else {
                $results_html .= qq|<span class="fail">Failed Response Time Verification - should be at most $case{verifyresponsetime}, got $latency</span><br />\n|;
                $results_xml .= qq|            <verifyresponsetime-success>false</verifyresponsetime-success>\n|;
                $results_xml .= qq|            <verifyresponsetime-message>Latency should be at most $case{verifyresponsetime} seconds</verifyresponsetime-message>\n|;
                print {*STDOUT} "Failed Response Time Verification - should be at most $case{verifyresponsetime}, got $latency \n";
                $failedcount++;
                $retryfailedcount++;
                $isfailure++;
        }
     }

    $forcedretry='false';
    if ($case{retryresponsecode}) {## retryresponsecode - retry on a certain response code, normally we would immediately fail the case
        if ($case{retryresponsecode} == $response->code()) { ## verify returned HTTP response code matches retryresponsecode set in test case
            $results_html .= qq|<span class="pass">Will retry on response code </span><br />\n|;
            $results_xml .= qq|            <retryresponsecode-success>true</retryresponsecode-success>\n|;
            $results_xml .= qq|            <retryresponsecode-message>Found Retry HTTP Response Code</retryresponsecode-message>\n|;
            print {*STDOUT} qq|Found Retry HTTP Response Code \n|;
            $forcedretry='true'; ## force a retry even though we received a potential error code
        }
    }

    if ($case{verifyresponsecode}) {
        if ($case{verifyresponsecode} == $response->code()) { #verify returned HTTP response code matches verifyresponsecode set in test case
            $results_html .= qq|<span class="pass">Passed HTTP Response Code Verification </span><br />\n|;
            $results_xml .= qq|            <verifyresponsecode-success>true</verifyresponsecode-success>\n|;
            $results_xml .= qq|            <verifyresponsecode-message>Passed HTTP Response Code Verification</verifyresponsecode-message>\n|;
            print {*STDOUT} qq|Passed HTTP Response Code Verification \n|;
            $passedcount++;
            $retrypassedcount++;
            $retry=0; ## we won't retry if the response code is invalid since it will probably never work
            }
        else {
            $results_html .= '<span class="fail">Failed HTTP Response Code Verification (received ' . $response->code() .  qq|, expecting $case{verifyresponsecode})</span><br />\n|;
            $results_xml .= qq|            <verifyresponsecode-success>false</verifyresponsecode-success>\n|;
            $results_xml .=   '            <verifyresponsecode-message>Failed HTTP Response Code Verification (received ' . $response->code() .  qq|, expecting $case{verifyresponsecode})</verifyresponsecode-message>\n|;
            print {*STDOUT} 'Failed HTTP Response Code Verification (received ' . $response->code() .  qq|, expecting $case{verifyresponsecode}) \n|;
            $failedcount++;
            $retryfailedcount++;
            $isfailure++;
        }
    }
    else { #verify http response code is in the 100-399 range
        if (($response->as_string() =~ /HTTP\/1.(0|1) (1|2|3)/i) || $case{ignorehttpresponsecode}) {  #verify existance of string in response - unless we are ignore error codes
            $results_html .= qq|<span class="pass">Passed HTTP Response Code Verification</span><br />\n|;
            $results_xml .= qq|            <verifyresponsecode-success>true</verifyresponsecode-success>\n|;
            $results_xml .= qq|            <verifyresponsecode-message>Passed HTTP Response Code Verification</verifyresponsecode-message>\n|;
            print {*STDOUT} qq|Passed HTTP Response Code Verification \n|;
            #succesful response codes: 100-399
            $passedcount++;
            $retrypassedcount++;
        }
        else {
            $response->as_string() =~ /(HTTP\/1.)(.*)/i;
            if ($1) {  #this is true if an HTTP response returned
                $results_html .= qq|<span class="fail">Failed HTTP Response Code Verification ($1$2)</span><br />\n|; #($1$2) is HTTP response code
                $results_xml .= qq|            <verifyresponsecode-success>false</verifyresponsecode-success>\n|;
                $results_xml .= qq|            <verifyresponsecode-message>($1$2)</verifyresponsecode-message>\n|;
                print {*STDOUT} "Failed HTTP Response Code Verification ($1$2) \n"; #($1$2) is HTTP response code
            }
            else {  #no HTTP response returned.. could be error in connection, bad hostname/address, or can not connect to web server
                $results_html .= qq|<span class="fail">Failed - No Response</span><br />\n|; #($1$2) is HTTP response code
                $results_xml .= qq|            <verifyresponsecode-success>false</verifyresponsecode-success>\n|;
                $results_xml .= qq|            <verifyresponsecode-message>Failed - No Response</verifyresponsecode-message>\n|;
                print {*STDOUT} "Failed - No Response \n"; #($1$2) is HTTP response code
            }
            if ($forcedretry eq 'false') {
                $failedcount++;
                $retryfailedcount++;
                $isfailure++;
                if ($retry > 0) { print {*STDOUT} "==> Won't retry - received HTTP error code\n"; }
                $retry=0; # we won't try again if we can't connect
            }
        }
    }

    if ($assertionskips > 0) {
        $totalassertionskips = $totalassertionskips + $assertionskips;
        $results_xml .= qq|            <assertionskips>true</assertionskips>\n|;
        $results_xml .= qq|            <assertionskips-message>$assertionskipsmessage</assertionskips-message>\n|;
    }

    if (($case{commandonerror}) && ($isfailure > 0)) { ## if the test case failed, check if we want to run a command to help sort out any problems
        commandonerror();
    }

    return;
}

sub _verify_autoassertion {

    foreach my $config_attribute ( sort keys %{ $userconfig->{autoassertions} } ) {
        if ( (substr $config_attribute, 0, 13) eq 'autoassertion' ) {
            my $verifynum = $config_attribute; ## determine index verifypositive index
            $verifynum =~ s/^autoassertion//g; ## remove autoassertion from string
            if (!$verifynum) {$verifynum = '0';} #In case of autoassertion, need to treat as 0
            @verifyparms = split /[|][|][|]/, $userconfig->{autoassertions}{$config_attribute} ; #index 0 contains the actual string to verify, 1 the message to show if the assertion fails, 2 the tag that it is a known issue
            if ($verifyparms[2]) { ## assertion is being ignored due to known production bug or whatever
                $results_html .= qq|<span class="skip">Skipped Auto Assertion $verifynum - $verifyparms[2]</span><br />\n|;
                print {*STDOUT} "Skipped Auto Assertion $verifynum - $verifyparms[2] \n";
                $assertionskips++;
                $assertionskipsmessage = $assertionskipsmessage . '[' . $verifyparms[2] . ']';
            }
            else {
                my $_results_xml = qq|            <$config_attribute>\n|;
                $_results_xml .= qq|                <assert>$verifyparms[0]</assert>\n|;
                #print {*STDOUT} "$verifyparms[0]\n"; ##DEBUG
                if ($response->as_string() =~ m/$verifyparms[0]/si) {  ## verify existence of string in response
                    #$results_html .= qq|<span class="pass">Passed Auto Assertion</span><br />\n|; ## Do not print out all the auto assertion passes
                    $_results_xml .= qq|                <success>true</success>\n|;
                    #print {*STDOUT} "Passed Auto Assertion \n"; ## Do not print out all the auto assertion passes
                    #print {*STDOUT} $verifynum." Passed Auto Assertion \n"; ##DEBUG
                    $passedcount++;
                    $retrypassedcount++;
                }
                else {
                    $results_html .= qq|<span class="fail">Failed Auto Assertion:</span>$verifyparms[0]<br />\n|;
                    $_results_xml .= qq|                <success>false</success>\n|;
                    if ($verifyparms[1]) { ## is there a custom assertion failure message?
                       $results_html .= qq|<span class="fail">$verifyparms[1]</span><br />\n|;
                       $_results_xml .= qq|                <message>$verifyparms[1]</message>\n|;
                    }
                    print {*STDOUT} "Failed Auto Assertion \n";
                    if ($verifyparms[1]) {
                       print {*STDOUT} "$verifyparms[1] \n";
                    }
                    $failedcount++;
                    $retryfailedcount++;
                    $isfailure++;
                }
                $_results_xml .= qq|            </$config_attribute>\n|;

                # only log the auto assertion if it failed
                if ($_results_xml =~ m/success.false/) {
                    $results_xml .= $_results_xml;
                }
            }
        }
    }

    return;
}

sub _verify_smartassertion {

    foreach my $config_attribute ( sort keys %{ $userconfig->{smartassertions} } ) {
        if ( (substr $config_attribute, 0, 14) eq 'smartassertion' ) {
            my $verifynum = $config_attribute; ## determine index verifypositive index
            $verifynum =~ s/^smartassertion//g; ## remove smartassertion from string
            if (!$verifynum) {$verifynum = '0';} #In case of smartassertion, need to treat as 0
            @verifyparms = split /[|][|][|]/, $userconfig->{smartassertions}{$config_attribute} ; #index 0 contains the pre-condition assertion, 1 the actual assertion, 3 the tag that it is a known issue
            if ($verifyparms[3]) { ## assertion is being ignored due to known production bug or whatever
                $results_html .= qq|<span class="skip">Skipped Smart Assertion $verifynum - $verifyparms[3]</span><br />\n|;
                print {*STDOUT} "Skipped Smart Assertion $verifynum - $verifyparms[2] \n";
                $assertionskips++;
                $assertionskipsmessage = $assertionskipsmessage . '[' . $verifyparms[2] . ']';
                return;
            }

            ## note the return statement in the previous condition, this code is executed if the assertion is not being skipped
            #print {*STDOUT} "$verifyparms[0]\n"; ##DEBUG
            if ($response->as_string() =~ m/$verifyparms[0]/si) {  ## pre-condition for smart assertion - first regex must pass
                $results_xml .= "            <$config_attribute>\n";
                $results_xml .= '                <assert>'._sub_xml_special($verifyparms[0])."</assert>\n";
                if ($response->as_string() =~ m/$verifyparms[1]/si) {  ## verify existence of string in response
                    #$results_html .= qq|<span class="pass">Passed Smart Assertion</span><br />\n|; ## Do not print out all the auto assertion passes
                    $results_xml .= qq|                <success>true</success>\n|;
                    #print {*STDOUT} "Passed Smart Assertion \n"; ## Do not print out the Smart Assertion passes
                    $passedcount++;
                    $retrypassedcount++;
                }
                else {
                    $results_html .= qq|<span class="fail">Failed Smart Assertion:</span>$verifyparms[0]<br />\n|;
                    $results_xml .= qq|                <success>false</success>\n|;
                    if ($verifyparms[2]) { ## is there a custom assertion failure message?
                       $results_html .= qq|<span class="fail">$verifyparms[2]</span><br />\n|;
                       $results_xml .= '                <message>'._sub_xml_special($verifyparms[2])."</message>\n";
                    }
                    print {*STDOUT} 'Failed Smart Assertion';
                    if ($verifyparms[2]) {
                       print {*STDOUT} ": $verifyparms[2]";
                    }
                    print {*STDOUT} "\n";
                    $failedcount++;
                    $retryfailedcount++;
                    $isfailure++;
                }
                $results_xml .= qq|            </$config_attribute>\n|;
            } ## end if - is pre-condition for smart assertion met?
        }
    }

    return;
}

sub _verify_verifypositive {

    foreach my $case_attribute ( sort keys %{ $xmltestcases->{case}->{$testnum} } ) {
        if ( (substr $case_attribute, 0, 14) eq 'verifypositive' ) {
            my $verifynum = $case_attribute; ## determine index verifypositive index
            $verifynum =~ s/^verifypositive//g; ## remove verifypositive from string
            if (!$verifynum) {$verifynum = '0';} #In case of verifypositive, need to treat as 0
            @verifyparms = split /[|][|][|]/, $case{$case_attribute} ; #index 0 contains the actual string to verify, 1 the message to show if the assertion fails, 2 the tag that it is a known issue
            if ($verifyparms[2]) { ## assertion is being ignored due to known production bug or whatever
                $results_html .= qq|<span class="skip">Skipped Positive Verification $verifynum - $verifyparms[2]</span><br />\n|;
                print {*STDOUT} "Skipped Positive Verification $verifynum - $verifyparms[2] \n";
                $assertionskips++;
                $assertionskipsmessage = $assertionskipsmessage . '[' . $verifyparms[2] . ']';
            }
            else {
                $results_xml .= "            <$case_attribute>\n";
                $results_xml .= '                <assert>'._sub_xml_special($verifyparms[0])."</assert>\n";
                if ($response->as_string() =~ m/$verifyparms[0]/si) {  ## verify existence of string in response
                    $results_html .= qq|<span class="pass">Passed Positive Verification</span><br />\n|;
                    $results_xml .= qq|                <success>true</success>\n|;
                    print {*STDOUT} "Passed Positive Verification \n";
                    #print {*STDOUT} $verifynum." Passed Positive Verification \n"; ##DEBUG
                    $passedcount++;
                    $retrypassedcount++;
                }
                else {
                    $results_html .= qq|<span class="fail">Failed Positive Verification:</span>$verifyparms[0]<br />\n|;
                    $results_xml .= qq|                <success>false</success>\n|;
                    if ($verifyparms[1]) { ## is there a custom assertion failure message?
                       $results_html .= qq|<span class="fail">$verifyparms[1]</span><br />\n|;
                       $results_xml .= '                <message>'._sub_xml_special($verifyparms[1])."</message>\n";
                    }
                    print {*STDOUT} "Failed Positive Verification \n";
                    if ($verifyparms[1]) {
                       print {*STDOUT} "$verifyparms[1] \n";
                    }
                    $failedcount++;
                    $retryfailedcount++;
                    $isfailure++;
                }
                $results_xml .= qq|            </$case_attribute>\n|;
            }
        }
    }

    return;
}

sub _verify_verifynegative {

    foreach my $case_attribute ( sort keys %{ $xmltestcases->{case}->{$testnum} } ) {
        if ( (substr $case_attribute, 0, 14) eq 'verifynegative' ) {
            my $verifynum = $case_attribute; ## determine index verifypositive index
            #print {*STDOUT} "$case_attribute\n"; ##DEBUG
            $verifynum =~ s/^verifynegative//g; ## remove verifynegative from string
            if (!$verifynum) {$verifynum = '0';} ## in case of verifypositive, need to treat as 0
            @verifyparms = split /[|][|][|]/, $case{$case_attribute} ; #index 0 contains the actual string to verify
            if ($verifyparms[2]) { ## assertion is being ignored due to known production bug or whatever
                $results_html .= qq|<span class="skip">Skipped Negative Verification $verifynum - $verifyparms[2]</span><br />\n|;
                print {*STDOUT} "Skipped Negative Verification $verifynum - $verifyparms[2] \n";
                $assertionskips++;
                $assertionskipsmessage = $assertionskipsmessage . '[' . $verifyparms[2] . ']';
            }
            else {
                $results_xml .= "            <$case_attribute>\n";
                $results_xml .= '                <assert>'._sub_xml_special($verifyparms[0])."</assert>\n";
                if ($response->as_string() =~ m/$verifyparms[0]/si) {  #verify existence of string in response
                    $results_html .= qq|<span class="fail">Failed Negative Verification</span><br />\n|;
                    $results_xml .= qq|                <success>false</success>\n|;
                    if ($verifyparms[1]) {
                       $results_html .= qq|<span class="fail">$verifyparms[1]</span><br />\n|;
                         $results_xml .= '            <message>'._sub_xml_special($verifyparms[1])."</message>\n";
                    }
                    print {*STDOUT} "Failed Negative Verification \n";
                    if ($verifyparms[1]) {
                       print {*STDOUT} "$verifyparms[1] \n";
                    }
                    $failedcount++;
                    $retryfailedcount++;
                    $isfailure++;
                    if ($retry > 0) { print {*STDOUT} "==> Won't retry - a verifynegative failed \n"; }
                    $retry=0; ## we won't retry if any of the verifynegatives fail
                    $verifynegativefailed = 'true';
                }
                else {
                    $results_html .= qq|<span class="pass">Passed Negative Verification</span><br />\n|;
                    $results_xml .= qq|            <success>true</success>\n|;
                    print {*STDOUT} "Passed Negative Verification \n";
                    $passedcount++;
                    $retrypassedcount++;
                }
                $results_xml .= qq|            </$case_attribute>\n|;
            }
        }
    }

    return;
}

sub _verify_assertcount {

    foreach my $case_attribute ( sort keys %{ $xmltestcases->{case}->{$testnum} } ) {
        if ( (substr $case_attribute, 0, 11) eq 'assertcount' ) {
            my $verifynum = $case_attribute; ## determine index verifypositive index
            #print {*STDOUT} "$case_attribute\n"; ##DEBUG
            $verifynum =~ s/^assertcount//g; ## remove assertcount from string
            if (!$verifynum) {$verifynum = '0';} ## in case of verifypositive, need to treat as 0
            @verifycountparms = split /[|][|][|]/, $case{$case_attribute} ;
            my $count = 0;
            my $tempstring=$response->as_string(); #need to put in a temporary variable otherwise it gets stuck in infinite loop

            while ($tempstring =~ m/$verifycountparms[0]/ig) { $count++;} ## count how many times string is found

            if ($verifycountparms[3]) { ## assertion is being ignored due to known production bug or whatever
                $results_html .= qq|<span class="skip">Skipped Assertion Count $verifynum - $verifycountparms[3]</span><br />\n|;
                print {*STDOUT} "Skipped Assertion Count $verifynum - $verifycountparms[2] \n";
                $assertionskips++;
                $assertionskipsmessage = $assertionskipsmessage . '[' . $verifyparms[2] . ']';
            }
            else {
                if ($count == $verifycountparms[1]) {
                    $results_html .= qq|<span class="pass">Passed Count Assertion of $verifycountparms[1]</span><br />\n|;
                    $results_xml .= qq|            <$case_attribute-success>true</$case_attribute-success>\n|;
                    print {*STDOUT} "Passed Count Assertion of $verifycountparms[1] \n";
                    $passedcount++;
                    $retrypassedcount++;
                }
                else {
                    $results_xml .= qq|            <$case_attribute-success>false</$case_attribute-success>\n|;
                    if ($verifycountparms[2]) {## if there is a custom message, write it out
                        $results_html .= qq|<span class="fail">Failed Count Assertion of $verifycountparms[1], got $count</span><br />\n|;
                        $results_html .= qq|<span class="fail">$verifycountparms[2]</span><br />\n|;
                        $results_xml .= qq|            <$case_attribute-message>|._sub_xml_special($verifycountparms[2]).qq| [got $count]</$case_attribute-message>\n|;
                    }
                    else {# we make up a standard message
                        $results_html .= qq|<span class="fail">Failed Count Assertion of $verifycountparms[1], got $count</span><br />\n|;
                        $results_xml .= qq|            <$case_attribute-message>Failed Count Assertion of $verifycountparms[1], got $count</$case_attribute-message>\n|;
                    }
                    print {*STDOUT} "Failed Count Assertion of $verifycountparms[1], got $count \n";
                    if ($verifycountparms[2]) {
                        print {*STDOUT} "$verifycountparms[2] \n";
                    }
                    $failedcount++;
                    $retryfailedcount++;
                    $isfailure++;
                } ## end else verifycountparms[2]
            } ## end else verifycountparms[3]
        } ## end if assertcount
    } ## end foreach

    return;
}
#------------------------------------------------------------------
sub parseresponse {  #parse values from responses for use in future request (for session id's, dynamic URL rewriting, etc)

    my ($_response_to_parse, @parseargs);
    my ($leftboundary, $rightboundary, $escape);

    foreach my $case_attribute ( sort keys %{ $xmltestcases->{case}->{$testnum} } ) {

        if ( (substr $case_attribute, 0, 13) eq 'parseresponse' ) {

            @parseargs = split /[|]/, $case{$case_attribute} ;

            $leftboundary = $parseargs[0]; $rightboundary = $parseargs[1]; $escape = $parseargs[2];

            $parsedresult{$case_attribute} = undef; ## clear out any old value first

            $_response_to_parse = $response->as_string;

            if ($rightboundary eq 'regex') {## custom regex feature
                if ($_response_to_parse =~ m/$leftboundary/s) {
                    $parsedresult{$case_attribute} = $1;
                }
            } else {
                if ($_response_to_parse =~ m/$leftboundary(.*?)$rightboundary/s) {
                    $parsedresult{$case_attribute} = $1;
                }
            }

            if ($escape) {
                ## convert special characters into %20 and so on
                if ($escape eq 'escape') {
                    $parsedresult{$case_attribute} = uri_escape($parsedresult{$case_attribute});
                }

                ## decode html entities - e.g. convert &amp; to & and &lt; to <
                if ($escape eq 'decode') {
                    _decode_html_entities($case_attribute);
                }

                ## quote meta characters so they will be treated as literal in regex
                if ($escape eq 'quotemeta') {
                    $parsedresult{$case_attribute} = quotemeta $parsedresult{$case_attribute};
                }
            }

            #print "\n\nParsed String: $parsedresult{$_}\n\n";
        }
    }

    return;
}

#------------------------------------------------------------------
sub _decode_html_entities {
    my ($_case_attribute) = @_;

    require HTML::Entities;

    $parsedresult{$_case_attribute} = HTML::Entities::decode_entities($parsedresult{$_case_attribute});

    return;
}

#------------------------------------------------------------------
sub slash_me {
    my ($_string) = @_;

    if ($is_windows) {
        $_string =~ s{/}{\\}g;
    } else {
        $_string =~ s{\\}{/}g;
    }

    return $_string;
}

#------------------------------------------------------------------
sub processcasefile {  #get test case files to run (from command line or config file) and evaluate constants
                       #parse config file and grab values it sets

    my $setuseragent;
    my $configfilepath;

    #process the config file
    if ($opt_configfile) {  #if -c option was set on command line, use specified config file
        $configfilepath = slash_me($opt_configfile);
    } else {
        $configfilepath = 'config.xml';
        $opt_configfile = 'config.xml'; ## we have defaulted to config.xml in the current folder
    }

    if (-e "$configfilepath") {  #if we have a config file, use it
        $userconfig = XMLin("$configfilepath"); ## Parse as XML for the user defined config
    } else {
        die "\nNo config file specified and no config.xml found in current working directory\n\n";
    }

    if (($#ARGV + 1) > 2) {  #too many command line args were passed
        die "\nERROR: Too many arguments\n\n";
    }

    if (($#ARGV + 1) < 1) {  #no command line args were passed
        #if testcase filename is not passed on the command line, use files in config.xml

        if ($userconfig->{testcasefile}) {
            $currentcasefile = slash_me($userconfig->{testcasefile});
        } else {
            die "\nERROR: I can't find any test case files to run.\nYou must either use a config file or pass a filename."; ## no critic(RequireCarping)
        }

    }

    elsif (($#ARGV + 1) == 1) {  #one command line arg was passed
        #use testcase filename passed on command line (config.xml is only used for other options)
        $currentcasefile = slash_me($ARGV[0]);  #first commandline argument is the test case file
    }

    #grab values for constants in config file:
    for my $config_const (qw/baseurl baseurl1 baseurl2 proxy timeout globalretry globaljumpbacks autocontrolleronly/) {
        if ($userconfig->{$config_const}) {
            $config{$config_const} = $userconfig->{$config_const};
            #print "\n$_ : $config{$_} \n\n";
        }
    }

    if ($userconfig->{useragent}) {
        $setuseragent = $userconfig->{useragent};
        print "\nuseragent : $setuseragent \n\n";
        if ($setuseragent) { #http useragent that will show up in webserver logs
            $useragent->agent($setuseragent);
        }
    }

    if ($userconfig->{httpauth}) {
        if ( ref($userconfig->{httpauth}) eq 'ARRAY') {
            #print "We have an array of httpauths\n";
            for my $auth ( @{ $userconfig->{httpauth} } ) { ## $userconfig->{httpauth} is an array
                _push_httpauth ($auth);
            }
        } else {
            #print "Not an array - we just have one httpauth\n";
            _push_httpauth ($userconfig->{httpauth});
        }
    }

    if (not defined $config{globaljumpbacks}) { ## default the globaljumpbacks if it isn't in the config file
        $config{globaljumpbacks} = 20;
    }

    if ($opt_ignoreretry) { ##
        $config{globalretry} = -1;
        $config{globaljumpbacks} = 0;
    }

    # find the name of the output folder only i.e. not full path - OS safe
    my $_abs_output_full = File::Spec->rel2abs( $output );
    $concurrency =  basename ( dirname($_abs_output_full) );

    $outsum = unpack '%32C*', $output; ## checksum of output directory name - for concurrency
    #print "outsum $outsum \n";

    if (defined $userconfig->{ports_variable}) {
        if ($userconfig->{ports_variable} eq 'convert_back') {
            $convert_back_ports = 'true';
        }

        if ($userconfig->{ports_variable} eq 'null') {
            $convert_back_ports_null = 'true';
        }
    }

    return;
}

sub _push_httpauth {
    my ($auth) = @_;

    #print "\nhttpauth:$auth\n";
    my @authentry = split /:/, $auth;
    if ($#authentry != 4) {
        print {*STDERR} "\nError: httpauth should have 5 fields delimited by colons\n\n";
    }
    else {
        push @httpauth, [@authentry];
    }

    return;
}

#------------------------------------------------------------------
sub _sub_xml_special {
    my ($_clean) = @_;

    $_clean =~ s/&/{AMPERSAND}/g;
    $_clean =~ s/</{LESSTHAN}/g;
    $_clean =~ s/>/{GREATERTHAN}/g;

    return $_clean;
}

#------------------------------------------------------------------
sub read_test_case_file {

    my $_xml = read_file($currentcasefile);

    # substitute in the included test step files
    $_xml =~ s{<include[^>]*?
               id[ ]*=[ ]*["'](\d*)["']                 # ' # id = "10"
               [^>]*?
               file[ ]*=[ ]*["']([^"']*)["']            # file = "tests\helpers\setup\create_job_ad.xml"
               [^>]*>
               }{_include_file($2,$1,$&)}gsex;          # the actual file content

    # for convenience, WebInject allows ampersand and less than to appear in xml data, so this needs to be masked
    $_xml =~ s/&/{AMPERSAND}/g;
    while ( $_xml =~ s/\w\s*=\s*"[^"]*\K<(?!case)([^"]*")/{LESSTHAN}$1/sg ) {}
    while ( $_xml =~ s/\w\s*=\s*'[^']*\K<(?!case)([^']*')/{LESSTHAN}$1/sg ) {}
    #$_xml =~ s/\\</{LESSTHAN}/g;

    $casecount = 0;
    while ($_xml =~ /<case/g) {  #count test cases based on '<case' tag
        $casecount++;
    }

    if ($casecount == 1) {
        $_xml =~ s/<\/testcases>/<case id="99999999" description1="dummy test case"\/><\/testcases>/;  #add dummy test case to end of file
    }

    # see the final test case file after all alerations for debug purposes
    #write_file('final_test_case_file_'.int(rand(999)).'.xml', $_xml);

    # here we parse the xml file in an eval, and capture any error returned (in $@)
    my $_message;
    $xmltestcases = eval { XMLin($_xml, VarAttr => 'varname') };

    if ($@) {
        $_message = $@;
        $_message =~ s{XML::Simple.*\n}{}g; # remove misleading line number reference
        my $_file_name_full = _write_failed_xml($_xml);
        die "\n".$_message."\nRefer to built test file: $_file_name_full\n";
    }

    return;
}

#------------------------------------------------------------------
sub _write_failed_xml {
    my ($_xml) = @_;

    require File::Path;

    ## output location might include a prefix that we do not want
    my $_output_folder = dirname($output.'dummy');

    my $_path = slash_me ($_output_folder.'/parse_error');

    File::Path::make_path ( $_path );

    my $_rand = int rand 999;
    my $_file_name = 'test_file_'.$_rand.'.xml';
    my $_file_name_full = slash_me ( $_path.q{/}.$_file_name);

    my $_abs_file_full = File::Spec->rel2abs( $_file_name_full );

    write_file($_abs_file_full, $_xml);

    return $_abs_file_full;
}

#------------------------------------------------------------------
sub _include_file {
    my ($_file, $_id, $_match) = @_;

    if ( $_match =~ /runon[\s]*=[\s]*"([^"]*)/ ) {
        if ( not _run_this_step($1) ) {
            print {*STDOUT} "not included: [id $_id] $_file (run on $1)\n";
            return q{};
        }
    }

    if ($_match =~ /autocontrolleronly/) {
        if (not $opt_autocontroller) {
            print {*STDOUT} "not included: [id $_id] $_file (autocontrolleronly)\n";
            return q{};
        }
    }

    print {*STDOUT} "include: [id $_id] $_file\n";

    my $_include = read_file(slash_me($_file));
    $_include =~ s{\n(\s*)id[\s]*=[\s]*"}{"\n".$1.'id="'.$_id.'.'}eg; #'

    #open my $INCLUDE, '>', "$output".'include.xml' or die "\nERROR: Failed to open include debug file\n\n";
    #print {$INCLUDE} $_include;
    #close $INCLUDE or die "\nERROR: Failed to close include debug file\n\n";

    return $_include;
}

#------------------------------------------------------------------
## no critic (RequireArgUnpacking)
sub convertbackxml {  #converts replaced xml with substitutions


## length feature for returning the size of the response
    my $mylength;
    if (defined $response) {#It will not be defined for the first test
        $mylength = length($response->as_string);
    }

    $_[0] =~ s/{JUMPBACKS}/$jumpbacks/g; #Number of times we have jumped back due to failure

## hostname, testnum, concurrency, teststeptime
    $_[0] =~ s/{HOSTNAME}/$hostname/g; #of the computer currently running webinject
    $_[0] =~ s/{TESTNUM}/$testnum_display/g;
    $_[0] =~ s/{TESTFILENAME}/$testfilename/g;
    $_[0] =~ s/{LENGTH}/$mylength/g; #length of the previous test step response
    $_[0] =~ s/{AMPERSAND}/&/g;
    $_[0] =~ s/{LESSTHAN}/</g;
    $_[0] =~ s/{SINGLEQUOTE}/'/g; #'
    $_[0] =~ s/{TIMESTAMP}/$timestamp/g;
    $_[0] =~ s/{STARTTIME}/$starttime/g;
    $_[0] =~ s/{OPT_PROXYRULES}/$opt_proxyrules/g;
    $_[0] =~ s/{OPT_PROXY}/$opt_proxy/g;

    $_[0] =~ m/{TESTSTEPTIME:(\d+)}/s;
    if ($1)
    {
     $_[0] =~ s/{TESTSTEPTIME:(\d+)}/$teststeptime{$1}/g; #latency for test step number; example usage: {TESTSTEPTIME:5012}
    }

    $_[0] =~ s/{RANDOM:(\d+)(:*[[:alpha:]]*)}/_get_random_string($1, $2)/eg;

    if (defined $convert_back_ports) {
        $_[0] =~ s/{:(\d+)}/:$1/;
    } elsif (defined $convert_back_ports_null) {
        $_[0] =~ s/{:(\d+)}//;
    }

## day month year constant support #+{DAY}.{MONTH}.{YEAR}+{HH}:{MM}:{SS}+ - when execution started
    $_[0] =~ s/{DAY}/$DAYOFMONTH/g;
    $_[0] =~ s/{MONTH}/$MONTHS[$MONTH]/g;
    $_[0] =~ s/{YEAR}/$YEAR/g; #4 digit year
    $_[0] =~ s/{YY}/$YY/g; #2 digit year
    $_[0] =~ s/{HH}/$HOUR/g;
    $_[0] =~ s/{MM}/$MINUTE/g;
    $_[0] =~ s/{SS}/$SECOND/g;
    $_[0] =~ s/{WEEKOFMONTH}/$WEEKOFMONTH/g;
    $_[0] =~ s/{DATETIME}/$YEAR$MONTHS[$MONTH]$DAYOFMONTH$HOUR$MINUTE$SECOND/g;
    my $underscore = '_';
    $_[0] =~ s{{FORMATDATETIME}}{$DAYOFMONTH\/$MONTHS[$MONTH]\/$YEAR$underscore$HOUR:$MINUTE:$SECOND}g;
    $_[0] =~ s/{COUNTER}/$counter/g;
    $_[0] =~ s/{CONCURRENCY}/$concurrency/g; #name of the temporary folder being used - not full path
    $_[0] =~ s/{OUTPUT}/$output/g;
    $_[0] =~ s/{PUBLISH}/$opt_publish_full/g;
    $_[0] =~ s/{OUTSUM}/$outsum/g;
## CWD Current Working Directory
    $_[0] =~ s/{CWD}/$this_script_folder_full/g;

## parsedresults moved before config so you can have a parsedresult of {BASEURL2} say that in turn gets turned into the actual value

    ##substitute all the parsed results back
    ##parseresponse = {}, parseresponse5 = {5}, parseresponseMYVAR = {MYVAR}
    foreach my $case_attribute ( sort keys %{parsedresult} ) {
       my $parse_var = substr $case_attribute, 13;
       $_[0] =~ s/{$parse_var}/$parsedresult{$case_attribute}/g;
    }

    $_[0] =~ s/{BASEURL}/$config{baseurl}/g;
    $_[0] =~ s/{BASEURL1}/$config{baseurl1}/g;
    $_[0] =~ s/{BASEURL2}/$config{baseurl2}/g;

## perform arbirtary user defined config substituions
    my ($value, $KEY);
    foreach my $key (keys %{ $userconfig->{userdefined} } ) {
        $value = $userconfig->{userdefined}{$key};
        if (ref($value) eq 'HASH') { ## if we found a HASH, we treat it as blank
            $value = q{};
        }
        $KEY = uc $key; ## convert to uppercase
        $_[0] =~ s/{$KEY}/$value/g;
    }

    return;
}

#------------------------------------------------------------------
sub _get_random_string {
    my ($_length, $_type) = @_;

    if (not $_type) {
        $_type = ':ALPHANUMERIC';
    }

    require Math::Random::ISAAC;

    my $_rng = Math::Random::ISAAC->new(time*100_000); ## only integer portion is used in seed

    my $_random;
    my $_last;
    my $_next;
    foreach my $_i (1..$_length) {
        $_next = _get_char($_rng->irand(), $_type);

        ## this clause stops two consecutive characters being the same
        ## some search engines will filter out words containing more than 2 letters the same in a row
        if (defined $_last) {
            while ($_next eq $_last) {
                $_next = _get_char($_rng->irand(), $_type);
            }
        }

        $_last = $_next;
        $_random .= $_last;
    }

    return $_random;
}

#------------------------------------------------------------------
sub _get_char {
    my ($_raw_rnd, $_type) = @_;

    ## here we need to turn our unsigned 32 bit integer into a character of the desired type
    ## supported types :ALPHANUMERIC, :ALPHA, :NUMERIC

    my $_min_desired_rnd = 1;
    my $_max_desired_rnd;
    my $_max_possible_rnd = 4_294_967_296;
    my $_number;
    my $_char;

    if (uc $_type eq ':ALPHANUMERIC') {
        $_max_desired_rnd = 36;
        $_number = _get_number_in_range ($_min_desired_rnd, $_max_desired_rnd, $_max_possible_rnd, $_raw_rnd);
        # now we should have a number in the range 1 to 36
        if ($_number < 11) {
            $_char = chr $_number + 47;
        } else {
            $_char = chr $_number + 54;  ## i.e. 64 - 10
        }
    }

    if (uc $_type eq ':ALPHA') {
        $_max_desired_rnd = 26;
        $_number = _get_number_in_range ($_min_desired_rnd, $_max_desired_rnd, $_max_possible_rnd, $_raw_rnd);
        $_char = chr $_number + 64;
    }

    if (uc $_type eq ':NUMERIC') {
        $_max_desired_rnd = 10;
        $_number = _get_number_in_range ($_min_desired_rnd, $_max_desired_rnd, $_max_possible_rnd, $_raw_rnd);
        $_char = chr $_number + 47;
    }

    return $_char;
}

#------------------------------------------------------------------
sub _get_number_in_range {
    my ($_min_desired_rnd, $_max_desired_rnd, $_max_possible_rnd, $_raw_rnd) = @_;

    return ( ($_raw_rnd * $_max_desired_rnd) / $_max_possible_rnd ) + $_min_desired_rnd;
}


#------------------------------------------------------------------
sub convertbackxmldynamic {## some values need to be updated after each retry

    my $retriessub = $retries-1;

    my $elapsed_seconds_so_far = int(time() - $starttime) + 1; ## elapsed time rounded to seconds - increased to the next whole number
    my $elapsed_minutes_so_far = int($elapsed_seconds_so_far / 60) + 1; ## elapsed time rounded to seconds - increased to the next whole number

    $_[0] =~ s/{RETRY}/$retriessub/g;
    $_[0] =~ s/{ELAPSED_SECONDS}/$elapsed_seconds_so_far/g; ## always rounded up
    $_[0] =~ s/{ELAPSED_MINUTES}/$elapsed_minutes_so_far/g; ## always rounded up

    ## put the current date and time into variables
    my ($dynamic_second, $dynamic_minute, $dynamic_hour, $dynamic_day_of_month, $dynamic_month, $dynamic_year_offset, $dynamic_day_of_week, $dynamic_day_of_year, $dynamic_daylight_savings) = localtime;
    my $dynamic_year = 1900 + $dynamic_year_offset;
    $dynamic_month = $MONTHS[$dynamic_month];
    my $dynamic_day = sprintf '%02d', $dynamic_day_of_month;
    $dynamic_hour = sprintf '%02d', $dynamic_hour; #put in up to 2 leading zeros
    $dynamic_minute = sprintf '%02d', $dynamic_minute;
    $dynamic_second = sprintf '%02d', $dynamic_second;

    my $underscore = '_';
    $_[0] =~ s{{NOW}}{$dynamic_day\/$dynamic_month\/$dynamic_year$underscore$dynamic_hour:$dynamic_minute:$dynamic_second}g;

    return;
}

#------------------------------------------------------------------
sub convertback_var_variables { ## e.g. postbody="time={RUNSTART}"
    foreach my $case_attribute ( sort keys %{varvar} ) {
       my $sub_var = substr $case_attribute, 3;
       $_[0] =~ s/{$sub_var}/$varvar{$case_attribute}/g;
    }

    return;
}

## use critic
#------------------------------------------------------------------
sub set_var_variables { ## e.g. varRUNSTART="{HH}{MM}{SS}"
    foreach my $case_attribute ( sort keys %{ $xmltestcases->{case}->{$testnum} } ) {
       if ( (substr $case_attribute, 0, 3) eq 'var' ) {
            $varvar{$case_attribute} = $case{$case_attribute}; ## assign the variable
        }
    }

    return;
}

#------------------------------------------------------------------
sub substitute_var_variables {
 
    foreach my $_case_attribute ( keys %{ $xmltestcases->{case}->{$testnum} } ) { ## then substitute them in
        convertback_var_variables($case{$_case_attribute});
    }

    return;
}

#------------------------------------------------------------------
sub uri_escape {
    my ($_string) = @_;

    $_string =~ s/([^^A-Za-z0-9\-_.!~*'()])/ sprintf "%%%02x", ord $1 /eg; ##no critic(RegularExpressions::ProhibitEnumeratedClasses) #'

    return $_string;
}

#------------------------------------------------------------------
sub httplog {  # write requests and responses to http.txt file

    ## save the http response to a file - e.g. for file downloading, css
    if ($case{logresponseasfile}) {
        my $responsefoldername = dirname($output.'dummy'); ## output folder supplied by command line might include a filename prefix that needs to be discarded, dummy text needed due to behaviour of dirname function
        open my $RESPONSEASFILE, '>', "$responsefoldername/$case{logresponseasfile}" or die "\nCould not open file for response as file\n\n";  #open in clobber mode
        binmode $RESPONSEASFILE; ## set binary mode
        print {$RESPONSEASFILE} $response->content, q{}; #content just outputs the content, whereas as_string includes the response header
        close $RESPONSEASFILE or die "\nCould not close file for response as file\n\n";
    }

    my $_step_info = "Test Step: $testnum_display$jumpbacksprint$retriesprint - ";

    ## log descrption1 and description2
    $_step_info .=  $case{description1};
    if (defined $case{description2}) {
       $_step_info .= ' ['.$case{description2}.']';
    }
    $_step_info .= "\n";

    for (qw/searchimage searchimage1 searchimage2 searchimage3 searchimage4 searchimage5/) {
        if ($case{$_}) {
            $_step_info .= "<searchimage>$case{$_}</searchimage>\n";
        }
    }

    my $_request_headers = $request->as_string;

    my $_request_content_length = length $request->content;
    if ($_request_content_length) {
        $_request_headers .= 'Request Content Length: '.$_request_content_length." bytes\n";
    }

    #$textrequest =~ s/%20/ /g; #Replace %20 with a single space for clarity in the log file

    my $_core_info = "\n".$response->status_line( )."\n";

    my $_response_base;
    if ( eval { defined $response->base( ) } ) {
        $_response_base = $response->base( );
        $_core_info .= 'Base for relative URLs: '.$_response_base."\n";
        $_core_info .= 'Expires: '.scalar(localtime( $response->fresh_until( ) ))."\n";
    }

    #my $_age = $response->current_age( );
    #my $_days  = int($_age/86400);       $_age -= $_days * 86400;
    #my $_hours = int($_age/3600);        $_age -= $_hours * 3600;
    #my $_mins  = int($_age/60);          $_age -= $_mins    * 60;
    #my $_secs  = $_age;
    #$_core_info .= "The document is $_days days, $_hours hours, $_mins minutes, and $_secs seconds old.\n";

    my $_response_content_ref = $response->content_ref( );
    my $_response_headers = $response->headers_as_string;

    _write_http_log($_step_info, $_request_headers, $_core_info, $_response_headers, $_response_content_ref);
    _write_step_html($_step_info, $_request_headers, $_core_info, $_response_headers, $_response_content_ref, $_response_base);

    return;
}

#------------------------------------------------------------------
sub _write_http_log {
    my ($_step_info, $_request_headers, $_core_info, $_response_headers, $_response_content_ref) = @_;

    my $_log_separator = "\n";
    $_log_separator .= "      *****************************************************      \n";
    $_log_separator .= "    *********************************************************    \n";
    $_log_separator .= "  *************************************************************  \n";
    $_log_separator .= "************************* LOG SEPARATOR *************************\n";
    $_log_separator .= "  *************************************************************  \n";
    $_log_separator .= "    *********************************************************    \n";
    $_log_separator .= "      *****************************************************      \n\n";
    open my $_HTTPLOGFILE, '>>' ,$opt_publish_full.'http.txt' or die "\nERROR: Failed to open $opt_publish_full"."http.txt for append\n\n";
    print {$_HTTPLOGFILE} $_step_info, $_request_headers, $_core_info."\n", $_response_headers."\n", ${ $_response_content_ref }, $_log_separator;
    close $_HTTPLOGFILE or die "\nCould not close http.txt file\n\n";

    return;
}

#------------------------------------------------------------------
sub _write_step_html {
    my ($_step_info, $_request_headers, $_core_info, $_response_headers, $_response_content_ref, $_response_base) = @_;

    _format_xml($_response_content_ref);

    _format_json($_response_content_ref);

    my $_display_as_text = _should_display_as_text($_response_content_ref);

    my ($_wif_batch, $_wif_run_number);
    if (defined $userconfig->{wif}->{batch} ) {
        $_wif_batch = $userconfig->{wif}->{batch};
        $_wif_run_number = $userconfig->{wif}->{run_number};
    } else {
        $_wif_batch = 'needs_webinject_framework';
        $_wif_run_number = 'needs_webinject_framework';
    }

    my $_html = '<!DOCTYPE html>';
    _add_html_head(\$_html);

    $_html .= qq|        <wi_div class="wi_heading">\n|;
    $_html .= qq|            <wi_h1 class="wi_alignleft">Step $testnum_display$jumpbacksprint$retriesprint</wi_h1>\n|;
    $_html .= qq|            <wi_h3 class="wi_alignright">\n|;
    $_html .= qq|              $case{description1}\n|;
    $_html .= qq|            </wi_h3>\n|;
    $_html .= qq|            <wi_div style="clear: both;"></wi_div>\n|;
    $_html .= qq|            <br />\n|;
    $_html .= qq|            <wi_h2>\n|;
    $_html .= qq|                <a href="../../../All_Batches/Summary.xml"> Summary </a> -&gt; <a href="../../../All_Batches/$_wif_batch.xml"> Batch Summary </a> -&gt; <a href="results_$_wif_run_number.xml"> Run Results </a> -&gt; Step\n|;
    if (defined $previous_test_step) {
        $_html .= qq|                &nbsp; &nbsp; [<a href="$previous_test_step.html"> prev </a>]\n|;
    }
    $_html .= qq|            </wi_h2>\n|;
    $_html .= qq|        </wi_div>\n|;

    #$_html .= $_step_info;

    $_html .= qq|        <a class="wi_headers" href="javascript:wi_toggle('wi_toggle_request');">Request Headers</a>\n|;
    $_html .= qq|\n<xmp id="wi_toggle_request" style="display: none; font-size:1.5em; white-space: pre-wrap;">\n|.$_request_headers.qq|\n</xmp>\n|;
    $_html .= qq|        <a class="wi_headers" href="javascript:wi_toggle('wi_toggle_response');">Response Headers</a>\n|;
    $_html .= qq|\n<xmp id="wi_toggle_response" style="display: none; font-size:1.5em; white-space: pre-wrap;">\n|.$_core_info.qq|\n|.$_response_headers.qq|\n</xmp>\n<br /><br />\n|;
    $_html .= qq|    </wi_body>\n|;
    $_html .= qq|    <body style="display:block; margin:0; padding:0; border:0; font-size: 100%; font: inherit; vertical-align: baseline;">\n|;

    _add_selenium_screenshot(\$_html);

    _add_search_images(\$_html);

    _add_email_link(\$_html);

    if (defined $_response_base) {
        _replace_relative_urls_with_absolute($_response_content_ref, $_response_base);
    }

    _response_content_substitutions( $_response_content_ref );

    if (defined $_display_as_text) {
        $_html .= "\n<xmp>\n".${ $_response_content_ref } ."\n</xmp>\n";
    } else {
        $_html .= ${ $_response_content_ref } ;
    }

    $_html .= "\n    </body>\n</html>\n";

    my $_file_full = $opt_publish_full."$testnum_display$jumpbacksprint$retriesprint".'.html';
    _delayed_write_step_html($_file_full, $_html);

    return;
}

#------------------------------------------------------------------
sub _format_xml {
    my ($_response) = @_;

    if ($case{formatxml}) {
         ## makes an xml response easier to read by putting in a few carriage returns
         ${ $_response } =~ s{\>\<}{\>\x0D\n\<}g; ## insert a CR between every ><
    }

    return;
}

#------------------------------------------------------------------
sub _format_json {
    my ($_response) = @_;

    if ($case{formatjson}) {
         ## makes a JSON response easier to read by putting in a few carriage returns
         ${ $_response }  =~ s{",}{",\x0D\n}g;   ## insert a CR after  every ",
         ${ $_response }  =~ s/[}],/\},\x0D\n/g;  ## insert a CR after  every },
         ${ $_response }  =~ s/\["/\x0D\n\["/g;  ## insert a CR before every ["
         ${ $_response }  =~ s/\\n\\tat/\x0D\n\\tat/g;        ## make java exceptions inside JSON readable - when \n\tat is seen, eat the \n and put \ CR before the \tat
    }

    return;
}

#------------------------------------------------------------------
sub _should_display_as_text {
    my ($_response) = @_;

    if ($case{logastext}) { return 'true'; }
    if ($case{method} eq 'selenium') { return 'true'; }

    # if html and body tags found, then display as html
    if ( ${ $_response } =~ m/<html.*?<body/is ) { return; }

    # if we didn't find html and body tags, then don't attempt to render as html
    return 'true';
}

#------------------------------------------------------------------
sub _add_html_head {
    my ($_html) = @_;

    ${$_html} .= qq|\n<html>\n    <wi_body style="padding:25px 0 0 35px; background: #ecf0f1; display:block; margin:0; border:0; font-size: 100%; vertical-align: baseline; font:80% Verdana, sans-serif;">\n|;
    ${$_html} .= qq|        <head>\n|;
    ${$_html} .= qq|            <style>\n|;
    ${$_html} .= qq|                wi_h1, wi_h2, wi_h3, wi_div { display:block; margin:0; padding:0; border:0; font-size: 100%; font: inherit; vertical-align: baseline; }\n|;
    ${$_html} .= qq|                wi_h2 a:link, .wi_headers:link { color:SlateGray; }\n|;
    ${$_html} .= qq|                wi_h2 a, .wi_headers { text-decoration:none; font-weight:bolder; }\n|;
    ${$_html} .= qq|                wi_h2 a:hover, .wi_headers:hover { color:SlateGray; text-decoration: underline; }\n|;
    ${$_html} .= qq|                wi_h2 a:visited, .wi_headers:visited { color:SlateGray; }\n|;
    ${$_html} .= qq|                .wi_heading { padding:1em 1em 0 1em; border:1px solid #ddd; background:DarkSlateGray; margin:0 2em 2em 0; font-weight:normal;  color:#D1E6E7; line-height:1.6em;}\n|;
    ${$_html} .= qq|                .wi_heading wi_h1 {  font-size:2.5em; font-family: Verdana, sans-serif; margin-bottom:0.3em;  }\n|;
    ${$_html} .= qq|                .wi_heading wi_h2 {  font-size:1.5em; font-family: Verdana, sans-serif; margin-bottom:0.3em;  }\n|;
    ${$_html} .= qq|                .wi_heading wi_h3 {  font-size:1.5em; font-family: Verdana, sans-serif; margin-bottom:0.3em; line-height:1.5em;}\n|;
    ${$_html} .= qq|                .wi_alignleft {float: left;}\n|;
    ${$_html} .= qq|                .wi_alignright {float: right;}\n|;
    ${$_html} .= qq|            </style>\n|;
    ${$_html} .= qq|            <script language="javascript">\n|;
    ${$_html} .= qq|                function wi_toggle(wi_toggle_ele) {\n|;
    ${$_html} .= qq|                   var ele = document.getElementById(wi_toggle_ele);\n|;
    ${$_html} .= qq|                   if(ele.style.display == "block") {\n|;
    ${$_html} .= qq|                           ele.style.display = "none";\n|;
    ${$_html} .= qq|                   }\n|;
    ${$_html} .= qq|                   else {\n|;
    ${$_html} .= qq|                       ele.style.display = "block";\n|;
    ${$_html} .= qq|                   }\n|;
    ${$_html} .= qq|                } \n|;
    ${$_html} .= qq|            </script>\n|;
    ${$_html} .= qq|        </head>\n|;

    return;
}

#------------------------------------------------------------------
sub _add_selenium_screenshot {
    my ($_html) = @_;

    # if we have a Selenium WebDriver screenshot, link to it
    if (-e "$opt_publish_full$testnum_display$jumpbacksprint$retriesprint.png" ) {
        ${$_html} .= qq|<br /><img style="position: relative; left: 50%; transform: translateX(-50%);" alt="screenshot of test step $testnum_display$jumpbacksprint$retriesprint" src="$testnum_display$jumpbacksprint$retriesprint.png"><br />|;
    }

    return;
}

#------------------------------------------------------------------
sub _add_search_images {
    my ($_html) = @_;

    # if we have search images, copy them to the results and link to them
    for (qw/searchimage searchimage1 searchimage2 searchimage3 searchimage4 searchimage5/) {
        if ( $case{$_} && -e $case{$_} ) {
            copy "$case{$_}", "$opt_publish_full";
            my ($_image_name, $_image_path) = fileparse( $case{$_} );
            ${$_html} .= qq|<br />$_image_name<br /><img style="position: relative; left: 50%; transform: translateX(-50%);" alt="searchimage $case{$_}" src="$_image_name"><br />|;
        }
    }

    return;
}

#------------------------------------------------------------------
sub _add_email_link {
    my ($_html) = @_;

    # if we have grabbed an email file, link to it
    if (-e "$opt_publish_full$testnum_display$jumpbacksprint$retriesprint.eml" ) {
        ${$_html} .= qq|<br /><A style="font-family: Verdana; font-size:2.5em;" href="$testnum_display$jumpbacksprint$retriesprint.eml">&nbsp; Link to actual eMail file &nbsp;</A><br /><br />|;
    }

    return;
}

#------------------------------------------------------------------
sub _response_content_substitutions {
    my ($_response_content_ref) = @_;

    foreach my $_sub ( keys %{ $userconfig->{content_subs} } ) {
        #print "_sub:$_sub:$userconfig->{content_subs}{$_sub}\n";
        my @_regex = split /[|][|][|]/, $userconfig->{content_subs}{$_sub}; #index 0 contains the LHS, 1 the RHS
        ${ $_response_content_ref } =~ s{$_regex[0]}{$_regex[1]}gees;
    }

    if (@hrefs) {
        ${ $_response_content_ref } =~ s{href="([^"]+)}{_grabbed_href($1)}eg;
    }

    if (@srcs) {
        ${ $_response_content_ref } =~ s{src="([^"]+)}{_grabbed_src($1)}eg;
    }

    if (@bg_images) {
        ${ $_response_content_ref } =~ s{style="background-image: url[(]([^)]+)}{_grabbed_background_image($1)}eg; #"
    }

    return;
}

#------------------------------------------------------------------
sub _grabbed_href {
    my ($_href) = @_;

    foreach (@hrefs) {
        if ($_href =~ m/$_/) {
            return 'href="'.$_;
        }
    }

    # we did not grab that asset, so we will substitute it with itself
    return 'href="'.$1; ##no critic(RegularExpressions::ProhibitCaptureWithoutTest)
}

#------------------------------------------------------------------
sub _grabbed_src {
    my ($_src) = @_;

    foreach (@srcs) {
        if ($_src =~ m/$_/) {
            return 'src="'.$_;
        }
    }

    # we did not grab that asset, so we will substitute it with itself
    return 'src="'.$1; ##no critic(RegularExpressions::ProhibitCaptureWithoutTest)
}

#------------------------------------------------------------------
sub _grabbed_background_image {
    my ($_bg_image) = @_;

    foreach (@bg_images) {
        if ($_bg_image =~ m/$_/) {
            return 'style="background-image: url\('.$_;
        }
    }

    # we did not grab that asset, so we will substitute it with itself
    return 'style="background-image: url\('.$1; ##no critic(RegularExpressions::ProhibitCaptureWithoutTest)
}

#------------------------------------------------------------------
sub _replace_relative_urls_with_absolute {
    my ($_response_content_ref, $_response_base) = @_;

    # first we need to see if there are any substitutions defined for the base url - e.g. turn https: to http:
    foreach my $_sub ( keys %{ $userconfig->{baseurl_subs} } ) {
        #print "_sub:$_sub:$userconfig->{baseurl_subs}{$_sub}\n";
        #print "orig _response_base:$_response_base\n";
        my @_regex = split /[|][|][|]/, $userconfig->{baseurl_subs}{$_sub}; #index 0 contains the LHS, 1 the RHS
        $_response_base =~ s{$_regex[0]}{$_regex[1]}ee;
        #print "new _response_base:$_response_base\n";
    }

    while (
            ${ $_response_content_ref } =~ s{
                                                 (action|href|src)
                                                 [ ]{0,1}
                                                 =
                                                 [ ]{0,1}
                                                 ["']                                                     #" (fix editor code highlight)
                                                 (
                                                     [./a-gik-zA-GIK-Z~]                                  # will not match http or javascript
                                                     [^"']*                                               #" (fix editor code highlight)
                                                 )
                                                 ["']                                                     #" (fix editor code highlight)
                                             }
                                             {
                                                $1
                                                .'="'.
                                                _determine_absolute_url($2, $_response_base)
                                                .'"'
                                             }exg
          )
    {
        #print "$&\n";
    }

    return;
}

#------------------------------------------------------------------
sub _determine_absolute_url {
    my ($_ref, $_response_base) = @_;

    my $_ur_url = URI::URL->new($_ref, $_response_base);
    my $_abs_url = $_ur_url->abs;

    # we must return a url beginning with http (or javascript), otherwise WebInject will get stuck in an infinite loop
    # if the url we are processing begins with something like android-app://, URI:URL will not turn it into a http url - better just to get rid of it
    if ( (substr $_abs_url, 0, 1) ne 'h') {
        $_abs_url = 'http://webinject_could_not_determine_absolute_url';
    }

    return $_abs_url;
}

#------------------------------------------------------------------
sub _delayed_write_step_html {
    my ($_file_full, $_html) = @_;

    if (defined $delayed_file_full) { # will not be defined on very first call, since it is only written to by this sub
        if (defined $_html) { # will not be defined on very last call - sub finaltaks passes undef
            # substitute in the next test step number now that we know what it is
            $delayed_html =~ s{</wi_h2>}{ &nbsp; &nbsp; [<a href="$testnum_display$jumpbacksprint$retriesprint.html"> next </a>]</wi_h2>};
        }
        open my $_FILE, '>', "$delayed_file_full" or die "\nERROR: Failed to create $delayed_file_full\n\n";
        print {$_FILE} $delayed_html;
        close $_FILE or die "\nERROR: Failed to close $delayed_file_full\n\n";
    }

    $delayed_file_full = $_file_full;
    $delayed_html = $_html;

    return;
}

#------------------------------------------------------------------
sub finaltasks {  #do ending tasks

    # write out the html for the final test step, there is no new content to put in the buffer
    _delayed_write_step_html(undef, undef);

    writefinalhtml();  #write summary and closing tags for results file

    writefinalstdout();  #write summary and closing tags for STDOUT

    writefinalxml();  #write summary and closing tags for XML results file

    return;
}

#------------------------------------------------------------------
sub startseleniumbrowser {     ## start Selenium Remote Control browser if applicable
    require Selenium::Remote::Driver;
    require Selenium::Chrome;

    if (defined $driver) { #shut down any existing selenium browser session
        print {*STDOUT} " driver is defined so shutting down Selenium first\n";
        shutdown_selenium();
        sleep 2.1; ## Sleep for 2.1 seconds, give system a chance to settle before starting new browser
        print {*STDOUT} " Done shutting down Selenium\n";
    }

    if ($opt_port) {
        print {*STDOUT} "\nConnecting to Selenium Remote Control server on port $opt_port \n";
    }

    ## connecting to the Selenium server is done in a retry loop in case of slow startup
    ## see http://www.perlmonks.org/?node_id=355817
    my $max = 30;
    my $try = 0;

    ## --load-extension Loads an extension from the specified directory
    ## --whitelisted-extension-id
    ## http://rdekleijn.nl/functional-test-automation-over-a-proxy/
    ## http://bmp.lightbody.net/
    ATTEMPT:
    {
        eval
        {

            ## Phantomjs
            if ($opt_driver eq 'phantomjs') {
                $driver = Selenium::Remote::Driver->new('remote_server_addr' => 'localhost',
                                                    'port' => $opt_port,
                                                    'browser_name' => 'phantomjs',
                                                    );
            }

            ## Firefox
            if ($opt_driver eq 'firefox') {
                print {*STDOUT} qq|opt_proxy $opt_proxy\n|;
                $driver = Selenium::Remote::Driver->new('remote_server_addr' => 'localhost',
                                                    'port' => $opt_port,
                                                    'browser_name' => 'firefox',
                                                    'proxy' => {'proxyType' => 'manual', 'httpProxy' => $opt_proxy, 'sslProxy' => $opt_proxy },
                                                    );
             }

            ## ChromeDriver without Selenium Server or JRE
            if ($opt_driver eq 'chromedriver') {
                my $port = find_available_port(9585); ## find a free port to bind to, starting from this number
                if ($opt_proxy) {
                    print {*STDOUT} "Starting ChromeDriver using proxy at $opt_proxy\n";
                    $driver = Selenium::Chrome->new (binary => $opt_chromedriver_binary,
                                                 binary_port => $port,
                                                 _binary_args => " --port=$port --url-base=/wd/hub --verbose --log-path=$output".'chromedriver.log',
                                                 'browser_name' => 'chrome',
                                                 'proxy' => {'proxyType' => 'manual', 'httpProxy' => $opt_proxy, 'sslProxy' => $opt_proxy }
                                                 );

                } else {
                    print {*STDOUT} "Starting ChromeDriver without a proxy\n";
                    $driver = Selenium::Chrome->new (binary => $opt_chromedriver_binary,
                                                 binary_port => $port,
                                                 _binary_args => " --port=$port --url-base=/wd/hub --verbose --log-path=$output".'chromedriver.log',
                                                 'browser_name' => 'chrome'
                                                 );
                }
            }

            ## Chrome
            if ($opt_driver eq 'chrome') {
                my $_chrome_proxy = q{};
                if ($opt_proxy) {
                    print {*STDOUT} qq|Starting Chrome using proxy on port $opt_proxy\n|;
                    $driver = Selenium::Remote::Driver->new('remote_server_addr' => 'localhost',
                                                        'port' => $opt_port,
                                                        'browser_name' => 'chrome',
                                                        'proxy' => {'proxyType' => 'manual', 'httpProxy' => $opt_proxy, 'sslProxy' => $opt_proxy },
                                                        'extra_capabilities' => {'chromeOptions' => {'args' => ['window-size=1260,968']}}
                                                        );
                } else {
                    $driver = Selenium::Remote::Driver->new('remote_server_addr' => 'localhost',
                                                        'port' => $opt_port,
                                                        'browser_name' => 'chrome',
                                                        'extra_capabilities' => {'chromeOptions' => {'args' => ['window-size=1260,968']}}
                                                        );
                }
             }

                                                   #'proxy' => {'proxyType' => 'manual', 'httpProxy' => $opt_proxy, 'sslProxy' => $opt_proxy },
                                                   #'extra_capabilities' => {'chrome.switches' => ['--proxy-server="http://127.0.0.1:$opt_proxy" --incognito --window-size=1260,460'],},
                                                   #'extra_capabilities' => {'chrome.switches' => ['--incognito --window-size=1260,960']}
                                                   #'extra_capabilities' => {'chromeOptions' => {'args' => ['incognito','window-size=1260,960']}}
                                                   #'extra_capabilities' => {'chromeOptions' => {'args' => ['window-size=1260,968']}}

                                                   #'extra_capabilities'
                                                   #   => {'chromeOptions' => {'args'  =>         ['window-size=1260,960','incognito'],
                                                   #                           'prefs' => {'session' => {'restore_on_startup' =>4, 'urls_to_restore_on_startup' => ['http://www.google.com','http://www.example.com']},
                                                   #                                       'first_run_tabs' => ['http://www.mywebsite.com','http://www.google.de']
                                                   #                                      }
                                                   #                          }
                                                   #      }

        }; ## end eval

        if ( $@ and $try++ < $max )
        {
            print "\nError: $@ Failed try $try to connect to Selenium Server, retrying...\n";
            sleep 4; ## sleep for 4 seconds, Selenium Server may still be starting up
            redo ATTEMPT;
        }
    } ## end ATTEMPT

    if ($@) {
        print "\nError: $@ Failed to connect on port $opt_port after $max tries\n\n";
        die "WebInject Aborted - could not connect to Selenium Server\n";
    }

    ## this block finds out the Windows window handle of the chrome window so that we can do a very fast screenshot (as opposed to full page grab which is slow)
    my $thetime = time;
    eval { $driver->get("http://127.0.0.1:87/?windowidentify_$thetime-time"); }; ## we put the current time stamp in the window title, so this is multi-thread safe

    my $allchromehandle = (`plugins/GetWindows.exe`); ## this is a separate simple .NET C# program that lists all open windows and what their title is
    #print {*STDOUT} qq|$allchromehandle\n|;
    $allchromehandle =~ m{(\d+), http:..127.0.0.1:87..windowidentify_$thetime}s;
    if ($1)
    {
        $chromehandle = $1;
    }
    else
    {
        $chromehandle = 0;
    }
    print {*STDOUT} qq|CHROME HANDLE THIS SESSION\n$chromehandle\n|;

    #eval { $driver->set_window_size(968, 1260); }; ## y,x

    eval { $driver->set_timeout('page load', 30_000); };

    return;
}

sub port_available {
    my ($port) = @_;

    my $family = PF_INET;
    my $type   = SOCK_STREAM;
    my $proto  = getprotobyname 'tcp' or die "getprotobyname: $!\n";
    my $host   = INADDR_ANY;  # Use inet_aton for a specific interface

    socket my $sock, $family, $type, $proto or die "socket: $!\n";
    my $name = sockaddr_in($port, $host)     or die "sockaddr_in: $!\n";

    if (bind $sock, $name) {
        return 'available';
    }

    return 'in use';
}

sub find_available_port {
    my ($start_port) = @_;

    my $max_attempts = 20;
    foreach my $i (0..$max_attempts) {
        if (port_available($start_port + $i) eq 'available') {
            return $start_port + $i;
        }
    }

    return 'none';
}

sub shutdown_selenium {
    if ($opt_driver) {
        #print {*STDOUT} " Shutting down Selenium Browser Session\n";

        #my $close_handles = $driver->get_window_handles;
        #for my $close_handle (reverse 0..@{$close_handles}) {
        #   print {*STDOUT} "Shutting down window $close_handle\n";
        #   $driver->switch_to_window($close_handles->[$close_handle]);
        #   $driver->close();
        #}

        eval { $driver->quit(); }; ## shut down selenium browser session
        if ($opt_driver eq 'chromedriver') {
            eval { $driver->shutdown_binary(); }; ## shut down chromedriver binary
        }
        undef $driver;
    }

    return;
}
#------------------------------------------------------------------
sub startsession {     ## creates the webinject user agent
    #contsruct objects
    ## Authen::NTLM change allows ntlm authentication
    #$useragent = LWP::UserAgent->new; ## 1.41 version
    $useragent = LWP::UserAgent->new(keep_alive=>1);
    $cookie_jar = HTTP::Cookies->new;
    $useragent->agent('WebInject');  ## http useragent that will show up in webserver logs
    #$useragent->timeout(200); ## it is possible to override the default timeout of 360 seconds
    $useragent->max_redirect('0');  #don't follow redirects for GET's (POST's already don't follow, by default)
    eval
    {
       $useragent->ssl_opts(verify_hostname=>0); ## stop SSL Certs from being validated - only works on newer versions of of LWP so in an eval
       $useragent->ssl_opts(SSL_verify_mode=>SSL_VERIFY_NONE); ## from Perl 5.16.3 need this to prevent ugly warnings
    };

    #add proxy support if it is set in config.xml
    if ($config{proxy}) {
        $useragent->proxy(['http', 'https'], "$config{proxy}")
    }

    #add http basic authentication support
    #corresponds to:
    #$useragent->credentials('servername:portnumber', 'realm-name', 'username' => 'password');
    if (@httpauth) {
        #add the credentials to the user agent here. The foreach gives the reference to the tuple ($elem), and we
        #deref $elem to get the array elements.
        foreach my $elem(@httpauth) {
            #print {*STDOUT} "adding credential: $elem->[0]:$elem->[1], $elem->[2], $elem->[3] => $elem->[4]\n";
            $useragent->credentials("$elem->[0]:$elem->[1]", "$elem->[2]", "$elem->[3]" => "$elem->[4]");
        }
    }

    #change response delay timeout in seconds if it is set in config.xml
    if ($config{timeout}) {
        $useragent->timeout("$config{timeout}");  #default LWP timeout is 180 secs.
    }

    return;
}

#------------------------------------------------------------------
sub getoptions {  #shell options

    Getopt::Long::Configure('bundling');
    GetOptions(
        'v|V|version'   => \$opt_version,
        'c|config=s'    => \$opt_configfile,
        'o|output=s'    => \$opt_output,
        'a|autocontroller'    => \$opt_autocontroller,
        'p|port=s'    => \$opt_port,
        'x|proxy=s'   => \$opt_proxy,
        'd|driver=s'   => \$opt_driver,
        'y|binary=s'   => \$opt_chromedriver_binary,
        'r|proxyrules=s'   => \$opt_proxyrules,
        'i|ignoreretry'   => \$opt_ignoreretry,
        'h|help'   => \$opt_help,
        'u|publish-to=s' => \$opt_publish_full,
        )
        or do {
            print_usage();
            exit;
        };

    if ($opt_version) {
        print_version();
        exit;
    }

    if ($opt_help) {
        print_version();
        print_usage();
        exit;
    }

    if (defined $opt_driver) {
        if ($opt_driver eq 'chromedriver') {
            if (not defined $opt_chromedriver_binary) {
                print "\nLocation of chromedriver binary must be specified when chromedriver selected.\n\n";
                print "--binary C:\\selenium-server\\chromedriver.exe\n";
                exit;
            }
        }
    }

    if ($opt_output) {  #use output location if it is passed from the command line
        $output = $opt_output;
    }
    else {
        $output = 'output/'; ## default to the output folder under the current folder
    }
    $output = slash_me($output);
    $outputfolder = dirname($output.'dummy'); ## output folder supplied by command line might include a filename prefix that needs to be discarded, dummy text needed due to behaviour of dirname function

    # default the publish to location for the individual html step files
    if (not defined $opt_publish_full) {
        $opt_publish_full = $output;
    } else {
        $opt_publish_full = slash_me($opt_publish_full);
    }

    return;
}

sub print_version {
    print "\nWebInject version $VERSION\nFor more info: https://github.com/Qarj/WebInject\n\n";

    return;
}

sub print_usage {
        print <<'EOB'
Usage: webinject.pl testcase_file <<options>>

                                                    examples/simple.xml
-c|--config config_file                             -c config.xml
-o|--output output_location                         -o output/
-A|--autocontroller                                 -a
-p|--port selenium_port                             -p 8325
-x|--proxy proxy_server                             -x localhost:9222
-b|--basefolder baselined image folder              -b examples/basefoler/
-d|--driver chromedriver OR phantomjs OR firefox    -d chromedriver
-y|--binary for chromedriver                        -y C:\selenium-server\chromedriver.exe
-r|--proxyrules                                     -r true
-i|--ignoreretry                                    -i
-u|--publish-to                                     -u C:\inetpub\wwwroot\this_run_home

or

webinject.pl --version|-v
webinject.pl --help|-h
EOB
    ;

    return;
}
#------------------------------------------------------------------

## References
##
## http://www.kichwa.com/quik_ref/spec_variables.html
