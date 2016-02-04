#!/usr/bin/perl
#
# This script is used to get Apache RANGER JIRA(s) that are 
#	(a)	in PATCH_AVAIL mode and 
#	(b)	have a valid patch attachment (.patch)
# And Then, check if there is already a PreCommit job executed for this attachment
#	If the preCommitJob is not already run for this job, it kicks off the preCommit job
#
#
# This should be invoked by Jenkins job on a regular time-interval with two specific env variable set
#       BUILD_USERNAME
#       BUILD_PASSWORD
# 
#
# Author: Selvamohan Neethiraj
# 02/02/2016
#
#
use strict;
use warnings;
use XML::XPath;
use POSIX qw(strftime) ;
use File::Temp qw(tempfile);

my $holdingFolder = "/var/lib/jenkins/ranger/processed" ;
my $jiraURL 	  = "https://issues.apache.org/jira/sr/jira.issueviews:searchrequest-xml/temp/SearchRequest.xml?jqlQuery=project+in+%28RANGER%29+AND+status+%3D+%22Patch+Available%22+AND+updated+%3E%3D+-2w+ORDER+BY+updated+DESC&tempMax=100" ;

sub get_processed_filename {
	my $fn = sprintf "%s/processedjiras_%s.txt", $holdingFolder, $ENV{"LOGNAME"} ;
	return $fn;
}

sub get_temp_filename {
    my $fh = File::Temp->new(TEMPLATE => 'jira_ranger_XXXXX', SUFFIX   => '.dat', UNLINK => 1, TMPDIR => 1);
    return $fh->filename;
}

my $curTimeStr = strftime "%m/%d/%y %H:%M:%S %Z", localtime();

my $lastProcessedFile = get_processed_filename() ;
my $file = get_temp_filename() ;

print "File : $file \n" ;

`curl -s -o $file $jiraURL` ;
my $dom = XML::XPath->new(filename => $file);
for my $node ($dom->findnodes('/rss/channel/item')) {
	for my $knode ($node->findnodes('key')) {
		my $patchName = "" ;
		my $id = "" ;
		my $prevCreatedTime = 0 ;
		for my $att ($node->findnodes('attachments/attachment')) {
			my $curId = $att->findnodes('@id') ; 
			my $curPatchName = $att->findnodes('@name') ; 
			if ($curPatchName =~ /.patch$/) {
				my $createdTimeStr = $att->findnodes('@created') ; 
				my $createdTime = `date -d "$createdTimeStr" "+%s"` ;
				#print "Patch : $curPatchName , $createdTime, $createdTimeStr \n" ;
				if (($prevCreatedTime == 0) || ($createdTime > $prevCreatedTime)) {
					#print "Making it as current Patch : $curPatchName , $createdTime \n" ;
					$patchName = $curPatchName->string_value ;
					$id = $curId->string_value ;
					$prevCreatedTime = $createdTime ;
				}
			}
		}
		if ($patchName ne "") {
			my $key = sprintf "%s|%s|%s", $knode->string_value, $id, $patchName  ;
			#print "Looking for processing $key ... \n" ;
			my $processKey = 1 ;
			if (-e $lastProcessedFile) {
				open my $fh, '<:encoding(UTF-8)', $lastProcessedFile or die "Can not open file for reading - '$lastProcessedFile' $!";
				while (my $line = <$fh>) {
					chomp $line ;
					if ($line eq $key) {
						#print "Found processed key: $line , $key \n" ;
						$processKey = 0 ; 
					}
				}
				close($fh);
			}
			if ($processKey == 1) {
				my @words = split /-/, $knode->string_value ;	
				my $buildUserName = $ENV{"BUILD_USERNAME"} ;
				my $buildPassword = $ENV{"BUILD_PASSWORD"} ;
				my $processURL = sprintf "curl  --user %s:%s -X POST \"https://builds.apache.org/view/PreCommit%%20Builds/job/PreCommit-RANGER-Build/build\" --data-urlencode json='{\"parameter\": [{\"name\":\"ISSUE_NUM\", \"value\":\"%s\"}]}'", $buildUserName, $buildPassword, $words[1] ;
				printf "Processing %s ...\n", $key ;
				`curl -s $processURL` ;
				open pFile, '>>', $lastProcessedFile or die "Could not open file for writing - '$lastProcessedFile' $!";
				printf pFile "#Processing - %s - at %s\n", $knode->string_value, $curTimeStr ;
				printf pFile "%s\n", $key ;
				close(pFile);
			}
			else {
				printf "Already processed %s\n", $key;
			}
		}
	}
}
unlink $file ;
