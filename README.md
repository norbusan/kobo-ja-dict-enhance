# kobo-ja-dict-enhance
Update the Kobo GloHD Japanese dictionary with English definitions
from edict (and or Japanese3).

## Options

`````
  -h, --help      Print this message and exit.
  -v, --version   Print version and exit.
  -i, --input     location of the original Kobo GloHD dict
                    default: dicthtml-jaxxdjs.zip
  -o, --output    name of the output file
                    default: dicthtml-jaxxdjs-TIMESTAMP.zip
  --dicts         dictionaries to be used, can be given multiple times
                  possible values are 'edict2' and 'japanese3'
                  The order determines the priority of the dictionary.
  -e, --edict     location of the edict2 file (default: edict2)
  -j, --japanese3 location of the japanese3 file (default: japanese3-data)
  --keep-input    keep the unpacked directory
  --keep-output   keep the updated output directory
  -u, --unpacked  location of an already unpacked original dictionary
  --unpackedzipped  location of an already unpacked original dictionary
                  where the html files are already un-gzipped
`````

## Notes

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

