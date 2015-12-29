# Wiki to OSM

This is a simple script to geolocate articles from a wikipedia dump,
make abstracts for articles and produce an OSM XML file from that.

## Installation

You would need to install `MediaWiki::DumpFile` CPAN module.
After that, you should patch it: on line 187 there is a check
for a dump version, it should pass even on version 0.10 (=0.1).

In the first lines of the scripts there are some constants.
You may need to alter `SUMMARY_LENGTH`, which is a maximum length
of a tag value. OSM has a limitation of 255 chars, but your
toolchain could accept more.

Also, there is a `MAIN_TAG`, since `wikipedia=*` is a secondary
tag, and you might need another one.

## Author and License

The script was written by Ilya Zverev, published under WTFPL.
