package PDLNA::ContentLibrary;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2011 Stefan Heumader <stefan@heumader.at>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

use PDLNA::Config;
use PDLNA::ContentDirectory;
use PDLNA::Log;

sub new
{
	my $class = shift;
	my $params = shift;

	my $self = ();
	$self->{TIMESTAMP} = '';
	$self->{DIRECTORIES} = {};

	bless($self, $class);

	$self->{DIRECTORIES}->{0} = PDLNA::ContentDirectory->new({
		'type' => 'meta',
		'name' => 'BaseView',
		'id' => 0,
		'parent_id' => '',
	});

	if ($CONFIG{'SPECIFIC_VIEWS'})
	{
		$self->{DIRECTORIES}->{'A_A'} = PDLNA::ContentDirectory->new({
			'type' => 'meta',
			'name' => 'Audio sorted by Artist',
			'id' => 'A_A',
			'parent_id' => '',
		});
		$self->{DIRECTORIES}->{'A_F'} = PDLNA::ContentDirectory->new({
			'type' => 'meta',
			'name' => 'Audio sorted by Folder',
			'id' => 'A_F',
			'parent_id' => '',
		});
		$self->{DIRECTORIES}->{'A_G'} = PDLNA::ContentDirectory->new({
			'type' => 'meta',
			'name' => 'Audio sorted by Genre',
			'id' => 'A_G',
			'parent_id' => '',
		});
		$self->{DIRECTORIES}->{'A_M'} = PDLNA::ContentDirectory->new({ # moods: WTF (dynamic)
			'type' => 'meta',
			'name' => 'Audio sorted by Mood',
			'id' => 'A_M',
			'parent_id' => '',
		});
		$self->{DIRECTORIES}->{'A_T'} = PDLNA::ContentDirectory->new({
			'type' => 'meta',
			'name' => 'Audio sorted by Title (Alphabet)',
			'id' => 'A_M',
			'parent_id' => '',
		});

		$self->{DIRECTORIES}->{'I_F'} = PDLNA::ContentDirectory->new({
			'type' => 'meta',
			'name' => 'Images sorted by Folder',
			'id' => 'I_F',
			'parent_id' => '',
		});
		$self->{DIRECTORIES}->{'I_T'} = PDLNA::ContentDirectory->new({
			'type' => 'meta',
			'name' => 'Images sorted by Date',
			'id' => 'I_T',
			'parent_id' => '',
		});

		$self->{DIRECTORIES}->{'V_D'} = PDLNA::ContentDirectory->new({
			'type' => 'meta',
			'name' => 'Videos sorted by Date',
			'id' => 'V_D',
			'parent_id' => '',
		});
		$self->{DIRECTORIES}->{'V_F'} = PDLNA::ContentDirectory->new({
			'type' => 'meta',
			'name' => 'Videos sorted by Folder',
			'id' => 'V_F',
			'parent_id' => '',
		});
		$self->{DIRECTORIES}->{'V_T'} = PDLNA::ContentDirectory->new({
			'type' => 'meta',
			'name' => 'Videos sorted by Title (Alphabet)',
			'id' => 'V_T',
			'parent_id' => '',
		});
	}

	my $i = 100;
	foreach my $directory (@{$CONFIG{'DIRECTORIES'}})
	{
		if ($i > 999)
		{
			PDLNA::Log::log('More than 900 configured directories. Skip to load directory: '.$directory, 1, 'library');
			next;
		}

		# BaseView
		$self->{DIRECTORIES}->{0}->add_directory({
			'path' => $directory->{'path'},
			'type' => $directory->{'type'},
			'recursion' => $directory->{'recursion'},
			'id' => $i,
			'parent_id' => '',
		});
		$i++;
	}

    foreach my $external (@{$CONFIG{'EXTERNALS'}})
    {
        if ($i > 999)
        {
            PDLNA::Log::log('More than 900 configured main entries. Skip to load external: '.$external, 1, 'library');
            next;
        }

        # BaseView
        $self->{DIRECTORIES}->{0}->add_external({
            'path' => $external->{'path'},
            'type' => $external->{'type'},
            'recursion' => $external->{'recursion'},
            'id' => $i,
            'parent_id' => '',
        });
        $i++;
    }
    
	return $self;
}

sub is_directory
{
	return 1;
}

sub is_item
{
	return 0;
}

sub directories
{
	my $self = shift;
	return $self->{DIRECTORIES};
}

sub print_object
{
	my $self = shift;

	my $string = "\n\tObject PDLNA::ContentLibrary\n";
	foreach my $id (keys %{$self->{DIRECTORIES}})
	{
		$string .= $self->{DIRECTORIES}->{$id}->print_object("\t\t");
	}
	$string .= "\t\tTimestamp: $self->{TIMESTAMP}\n";
	$string .= "\tObject PDLNA::ContentLibrary END\n";

	return $string;
}

sub get_object_by_id
{
	my $self = shift;
	my $id = shift;

	if ($id =~ /^\d+$/) # if ID is numeric
	{
		return $self->{DIRECTORIES}->{0}->get_object_by_id($id);
	}

	return undef;
}

1;
