#!/usr/bin/perl
#
# enhance-dictionary.pl
# Update a Kobo GloHD Japanese dictionary with definitions
# from edict2 dictionaries and Japanese3 dictionary.
#
# (C) 2015 Norbert Preining <norbert@preining.info>
# Licensed under GNU General Public License version 3 or any later version.
#
# Version: 1.1dev
#
# Changelog:
# v0.1: first working version
# v0.2: do not depend on ja_JA locale, but use LC_CTYPE="C"
# v1.0: 
#     - new mode, ignore the words.original file and simply go through
#       every entry in the dictionaries
#     - add translations to hiragana and katakana words
#     - translation of multiple Hiragana entries with different Kanjis
# v1.1:
#     - more error checking
#
# TODO
# - add switch --all (or similar) which includes definitions
#   from *all* used dictionaries. This way one could create a
#   dictionary with both German and English translations
#
# Requirements
# - unix (for now!)
# - several Perl modules: Getopt::Long, File::Temp, File::Basename, Cwd
#   (all standard). Also PerlIO:gzip is needed to read/write directly
#   from gzipped files
# - 7z for unpacking with LANG support and packing up
#
# Current status based on 3.17.3 dictionary:
# edict2 + japanese3
#   total entries: 922380, edict: 326064, jap3: 7390
# wadoku German edict2
#   total entries: 922380, edict: 368943, jap3: 0
#

use strict;
$^W = 1;

my $version = "1.1dev";

use utf8;
binmode(STDOUT, ":utf8");
binmode(STDIN, ":utf8");
binmode(STDERR, ":utf8");

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
my $opt_outputdir;
my $opt_keep_in = 0;
my $opt_keep_out = 0;
my $opt_unpacked;
my $opt_unpackedzipped;
my $help = 0;
my $opt_merge = 0;
my $opt_version = 0;
my $info;
my $opt_debug = 0;
my $opt_checkword;
my $opt_dev = 0;

# global vars of data
my @dicts;
my %dictfile;

$| = 1; #autoflush

&main();

