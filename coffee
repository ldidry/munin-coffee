#!/usr/bin/perl
# vim: set filetype=perl sts=4 sw=4 tabstop=4 expandtab smartindent: #

=head1 NAME

  coffee - Plugin to monitor your coffee pot level

=head1 AUTHOR AND COPYRIGHT

  Copyright 2013 Luc Didry <luc AT didry.org>

=head1 HOWTO CONFIGURE AND USE :

=over

=item - /etc/munin/plugins/coffee

     cp coffee /etc/munin/plugins/

=item - /etc/munin/plugin-conf.d/coffee

     [coffee]
     env.start_pixel_x 1    # x coordinate of the top pixel of the ruler (default 1)
     env.start_pixel_y 1    # y coordinate of the top pixel of the ruler (default 1)
     env.r_min 0            # RGB colors min and max values.
     env.r_max 0.2          # If a pixel got its RGB values inside the min and max, it's a win !
     env.g_min 0
     env.g_max 0.2
     env.b_min 0
     env.b_max 0.2
     env.height 100         # length of the ruler (start from the top pixel and goes to bottom) (default 100)
     env.device /dev/video0 # video device (i.e. the webcam) used to take picture (default /dev/video0)
     env.warning 20         # get prepared to make more coffee
     env.critical 5         # Oh my god ! How can we work now ? We need to make coffee !

=item - restart Munin node

     /etc/init.d/munin-node restart

=back

=head1 DEPENDANCIES
    You will need :
        * ffmpeg
        * imagemagick
        * zbar
        * Image::Magick perl module

=head1 WARNING !

    You also need to put a QRcode on your coffeepot to check its presence.
    You will find the QRcode in the git repo
    https://github.com/ldidry/munin-coffee

=head1 LICENSE

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut

use warnings;
use strict;
use Munin::Plugin;
use Image::Magick;
use Data::Dumper;

my $PLUGIN_NAME = "coffee";
my $PICTURE = "$Munin::Plugin::pluginstatedir/picture.jpg";
my $START_X = $ENV{start_pixel_x};
my $START_Y = $ENV{start_pixel_y};
my $RMIN    = $ENV{r_min}  || 0;
my $RMAX    = $ENV{r_max}  || 0.2;
my $GMIN    = $ENV{g_min}  || 0;
my $GMAX    = $ENV{g_max}  || 0.2;
my $BMIN    = $ENV{b_min}  || 0;
my $BMAX    = $ENV{b_max}  || 0.2;
my $HEIGHT  = $ENV{height} || 100;
my $DEVICE  = (defined $ENV{device}) ? $ENV{device} : "/dev/video0";

## In the parent, it's just a regular munin plugin which reads a file with the infos
##### config
if( (defined $ARGV[0]) && ($ARGV[0] eq "config") ) {
    print "graph_title Coffee level\n";
    print "graph_vlabel level of coffee in coffee pot\n";
    print "graph_info This graph shows how much coffee there is in the coffee pot\n";
    print "graph_args -u 100 -l 0\n";
    print "coffee.label coffee level\n";
    print "coffee.warning $ENV{warning}\n" if defined $ENV{warning};
    print "coffee.critical $ENV{critical}\n" if defined $ENV{critical};
    print "coffee.draw AREA\n";
    ## Done !
    _munin_exit_done();
}

##### fetch
# take picture
if (!-e $DEVICE) {
    print "Can't see video device: $DEVICE\n";
    _munin_exit_fail();
}
if (system("ffmpeg -y -f video4linux2 -i $DEVICE -vframes 1 $PICTURE")) {
    print "Error while taking photo from video device $DEVICE to $PICTURE\n";
    _munin_exit_fail();
}

# check if the coffee pot is present with QRcode
_munin_exit_done() unless (`zbarimg $PICTURE` =~ m/QR-Code:present/m);

# get the ruler pixels informations
my $image = new Image::Magick;
$image->Read($PICTURE);
my @pixels = $image->GetPixels(
    x         => $START_X,
    y         => $START_Y,
    width     => 1,
    height    => $HEIGHT,
    normalize => 1
);
for (my $i = $START_Y; $i < $START_Y + $HEIGHT; $i++) {
    $image->Set('pixel['.$START_X.','.$i.']' =>  'red');
}
$image->Write('/tmp/coffee_check.png');

my @cleaned;
while (scalar @pixels) {
    push @cleaned, {
       r => shift @pixels,
       g => shift @pixels,
       b => shift @pixels
    };
}

# get the level
my $i = 0;
foreach my $pixel (@cleaned) {
    if ($pixel->{r} >= $RMIN && $pixel->{r} < $RMAX &&
        $pixel->{g} >= $GMIN && $pixel->{g} < $GMAX &&
        $pixel->{b} >= $BMIN && $pixel->{b} < $BMAX ) {
        my $level = 100 * ($HEIGHT - $i) / $HEIGHT;
        printf "coffee.value %.2f\n", $level;
        _munin_exit_done();
    }
    $i++;
}
printf "coffee.value 0\n";

_munin_exit_done();
#
###############################################################################

sub _munin_exit_done {
    _munin_exit(0);
} ## sub _munin_exit_done

sub _munin_exit_fail {
    _munin_exit(1);
} ## sub _munin_exit_fail

sub _munin_exit {
    my $exitcode = shift;
    exit($exitcode) if(defined $exitcode);
    exit(1);
} ## sub _munin_exit
