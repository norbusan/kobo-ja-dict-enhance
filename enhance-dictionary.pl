#!/usr/bin/perl
#
# enhance-dictionary.pl
# Update a Kobo GloHD Japanese dictionary with English definitions
# from the edict project.
#
# (C) 2015 Norbert Preining <norbert@preining.info>
# Licensed under GNU General Public License version 3 or any later version.
#
# Version: 0.3DEV
#
# Changelog:
# v0.1: first working version
# v0.2: do not depend on ja_JA locale, but use LC_CTYPE="C"
# v0.3: add translations to hiragana and katakana words
#
# Requirements
# - unix (for now!)
# - several Perl modules: Getopt::Long, File::Temp, File::Basename, Cwd
#   (all standard). Also PerlIO:gzip is needed to read/write directly
#   from gzipped files
# - 7z for unpacking with LANG support and packing up
#
# Current status based on 3.16.10 dictionary and edict2 and Japanese3:
# total words 805521, matches: 274464 (edict: 265953, japanese3: 8511)
#
# NOTES
# - Hiragana words are searched as *Katakana*, thus the Katakana entries
#   need to be translated!
#

use strict;
$^W = 1;

my $version = "0.3DEV";

use utf8;
binmode(STDOUT, ":utf8");
binmode(STDIN, ":utf8");

use Getopt::Long;
use File::Temp;
use File::Basename;
use Cwd 'abs_path';
#use Data::Dumper;

my $opt_edict = "edict2";
my $opt_jadict = "dicthtml-jaxxdjs.zip";
my $opt_japanese3 = "japanese3-data";
my @opt_dicts;
my $opt_out;
my $opt_keep_in = 0;
my $opt_keep_out = 0;
my $opt_unpacked;
my $opt_unpackedzipped;
my $help = 0;
my $opt_version = 0;
my $info;

# global vars of data
my %edict;
my %edictkana;
my %japanese3;
my %japanese3kana;
my %word2file;
my %dictfile;
my @words;

$| = 1; #autoflush

&main();

sub main() {
  GetOptions(
    "input|i=s"   => \$opt_jadict,
    "output|o=s"  => \$opt_out,
    "dicts=s"     => \@opt_dicts,
    "japanese3=s" => \$opt_japanese3,
    "edict|e=s"   => \$opt_edict,
    "keep-input"  => \$opt_keep_in,
    "keep-output" => \$opt_keep_out,
    "unpacked|u=s" => \$opt_unpacked,
    "unpackedzipped=s" => \$opt_unpackedzipped,
    "info=s"      => \$info,
    "help|?"      => \$help,
    "version|v"   => \$opt_version) or usage(1);
  usage(0) if $help;
  if ($opt_version) {
    print version();
    exit(0);
  }
  # try to auto-determine the list of dictionaries if nothing is passed in
  if (!@opt_dicts) {
    push @opt_dicts, 'edict2' if (-r $opt_edict);
    push @opt_dicts, 'japanese3' if (-r $opt_japanese3);
  }
  if (@opt_dicts) {
    print "Using the following dictionaries as source for translations: @opt_dicts\n";
  } else {
    die "No dictionary found or not readable, exiting.";
  }
  for my $d (@opt_dicts) {
    if ($d eq 'edict2') {
      load_edict($opt_edict);
    } elsif ($d eq 'japanese3') {
      load_japanese3($opt_japanese3);
    } else {
      die "Unknown dictionary: $d";
    }
  }
  if ($info) {
    utf8::decode($info);
    print "Info on $info:\n";
    print "Edict entry found: $edict{$info}\n" if ($edict{$info});
    print "EdictKana entry found: @{$edictkana{$info}}\n" if ($edictkana{$info});
    print "Japanese3 entry found: $japanese3{$info}\n" if ($japanese3{$info});
    print "Japanese3Kana entry found: @{$japanese3kana{$info}}\n" if ($japanese3kana{$info});
    exit(0);
  }
  my $orig;
  if ($opt_unpacked || $opt_unpackedzipped) {
    if (defined($opt_unpacked) && -d $opt_unpacked) {
      $orig = $opt_unpacked;
    } elsif (-d $opt_unpackedzipped) {
      $orig = $opt_unpackedzipped;
    } else {
      die "opt_unpacked/opt_unpackedzipped is NOT dir, exitint.";
    }
  } else {
    $orig = File::Temp::tempdir(CLEANUP => !$opt_keep_in);
    unpack_original_glohd($opt_jadict, $orig);
  }
  load_words($orig);
  load_dicts($orig);
  search_merge_edict();
  my $new = File::Temp::tempdir(CLEANUP => !$opt_keep_out);
  create_output_dir($new);
  create_dict($orig, $new, $opt_out);
}