sub main() {
  GetOptions(
    "input|i=s"   => \$opt_jadict,
    "output|o=s"  => \$opt_out,
    "dict=s"     => \@opt_dicts,
    "merge"       => \$opt_merge,
    "keep-input"  => \$opt_keep_in,
    "keep-output" => \$opt_keep_out,
    "unpacked|u=s" => \$opt_unpacked,
    "unpackedzipped=s" => \$opt_unpackedzipped,
    "outputdir=s" => \$opt_outputdir,
    "info=s"      => \$info,
    "help|?"      => \$help,
    "debug|d"     => \$opt_debug,
    "checkword=s" => \$opt_checkword,
    "dev" => \$opt_dev,
    "version|v"   => \$opt_version) or usage(1);
  usage(0) if $help;
  if ($opt_version) {
    print version();
    exit(0);
  }
  if ($opt_dev) {
    $opt_unpackedzipped = "orig";
    $opt_outputdir = "new";
    $opt_keep_out = 1;
  }
  # try to auto-determine the list of dictionaries if nothing is passed in
  if (!@opt_dicts) {
    push @opt_dicts, "edict2:$opt_edict" if (-r $opt_edict);
    push @opt_dicts, "japanese3:$opt_japanese3" if (-r $opt_japanese3);
  }
  if (@opt_dicts) {
    print "Using the following dictionaries as source for translations: @opt_dicts\n";
  } else {
    die "No dictionary found or not readable, exiting.";
  }
  for my $d (@opt_dicts) {
    my $type;
    my $path;
    if ($d =~ m/^(.*?:)?(.*)$/) {
      $type = ($1 ? $1 : "edict2");
      $path = $2;
      $type =~ s/:$//;
      if (! -r $path) {
        die "Cannot read $path.";
      }
      if ($type eq 'edict2') {
        push @dicts, load_edict($path);
      } elsif ($type eq 'japanese3') {
        push @dicts, load_japanese3($path);
      } else {
        die "Unknown dictionary type: $type";
      }
    } else {
      die "Cannot parse argument: $d";
    }
  }
  if ($info) {
    utf8::decode($info);
    print "Info on $info:\n";
    for my $d (@dicts) {
      print "Found >", $d->{$info}, "< in ", $d->{'__FILE'}, "\n" if ($d->{$info});
    }
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
  load_merge_dicts($orig);
  exit(0) if ($opt_checkword && !$opt_dev);
  if (!$opt_outputdir) {
    $opt_outputdir = File::Temp::tempdir(CLEANUP => !$opt_keep_out);
  }
  create_output_dir($opt_outputdir);
  exit(0) if $opt_dev;
  create_dict($orig, $opt_outputdir, $opt_out);
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

Update the Kobo GloHD Japanese dictionary with definitions
from edict2 dictionaries (and or Japanese3).

Options:
  -h, --help            Print this message and exit.
  -v, --version         Print version and exit.
  -i, --input=STR       location of the original Kobo GloHD dict
                          default: dicthtml-jaxxdjs.zip
  -o, --output=STR      name of the output file
                          default: dicthtml-jaxxdjs-TIMESTAMP.zip
  --dict=[TYPE:]PATH    specify a dictionary to use
                          TYPE can be either 'edict2' or 'japanese3'
                            if TYPE is missing 'edict2' is assumed
                          PATH gives the path to the dictionary
                          if nothing is specified, the program checks for
                          files 'edict2' and 'japanese3-data'
  -u, --unpacked=STR    location of an already unpacked original dictionary
  --unpackedzipped=STR  location of an already unpacked original dictionary
                        where the html files are already un-gzipped
  --outputdir=STR       where the new dictionary is made

Debugging and development options:
  -d, --debug           Print debug information, a lot of them!
  --checkword=STR       Checks for translations of word, mostly useful with -d
  --info=STR            Print info found on STR in dictionaries and exit.
  --keep-input          keep the unpacked directory
  --keep-output         keep the updated output directory

Examples:

  enhance-dictionary.pl

    will use files 'edict2' and 'japanese3-data' if they are found
    in the current working directory.

  enhance-dictionary.pl --dict=wadokudict
    
    will use the edict2 formatted Wadoku (Japanese-German) dictionary


Notes:
* Unpacked dictionaries contain html and gif files that are
  actually gzip-compressed, but without .gz extensions.
  If you pass in an already unpacked dir as source via --unpacked, the
  html files still need to be gzipped. If you have already unpacked
  the html file, you can use --unpackedzipped.

* Dictionaries: at the moment edict2 style dictionaries and
  Japanese3 (commercial) are supported. 
  But as far as I see they are overlapping to a very high
  percentage. So keeping with edict2 is fine.

* The edict file can be downloaded from 
  http://ftp.monash.edu.au/pub/nihongo/edict2.gz
  Afterwards the file needs to be unpacked with 'gunzip edict2.gz'

* For German translations get the Edict2 version of Wadoku from
  http://www.wadoku.de/wiki/display/WAD/Downloads+und+Links

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

#
# load edict data from file
# TODO:
# - evaluate hiragana???
sub load_edict {
  my $edict = shift;
  my %edict;
  $edict{'__TYPE'} = 'edict2';
  $edict{'__FILE'} = $edict;
  $edict{'__USED'} = 0;
  open (my $wf, '<:encoding(utf8)', $edict) or die "Cannot open $edict: $?";
  print "loading edict2 type from $edict ... ";
  my $line = 0;
  while (<$wf>) {
    $line++;
    chomp;
    next if m/^\s*$/;
    my @fields = split(" ", $_, 2);
    if ($#fields < 0) {
      warning("Cannot find first field, skipping. Line nr $line, =$_");
      next;
    }
    my @kanji = split(/;/,$fields[0]);
    my $desc;
    # if the line is an entry for a Katakana/Hiragana word, there is 
    # no second field and the next one is immediately the English
    if ($fields[1] =~ m/^\//) {
      $desc = $fields[1];
    } else {
      (undef, $desc) = split(" ", $fields[1], 2);
    }
    # trim edict description string
    if (!$desc) {
      warning("Didn't get description, skipping. Line nr $line, =$_");
      next;
    }
    $desc =~ s/^\///;
    $desc =~ s/EntL[0-9]*X?\/$//;
    $desc =~ s/\/$//;
    for my $k (@kanji) {
      $k =~ s/\(P\)$//;
      $edict{$k} = $desc;
    }
  }
  print "done\n";
  return \%edict;
}

sub load_japanese3 {
  my $f = shift;
  my %japanese3;
  $japanese3{'__TYPE'} = 'japanese3';
  $japanese3{'__FILE'} = $f;
  $japanese3{'__USED'} = 0;
  open (my $wf, '<:encoding(utf8)', $f) or die "Cannot open $f: $?";
  print "loading Japanese3 data from $f ... ";
  while (<$wf>) {
    chomp;
    # mind the ' and \ here, we have to ship in a regexp where | is escaped!
    my @fields = split('\|', $_, 3);
    my $kanj = $fields[0];
    my $furi = $fields[1];
    my $desc = $fields[2];
    if ($kanj && $desc) {
      $japanese3{$kanj} = $desc;
    }
  }
  print "done\n";
  return \%japanese3;
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

sub load_merge_dicts {
  my $loc = shift;
  # first load all dictionary files
  my @hf = <"$loc/*.html">;
  my $nr = $#hf;
  my $i = 0;
  my $entries_total = 0;
  my $trans_edict = 0;
  my $trans_jap3  = 0;
  for my $f (@hf) {
    $i++;
    my $per = int(($i/$nr)*10000)/100;
    print "\033[Jloading and merging dict files ... ${per}%" . "\033[G";
    my $n = $f;
    utf8::decode($n);
    $n =~ s/^$loc\/(.*)\.html/$1/;
    if ($opt_dev && $opt_checkword) {
      next if ($n ne $opt_checkword);
    }
    debug("reading file $n (.html)\n");
    local $/;
    my $wf;
    if ($opt_unpackedzipped) {
      open ($wf, '<:utf8', $f) || die "Cannot open $f: $?";
    } else {
      open ($wf, '<:gzip:utf8', $f) || die "Cannot open $f: $?";
    }
    my $str = <$wf> ;
    close $wf || warn "Cannot close $f: $?";
    # this is already the replaced entry!
    $dictfile{$n} = update_definition($n, $str, \$entries_total);
  }
  print "loading and merging dict files ... done\n";
  print "total entries: $entries_total\n";
  for my $d (@dicts) {
    print "entries used from ", $d->{'__FILE'}, ": ", $d->{'__USED'}, "\n";
  }
}
 
sub update_definition {
  my ($n, $str, $totalref) = @_;
  my $new = '';
  # read in header of file
  if ($str =~ m/^(.*?<a name=")/g) {
    $new .= $1;
  } else {
    die "Cannot parse $n.";
  }
  while ($str =~ m/(.*?(<a name="|$))/g) {
    # debug("===found $1\n");
    if ($1) {
      ${$totalref}++;
      # we get one return value with empty match!
      my $entry = $1;
      my $nentry = '';
      # we can have img stuff interspersed!!!
      if ($entry =~ m!^(?:<img src=.*?</img>)?([^"]*)(?:<img src=.*?</img>)?([^"]*)(?:<img src=.*?</img>)?"\s*/>(<b>.*?</b>)?(〔.*?〕)?(【.*?】)?(.*?)<p>(.*)$!) {
        my $key = '';
        my $reading = $3;
        my $something = $4;
        my $kanjipart = $5;
        my $something2 = $6;
        my $definition = $7;
        $key .= $1 if $1; $key .= $2 if $2;
        # the kanji part can have the following forms:
        # - roman letters only
        # - kanji with （）and ／
        my $w;
        if ($kanjipart) {
          $kanjipart =~ s/^【//;
          $kanjipart =~ s/】$//;
          # split after ／
          KANJIPART: for my $k (split('／', $kanjipart)) {
            my $s;
            last KANJIPART if ($w = find_translation($k));
            # try to remove parenthesis
            my $a = $k;
            $a =~ s/（//g;
            $a =~ s/）//g;
            if ($a ne $k) {
              last KANJIPART if ($w = find_translation($a));
            }
            $a = $k;
            $a =~ s/（[^）]*）//g;
            if ($a ne $k) {
              last KANJIPART if ($w = find_translation($a));
            }
          }
        }
        $nentry = $entry;
        if ($w) {
          $nentry =~ s/(【.*?】)(.*?)<p>/$1$2<p>$w<p>/;
        }
      } else {
        print "cannot parse entry in $n: $entry\n";
        $nentry = $entry;
      }
      $new .= $nentry;
    }
  }
  return($new);
}

sub find_translation {
  my $word = shift;
  debug("find_translation: searching for $word\n");
  # do the dict check in reverse order so that the first listed dict
  # provides the proper value
  my @w;
  for my $d (@dicts) {
    my $tw = $d->{$word};
    if ($tw) {
      $d->{'__USED'} = $d->{'__USED'} + 1;
      push @w, $tw;
      last if (!$opt_merge);
    }
  }
  my $w = join('<p>', @w);
  debug("find_translation: found hit for $word: $w\n") if $w;
  return $w;
}

sub create_output_dir {
  my $newdir = shift;
  mkdir $newdir || die "cannot create $newdir: $?";
  my @dk = keys(%dictfile);
  my $nr = $#dk + 1;
  my $i = 0;
  for my $k (@dk) {
    $i++;
    my $per = int(($i/$nr)*10000)/100;
    print "\033[Jcreating output html ... ${per}%" . "\033[G";
    next if ($opt_dev && $opt_checkword && ($opt_checkword ne $k));
    my $fh;
    if ($opt_dev) {
      open $fh, ">:utf8", "$newdir/$k.html" || die "cannot open $newdir/$k.html: $?";
    } else {
      open $fh, ">:gzip:utf8", "$newdir/$k.html" || die "cannot open $newdir/$k.html: $?";
    }
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

sub debug {
  print STDERR @_ if $opt_debug;
}
sub warning {
  print STDERR @_;
}
# vim:set tabstop=2 expandtab: #
