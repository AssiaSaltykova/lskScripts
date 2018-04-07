#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use File::Basename qw/fileparse basename/;

# custom perl modules
use FindBin;
use lib "$FindBin::RealBin/lib";
use lib "$FindBin::RealBin/../lib"; # in case the script is in a separate scripts directory
use Vcf;

local $0=basename($0);
sub logmsg{print STDERR "$0: @_\n";}
exit main();

sub main{
  my $settings={};
  GetOptions($settings,qw(help format=s version=s));
  $$settings{version}||="4.1";
  die usage() if($$settings{help} || !@ARGV);

  my ($mummer)=@ARGV;
  convertMummer($mummer,$settings);

  return 0;
}

sub convertMummer{
  my($mummer,$settings)=@_;
  
  # Input/Output streaming
  my $vcf=Vcf->new(version=>$$settings{version},strict=>1);
  open(MUMMER,$mummer) or die "ERROR: could not open mummer file: $!";

  # get header information
  my $files=<MUMMER>;
  my $program=<MUMMER>;
  my $blankLine=<MUMMER>;
  my $header=<MUMMER>;
  chomp($files,$program,$blankLine,$header);
  $header=~s/^\s+|\s+$//g;
  my($refFile,$queryFile)=split(/\s+/,$files);
  my @header=split(/\s+/,$header);
  for(@header){
    $_=~s/^\s+|\s+$//g; # remove whitespace (hopefully it didn't exist anyway)
    $_=~s/^\[|\]$//g;   # remove brackets
  }
  $header[1]="SUB 1"; # fix duplicate header
  $header[2]="SUB 2"; # fix duplicate header
  my $numHeaders=@header;
  #die Dumper($refFile,$queryFile,$program,$blankLine,$header,\@header);

  # Translate what we can to VCF headers.  Headers cannot be modified after being printed.
  $vcf->add_header_line({key=>"reference",value=>$refFile});
  $vcf->add_header_line({key=>"query",value=>$queryFile});
  $vcf->add_header_line({key=>"source",value=>$program});
  my $printedHeader=0; # set to true whenever the header is printed
  my %contigSeen;      # keep track of contigs we've seen

  # get the values from mummer file
  my $vcfBuffer;
  while(<MUMMER>){
    s/^\s+|\s+$//g;
    next if($_=~/====/);
    my @row=split(/\s+/,$_);
    my %hash;
    @hash{qw(P1 SUB1 SUB2 P2 | BUFF DIST | LEN_R LEN_Q | START_1 START_2 REF QUERY)}=@row;
    #die Dumper \%hash;
    $hash{TAGS}=[$hash{REF},$hash{QUERY}];

    my $refContig=$hash{TAGS}[0];
    if(!$contigSeen{$refContig}++){
      $vcf->add_header_line({key=>"contig",ID=>$refContig});
    }

    # In the mummer world, a dot means indel but in the VCF world, it means 'same'
    if($hash{'SUB1'} eq '.'){
      $hash{'SUB1'}="*";
      #$hash{'SUB2'}="N".$hash{'SUB2'};
    }
    if($hash{'SUB2'} eq '.'){
      #$hash{'SUB1'}="N".$hash{'SUB1'};
      $hash{'SUB2'}="*";
    }

    $vcfBuffer.=join("\t",$hash{REF},$hash{P1},'.',$hash{SUB1},$hash{SUB2},'.','PASS','NS=2','GT',0,1)."\n";
    next;

    # convert to the VCF line format which is wonky
    my $x={
      FORMAT=>['GT'],
      QUAL  =>'.',
      ID    =>'.',
      CHROM =>$hash{TAGS}[0],
      INFO  =>{},
      FILTER=>['.'],
      gtypes=>{ 
                $hash{REF} => {
                                GT=>$hash{SUB1}
                                #GT=>'0'
                              },
                $hash{QUERY} => {
                                #GT=>'1'
                                GT=>$hash{SUB2}
                              }
                },
      REF   =>$hash{SUB1},
      ALT   =>[
                $hash{SUB2}
              ],
      POS   =>$hash{P1},
    };
    #die Dumper $x;
    $vcf->format_genotype_strings($x);  # things apparently need to be formatted correctly even after this hot mess of a hash
    $vcf->validate_line($x);

    # ready to format the line
    $vcfBuffer.=$vcf->format_line($x);
  }
  close MUMMER;

  # ready to print out everything
  print $vcf->format_header();  # Cannot give any more headers after printing them
  print $vcfBuffer;
    
}

sub usage{
  "Converts mummer format to Vcf.
  Usage: $0 mummer.snps > file.vcf
  -version 4.1 The VCF version to use
  ";
}