sub version {
  my $prog = basename($0, ".pl");
  print "$prog version $version\n";
}

sub usage {
  my $exitcode = shift;
  my $prog = basename($0, ".pl");
  print <<"EOF";
Usage: $prog [OPTIONS]

Update the Kobo GloHD Japanese dictionary with English definitions
from edict (and or Japanese3).

Options:
  -h, --help            Print this message and exit.
  -v, --version         Print version and exit.
  --info=STR            Print info found on STR in dictionaries and exit.
  -i, --input=STR       location of the original Kobo GloHD dict
                          default: dicthtml-jaxxdjs.zip
  -o, --output=STR      name of the output file
                          default: dicthtml-jaxxdjs-TIMESTAMP.zip
  --dicts=STR           dictionaries to be used, can be given multiple times
                        possible values are 'edict2' and 'japanese3'
                        The order determines the priority of the dictionary.
                        If *not* given, all found dictionaries are used.
  -e, --edict=STR       location of the edict2 file
                          default: edict2
  -j, --japanese3=STR   location of the japanese3 file
                          default: japanese3-data
  --keep-input          keep the unpacked directory
  --keep-output         keep the updated output directory
  -u, --unpacked=STR    location of an already unpacked original dictionary
  --unpackedzipped=STR  location of an already unpacked original dictionary
                        where the html files are already un-gzipped

Notes:
* Unpacked dictionaries contain html and gif files that are
  actually gzip-compressed, but without .gz extensions.
  If you pass in an already unpacked dir as source via --unpacked, the
  html files still need to be gzipped. If you have already unpacked
  the html file, you can use --unpackedzipped.

* Dictionaries: at the moment edict2 (free) and Japanese3 (commercial) are
  supported. But as far as I see they are overlapping to a very high
  percentage. So keeping with edict2 is fine.

* The edict file can be downloaded from 
  http://ftp.monash.edu.au/pub/nihongo/edict2.gz
  Afterwards the file needs to be unpacked with 'gunzip edict2.gz'

* The 'japanese3-data' file has to be generated from the Japanese3 iPhone
  application https://itunes.apple.com/en/app/japanese/id290664053
  You need to copy the Japanese3.db from the application directory on the
  iPhone, then open it with 'sqlite3' application and do the following
  SQL query:
    .output japanese3-data
    select Entry, Furigana, Summary from entries;
  (For getting the file you probably need a jailbroken iOS)

EOF
;
  exit($exitcode);
}

sub load_words {
  my $loc = shift;
  open (my $wf, '<:encoding(utf8)', "$loc/words.original") or die "Cannot open $loc/words.original: $?";
  @words = <$wf>;
  chomp(@words);
  close $wf || warn "Cannot close words.original: $?";
}



#
# load edict data from file
# TODO:
# - evaluate hiragana???
sub load_edict {
  my $edict = shift;
  print "loading edict2 ... ";
  open (my $wf, '<:encoding(utf8)', $edict) or die "Cannot open $edict: $?";
  while (<$wf>) {
    chomp;
    my @fields = split(" ", $_, 2);
    my @kanji = split(/;/,$fields[0]);
    my $desc;
    my $kanastr;
    my @kana;
    # if the line is an entry for a Katakana/Hiragana word, there is 
    # no second field and the next one is immediately the English
    if ($fields[1] =~ m/^\//) {
      $desc = $fields[1];
    } else {
      ($kanastr, $desc) = split(" ", $fields[1], 2);
      $kanastr =~ s/^\[//;
      $kanastr =~ s/\]$//;
      @kana = split(/;/, $kanastr);
    }
    for my $k (@kanji) {
      $k =~ s/\(P\)$//;
      $edict{$k} = $desc;
      for my $ka (@kana) {
        $ka =~ s/\(P\)$//;
        push @{$edictkana{$ka}}, "$k: $desc";
      }
    }
  }
  print "done\n";
}

