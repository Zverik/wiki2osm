#!/usr/bin/env perl
# Read wiki pages+articles dump, and mix in external links dump to produce OSM XML file.
# Settings are in constants at the top of this script.
# Get dumps at https://dumps.wikimedia.org/backup-index.html
#
# WARNING: for dumps of versions 0.10+, MediaWiki::DumpFile::Pages should be patched
# (at line 187), since it compares versions numerically.
use strict;
use warnings;
use utf8;
use open qw(:std :utf8);
use MediaWiki::DumpFile;

use constant SUMMARY_LENGTH => 255 * 4;
use constant SUMMARY_KEY => 'description';
use constant MAIN_TAG => 'tourism=wikipedia';
use constant MAX_ARTICLES => 1_000_000;

sub wiki_summary {
  my $content = shift;
  # turn links (wiki and regular) to a plain text
  1 while $content =~ s/\[\[(?:[^\[\]:]+\|)?([^\[\]:]+)\]\]/$1/g;
  $content =~ s/(?<!\[)\[[^\s\[\]]+\s+([^\[\]]+)\](?!\])/$1/g;
  # strip special wiki links
  $content =~ s/\[\[[^\[\]|]+:[^\[\]]+\]\]//g;
  # process skipped links with a semicolon
  $content =~ s/\[\[(?:[^\[\]]+\|)?([^\[\]]+)\]\]/$1/g;
  # strip templates
  1 while $content =~ s/{{[^{}]*}}//gs;
  # strip tags, and especially refs
  $content =~ s#<(ref|timeline)[^>/]*>.*?</\1>##gs;
  $content =~ s#<.*?>##gs;
  # process special chars
  $content =~ s/&nbsp;/ /g;
  $content =~ s/&quot;/"/g;
  # after that, remove empty quoting
  $content =~ s/\([,\s]*\)//g;
  # remove tables
  $content =~ s/{\|.+?\|}//gs;
  # shorten headers
  $content =~ s/(==+)\s*([^=]+?)\s*\1/[$2]/g;
  # delete empty sections
  $content =~ s/(?:\[[^\]]+\]\s*)+\[/[/g;
  # strip some formatting
  $content =~ s/'{3,}//g;
  # delete stray spaces
  $content =~ s/\([\s,;]+/(/g;
  $content =~ s/[\s,;]+(?=[),;.])//g;
  # make in in a single line
  $content =~ s/\s+/ /g;
  $content =~ s/^ | $//g;
  # cut line to N chars
  if (length($content) > SUMMARY_LENGTH) {
    my $i = SUMMARY_LENGTH - 1;
    $i-- while ($i > SUMMARY_LENGTH - 50 && substr($content, $i, 1) ne ' ');
    $content = substr($content, 0, $i).'…';
  }
  return $content;
}

sub parse_params {
  my $params = shift;
  return if $params =~ /globe:(?!earth|_|$)/i;
  return if $params !~ /^([-+]?[\d.]+)_([-+]?[\d.]*)_?([-+]?[\d.]*)_?([NSZ])_([-+]?[\d.]+)_([-+]?[\d.]*)_?([-+]?[\d.]*)_?([EOW])/;
  my $lat = (1.0 * $1) + ($2 || 0) / 60.0 + ($3 || 0) / 3600.0;
  $lat = -$lat if $4 ne 'N';
  my $lon = (1.0 * $5) + ($6 || 0) / 60.0 + ($7 || 0) / 3600.0;
  $lon = -$lon if $8 eq 'W';
  return [$lat, $lon];
}

sub dist {
  my ($a, $b) = @_;
  my $dx = $a->[0] - $b->[0];
  my $dy = $a->[1] - $b->[1];
  return abs($dx) + abs($dy);
}

sub xml_encode {
  my $s = shift;
  $s =~ s/&/&amp;/g;
  $s =~ s/</&lt;/g;
  $s =~ s/>/&gt;/g;
  $s =~ s/"/&quot;/g;
  return $s;
}

if ($#ARGV < 0) {
  print "Syntax: $0 <pages.xml> <links.sql>\n";
  print "Alternative: $0 <article.wiki>\n";
  print "The script prints OSM XML to the stdout.\n";
  print "Or prepares a summary from a wikitext.\n";
  exit(1);
}

if ($#ARGV == 0) {
  undef $/;
  my $content = <>;
  print wiki_summary($content)."\n";
  exit(0);
}

my $mw = MediaWiki::DumpFile->new;

my %page2latlon;
my %bad_ids;

my $links = $mw->sql($ARGV[1]);
if ($links->table_name ne 'externallinks') {
  print "Expected sql of external links\n";
  exit(1);
}
while (defined(my $row = $links->next)) {
  next if $row->{'el_from_namespace'} ne '0';
  my $id = $row->{'el_from'};
  next if exists $bad_ids{$id};
  next if $row->{'el_to'} !~ /geohack.+[?&]params=([^&]+)/;
  my $params = $1;
  my $latlon = parse_params($params);
  #print "FAIL: $params\n" if !$latlon && $params !~ /globe/i;
  next if !$latlon;
  if (exists($page2latlon{$id})) {
    if (dist($page2latlon{$id}, $latlon) > 0.01) {
      delete $page2latlon{$id};
      $bad_ids{$id} = undef;
    }
  } else {
    $page2latlon{$id} = $latlon;
  }
}
print STDERR "Total links: ".(scalar keys %page2latlon)."\n";

my $pages = $mw->pages($ARGV[0]);

my $limit = MAX_ARTICLES;
my $count = 0;
print "<?xml version='1.0' encoding='UTF-8'?><osm version=\"0.6\" generator=\"wiki2osm.pl\">\n";
my ($lang) = ($pages->base =~ m#://(\w+?)\.wikipedia#);
die "No language defined" if length($lang) <= 1;
my ($main_key, $main_value) = (MAIN_TAG =~ /^(.+?)=(.+)$/);
while (defined(my $page = $pages->next)) {
  next if $page->title =~ /^[^ ]+?:/;
  if (exists($page2latlon{$page->id})) {
    $count++;
    last if --$limit < 0;
    my $ll = $page2latlon{$page->id};
    printf '<node id="%d" lat="%0.6f" lon="%0.6f" version="1">'."\n", $count, $ll->[0], $ll->[1];
    print "  <tag k=\"$main_key\" v=\"$main_value\" />\n";
    print '  <tag k="wikipedia" v="'.$lang.':'.xml_encode($page->title)."\" />\n";
    print '  <tag k="'.SUMMARY_KEY.'" v="'.xml_encode(wiki_summary($page->revision->text))."\" />\n";
    print "</node>\n";
  }
}
print "</osm>\n";
print STDERR "Total pages: $count\n";