sub load_japanese3 {
  my $f = shift;
  return if (!$f);
  if (! -r $f) {
    die "Cannot read Japanese3 data file $f: $?";
  }
  print "loading Japanese3 data ... ";
  open (my $wf, '<:encoding(utf8)', $f) or die "Cannot open $f: $?";
  while (<$wf>) {
    chomp;
    # mind the ' and \ here, we have to ship in a regexp where | is escaped!
    my @fields = split('\|', $_, 3);
    my $kanj = $fields[0];
    my $furi = $fields[1];
    my $desc = $fields[2];
    if ($kanj && $desc) {
      $japanese3{$kanj} = $desc;
      if ($furi) {
        push @{$japanese3kana{$furi}}, "$kanj: $desc";
      }
    }
  }
  print "done\n";
  #print Dumper(\%japanese3);
  #exit 1;
}

sub unpack_original_glohd {
  print "unpacking original dictionary ... ";
  my ($opt_jadict, $orig) = @_;
  if (! -r $opt_jadict) {
    die "Cannot read $opt_jadict: $?";
  }
  $opt_jadict = abs_path($opt_jadict);
  if (! $opt_jadict) {
    die "Cannot determine abs path of $opt_jadict: $?";
  }
  `cd $orig ; LC_CTYPE=C 7z x \"$opt_jadict\"`;
  print "done\n";
}

sub load_dicts {
  my $loc = shift;
  # first load all dictionary files
  my @hf = <"$loc/*.html">;
  my $nr = $#hf;
  my $i = 0;
  for my $f (@hf) {
    $i++;
    my $per = int(($i/$nr)*10000)/100;
    print "\033[Jloading dict files ... ${per}%" . "\033[G";
    my $n = $f;
    utf8::decode($n);
    $n =~ s/^$loc\/(.*)\.html/$1/;
    #print "reading file $n (.html)\n";
    local $/;
    my $wf;
    if ($opt_unpackedzipped) {
      open ($wf, '<:utf8', $f) || die "Cannot open $f: $?";
    } else {
      open ($wf, '<:gzip:utf8', $f) || die "Cannot open $f: $?";
    }
    $dictfile{$n} = <$wf> ;
    close $wf || warn "Cannot close $f: $?";
  }
  print "loading dict files ... done\n";
}

# returns 0 on success
#         1 on doctfile not found
#         2 on dictfile exists but tag not found
sub check_dict {
  my ($word, $d, $verb) = @_;
  if ($dictfile{$d}) {
    if (grep(/name="\Q$word\E"/, $dictfile{$d})) {
      $word2file{$word} = $d;
      return 0;
    } else {
      print "\nname tag not found for $word in $d\n" if $verb;
      return 2;
    }
  } else {
    print "\nnot found $word (d=$d)\n" if $verb;
    return 1;
  }
}

#
# core routine
# search the correct file for an entry
# check for existence of translation
# update the file contents
sub search_merge_edict {
  my $nr = $#words;
  my $i = 0;
  my $found_edict = 0;
  my $found_japa = 0;
  my $found_total = 0;
  for my $word (@words) {
    $i++;
    my $per = int(($i/$nr)*10000)/100;
    print "\033[Jsearching for words and updating ... ${per}%" . "\033[G";
    my ($a, $b);
    my $foo = $word;
    $foo =~ s/\s//g;
    if ($foo =~ m/^(.)(.)/) {
      $a = $1;
      $b = $2;
    } else {
      $a = $word;
    }
    $a = lc($a);
    $b = lc($b) if $b;
    if ($a =~ m/[\p{Hiragana}\p{Katakana}a-z]/) {
      if ($b) {
        if (check_dict($word,"$a$b",0) != 0) {
          if ($a =~ m/[a-z]/) {
            if (check_dict($word,"${a}1",0) != 0) {
              if (check_dict($word,"${a}a",0) != 0) {
                check_dict($word, "11", 1);
              }
            }
          } else {
            print "\ngiving up(2): $word (ab=$a$b)\n";
          }
        }
      } else {
        if (check_dict($word,$a,0) != 0) {
          if (check_dict($word,"${a}a",0) != 0) {
            check_dict($word,"11", 1);
          }
        }
      }
    } else {
      if (check_dict($word,$a,0) != 0) {
        if (check_dict($word,"11",0) != 0) {
          if (check_dict($word,"${a}a", 0) != 0) {
            if ($b) {
              check_dict($word,"1$b", 1)
            } else {
              print "\ngiving up(1): $word (a=$a)\n";
            }
          }
        }
      }
    }
    if ($word2file{$word}) {
      my $hh = $word2file{$word};
      my $w;
      # do the dict check in reverse order so that the first listed dict
      # provides the proper value
      DICTS: for my $d (@opt_dicts) {
        if ($d eq 'edict2') {
          if ($edict{$word}) {
            $w = $edict{$word};
            $w =~ s/^\///;
            $w =~ s/EntL[0-9]*X?\/$//;
            $w =~ s/\/$//;
            $found_edict++;
            $found_total++;
            last DICTS;
          }
        } elsif ($d eq 'japanese3') {
          if ($japanese3{$word}) {
            $found_japa++;
            $found_total++;
            $w = $japanese3{$word};
            last DICTS;
          }
        } else {
          die "Unknown dictionary: $d";
        }
      }
      # mind the NOT GREEDY search for the first <p>!!! .*?
      if ($w) {
        # we should NOT blindly replace this, as we might end up with
        # things like:
        # <a name="だけ" /><b>たけ</b>【岳／嶽】<p>only‚ just‚ as<p>《
        # because Japanese3 ships a direct definitions of だけ which
        # is here used for replacing the definition os 岳 ...
        $dictfile{$hh} =~ s/(a name="\Q$word\E".*?)<p>/$1<p>$w<p>/;
      } else {
        # this is the case when we might have some kana reading.
        # check for possible kana readings
        # the possible list is a set of "KANJI: desc"
        my @possible_readings;
        my $source;
        my $hiraword = $word;
        # convert to hiragana
        $hiraword =~ tr/[\x{30A1}-\x{30FF}]/[\x{3041}-\x{3096}]/;
        DICTSKANA: for my $d (@opt_dicts) {
          if ($d eq 'edict2') {
            if ($edictkana{$word}) {
              @possible_readings = @{$edictkana{$word}};
              $source = \$found_edict;
              last DICTSKANA;
            } 
            if ($edictkana{$hiraword}) {
              @possible_readings = @{$edictkana{$hiraword}};
              $source = \$found_edict;
              last DICTSKANA;
            }
          } elsif ($d eq 'japanese3') {
            if ($japanese3kana{$word}) {
              @possible_readings = @{$japanese3kana{$word}};
              $source = \$found_japa;
              last DICTSKANA;
            }
            if ($japanese3kana{$hiraword}) {
              @possible_readings = @{$japanese3kana{$hiraword}};
              $source = \$found_japa;
              last DICTSKANA;
            }
          } else {
            # actually not necessary
            die "Unknown dictionary: $d";
          }
        }
        if (@possible_readings) {
          for my $pa (@possible_readings) {
            my ($kanji, $desc) = split(': ', $pa, 2);
            # here there are some cases that we do not cover:
            # - 【素晴（ら）しい】
            # - 【岳／嶽】 could be fixed by adding (\p{Kanji}／)* at the
            #              beginning and end
            if ($dictfile{$hh} =~ s/(a name="\Q$word\E".*?【\Q$kanji\E】)/$1<p>$desc/) {
              ${$source}++;
              $found_total++;
            }
          }
        }
      }
    }
  }
  print "searching for words and updating ... done\n";
  print "total words $nr, matches: $found_total (edict: $found_edict, japanese3: $found_japa)\n";
}

sub create_output_dir {
  my $newdir = shift;
  mkdir $newdir || die "cannot create $newdir: $?";
  my @dk = keys(%dictfile);
  my $nr = $#dk;
  my $i = 0;
  for my $k (@dk) {
    $i++;
    my $per = int(($i/$nr)*10000)/100;
    print "\033[Jcreating output html ... ${per}%" . "\033[G";
    my $fh;
    open $fh, ">:gzip:utf8", "$newdir/$k.html" || die "cannot open $newdir/$k.html: $?";
    print $fh $dictfile{$k};
    close $fh;
  }
  print "creating output html ... done\n";
}

sub create_dict {
  my ($old, $new, $opt_out) = @_;
  `cp $old/*.gif $new/`;
  `cp $old/words* $new/`;
  if (!$opt_out) {
    $opt_out = "dicthtml-jaxxdjs-" . `date +%Y%m%d%H%M`;
    chomp($opt_out);
    $opt_out .= ".zip";
  }
  my $out = abs_path($opt_out);
  print "creating update dictionary in $opt_out ... ";
  `cd \"$new\" ; 7z a \"$out\" *`;
  print "done\n";
}

# vim:set tabstop=2 expandtab: #
