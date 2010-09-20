package PDLNA::HTTPServer;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010 Stefan Heumader <stefan@heumader.at>
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

use Data::Dumper;
use XML::Simple;
use Date::Format;

use Socket;
use IO::Select;

use threads;
use threads::shared;

use PDLNA::Config;
use PDLNA::Log;
use PDLNA::Content;

our $content = undef;

sub initialize_content
{
	$content = PDLNA::Content->new();
	$content->print_object();
}

sub start_webserver
{
	PDLNA::Log::log('Starting HTTP Server listening on '.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'.', 0);

	# I got inspired by: http://www.adp-gmbh.ch/perl/webserver/
	local *S;
	socket(S, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die "Can't open HTTPServer socket: $!\n";
	setsockopt(S, SOL_SOCKET, SO_REUSEADDR, 1);
	my $server_ip = inet_aton($CONFIG{'LOCAL_IPADDR'});
	bind(S, sockaddr_in($CONFIG{'HTTP_PORT'}, $server_ip)); # INADDR_ANY
	listen(S, 5) || die "Can't listen to HTTPServer socket: $!\n";

	my $ss = IO::Select->new();
	$ss->add(*S);

	while(1)
	{
		my @connections_pending = $ss->can_read();
		foreach my $connection (@connections_pending)
		{
			my $FH;
			my $remote = accept($FH, $connection);
			my ($peer_src_port, $peer_addr) = sockaddr_in($remote);
			my $peer_ip_addr = inet_ntoa($peer_addr);

			my $thread = threads->create(\&handle_connection, $FH, $peer_ip_addr, $peer_src_port);
			$thread->detach();
		}
	}
}

sub handle_connection
{
	my $FH = shift;
	my $peer_ip_addr = shift;
	my $peer_src_port = shift;

	binmode($FH);

	my %CGI = ();
	my %ENV = ();

	my $post_xml = undef;
	my $request_line = <$FH>;
	my $first_line = '';
	while ($request_line ne "\r\n")
	{
		next unless $request_line;
		$request_line =~ s/\r\n//g;
		chomp($request_line);

		if (!$first_line)
		{
			$first_line = $request_line;

			my @parts = split(' ', $first_line);
			close $FH if @parts != 3;

			$ENV{'METHOD'} = $parts[0];
			$ENV{'OBJECT'} = $parts[1];
		}
		else
		{
			my ($name, $value) = split(': ', $request_line);
			$name = uc($name);
			$CGI{$name} = $value;
		}
		$request_line = <$FH>;
	}
	if ($ENV{'METHOD'} eq "POST")
	{
		$CGI{'POSTDATA'} = <$FH>;
		my $xmlsimple = XML::Simple->new();
		$post_xml = $xmlsimple->XMLin($CGI{'POSTDATA'});
	}

	PDLNA::Log::log('New HTTP Connection: '.$peer_ip_addr.':'.$peer_src_port.' -> Request: '.$ENV{'METHOD'}.' '.$ENV{'OBJECT'}.'.', 1);
	PDLNA::Log::log('HTTP Connection: CGI hash:', 2);
	foreach my $key (keys %CGI)
	{
		PDLNA::Log::log("\t".$key.' -> '.$CGI{$key}, 2);
	}
	PDLNA::Log::log('--------------', 2);

	if ($ENV{'OBJECT'} eq '/ServerDesc.xml')
	{
		print $FH "HTTP/1.0 200 OK\r\n";
		print $FH "Server: $CONFIG{'PROGRAM_NAME'} v$CONFIG{'PROGRAM_VERSION'} Webserver\r\n";
		print $FH "\r\n";
		server_description($FH);
	}
	elsif ($ENV{'OBJECT'} eq '/upnp/control/ContentDirectory1')
	{
		print $FH "HTTP/1.0 200 OK\r\n";
		print $FH "Server: $CONFIG{'PROGRAM_NAME'} v$CONFIG{'PROGRAM_VERSION'} Webserver\r\n";
		print $FH "\r\n";
		ctrl_content_directory_1($FH, $post_xml, $CGI{'SOAPACTION'});
		print $FH "\r\n";
	}
	elsif ($ENV{'OBJECT'} =~ /^\/media\/(.*)$/)
	{
		stream_media($FH, $1);
		print $FH "\r\n";
	}
	elsif ($ENV{'OBJECT'} =~ /^\/media_preview\/(.*)$/)
	{
		print $FH "HTTP/1.0 200 OK\r\n";
		print $FH "Server: $CONFIG{'PROGRAM_NAME'} v$CONFIG{'PROGRAM_VERSION'} Webserver\r\n";
		print $FH "\r\n";
		preview_media($FH);
		print $FH "\r\n";
	}
	else
	{
		print $FH "HTTP/1.0 404 Not found\r\n";
		print $FH "Server: $CONFIG{'PROGRAM_NAME'} v$CONFIG{'PROGRAM_VERSION'} Webserver\r\n";
		print $FH "\r\n";
	}

	close($FH);
}

sub ctrl_content_directory_1
{
	my $FH = shift;
	my $xml = shift;
	my $action = shift;

	my $response = undef;

	PDLNA::Log::log('HTTP Connection SOAPACTION: '.$action, 2);
	if ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"')
	{
		PDLNA::Log::log('HTTP Connection ObjectID: '.$xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'}, 2);
		print STDERR Dumper $xml;
		if ($xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'} =~ /^(\w)_(\w)$/)
		{
			my $media_type = $1;
			my $sort_type = $2;

			$response .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
			$response .= '<s:Body>';
			$response .= '<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
			$response .= '<Result>';
			$response .= '&lt;DIDL-Lite xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&apos;urn:schemas-upnp-org:metadata-1-0/upnp/&apos; xmlns:dlna=&quot;urn:schemas-dlna-org:metadata-1-0/&quot; xmlns:sec=&quot;http://www.sec.co.kr/&quot;&gt;';
			my $content_type_obj = $content->get_content_type($media_type, $sort_type);
			foreach my $group (@{$content_type_obj->content_groups()})
			{
				my $group_id = $group->beautiful_id();
				my $group_name = $group->name();
				my $group_childs_amount = $group->content_items_amount();

				$response .= '&lt;container id=&quot;'.$media_type.'_'.$sort_type.'_'.$group_id.'&quot; parentId=&quot;'.$media_type.'_'.$sort_type.'&quot; childCount=&quot;'.$group_childs_amount.'&quot; restricted=&quot;1&quot;&gt;';
				$response .= '&lt;dc:title&gt;'.$group_name.'&lt;/dc:title&gt;';
				$response .= '&lt;upnp:class&gt;object.container&lt;/upnp:class&gt;';
				$response .= '&lt;/container&gt;';
			}
			$response .= '&lt;/DIDL-Lite&gt;';
			$response .= '</Result>';
			$response .= '<NumberReturned>'.$content_type_obj->content_groups_amount.'</NumberReturned>';
			$response .= '<TotalMatches>'.$content_type_obj->content_groups_amount.'</TotalMatches>',
			$response .= '<UpdateID>0</UpdateID>';
			$response .= '</u:BrowseResponse>';
			$response .= '</s:Body>';
			$response .= '</s:Envelope>';
		}
		elsif ($xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'} =~ /^(\w)_(\w)_(\d+)_(\d+)/)
		{
			my $media_type = $1;
			my $sort_type = $2;
			my $group_id = $3;
			my $item_id = $4;

			my $content_type_obj = $content->get_content_type($media_type, $sort_type);
			my $content_group_obj = $content_type_obj->content_groups()->[int($group_id)];
			my $foldername = $content_group_obj->name();
			my $content_item_obj = $content_group_obj->content_items()->[int($item_id)];
			my $name = $content_item_obj->name();
			my $date = $content_item_obj->date();
			my $beautiful_date = time2str("%Y-%m-%d", $date);
			my $size = $content_item_obj->size();

			my $item_name = $media_type.'_'.$sort_type.'_'.$group_id.'_'.$item_id;
			my $url = 'http://'.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'};

			$response .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
			$response .= '<s:Body>';
			$response .= '<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
			$response .= '<Result>&lt;DIDL-Lite xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&apos;urn:schemas-upnp-org:metadata-1-0/upnp/&apos; xmlns:dlna=&quot;urn:schemas-dlna-org:metadata-1-0/&quot; xmlns:sec=&quot;http://www.sec.co.kr/&quot;&gt;';
			$response .= '&lt;item id=&quot;'.$item_name.'&quot; parentId=&quot;'.$media_type.'_'.$sort_type.'_'.$group_id.'&quot; restricted=&quot;1&quot;&gt;&lt;dc:title&gt;'.$name.'&lt;/dc:title&gt;';
			$response .= '&lt;upnp:class&gt;object.item.videoItem&lt;/upnp:class&gt;'; # TODO adapt videoItem string
			$response .= '&lt;sec:dcmInfo&gt;CREATIONDATE='.$date.',FOLDER='.$foldername.'&lt;/sec:dcmInfo&gt;';
			# TODO a lot
			$response .= '&lt;dc:date&gt;'.$beautiful_date.'&lt;/dc:date&gt;';

			$response .= '&lt;res protocolInfo=&quot;http-get:*:video/x-avi:DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01500000000000000000000000000000&quot; size=&quot;'.$size.'&quot; duration=&quot;0:17:09&quot;&gt;'.$url.'/media/'.$item_name.'.AVI&lt;/res&gt;';
#			$response .= '&lt;res protocolInfo=&quot;http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_SM;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=00D00000000000000000000000000000&quot;&gt;'.$url.'/media_preview/'.$item_name.'.MTN&lt;/res&gt;';
#			$response .= '&lt;res protocolInfo=&quot;http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_TN;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=00D00000000000000000000000000000&quot;&gt;'.$url.'/media_preview/'.$item_name.'.TMTN&lt;/res&gt;';
			$response .= '&lt;/item&gt;';
			$response .= '&lt;/DIDL-Lite&gt;</Result><NumberReturned>1</NumberReturned><TotalMatches>1</TotalMatches><UpdateID>0</UpdateID></u:BrowseResponse></s:Body></s:Envelope>';
		}
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#X_GetObjectIDfromIndex"')
	{
		my $media_type = 'V' if $xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'CategoryType'} == 32;
		my $sort_type = 'F' if $xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'CategoryType'} == 32;
		my $index = $xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'Index'};

		my $content_type_obj = $content->get_content_type($media_type, $sort_type);
		my $i = 0;
		my @groups = @{$content_type_obj->content_groups()};
		while ($index >= $groups[$i]->content_items_amount())
		{
			$index -= $groups[$i]->content_items_amount();
			$i++;
		}
		my $content_item_obj = $groups[$i]->content_items()->[$index];

		$response .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response .= '<s:Body>';
		$response .= '<u:X_GetObjectIDfromIndexResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response .= '<ObjectID>'.$media_type.'_'.$sort_type.'_'.$groups[$i]->beautiful_id().'_'.$content_item_obj->beautiful_id().'</ObjectID>';
		$response .= '</u:X_GetObjectIDfromIndexResponse>';
		$response .= '</s:Body>';
		$response .= '</s:Envelope>';
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#X_GetIndexfromRID"')
	{
		$response .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response .= '<s:Body>';
		$response .= '<u:X_GetIndexfromRIDResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response .= '<Index>7</Index>';
		$response .= '</u:X_GetIndexfromRIDResponse>';
		$response .= '</s:Body>';
		$response .= '</s:Envelope>';
	}

	print STDERR $response."\n";
	print $FH $response;
}

sub server_description
{
	my $FH = shift;

	my $xml_response = XML::Simple->new();
	my $xml_serverdesc = {
		'xmlns' => 'urn:schemas-upnp-org:device-1-0',
		'specVersion' =>
		{
			'minor' => '5',
			'major' => '1'
		},
		'device' =>
		{
			'friendlyName' => $CONFIG{'FRIENDLY_NAME'},
			'modelName' => $CONFIG{'PROGRAM_NAME'},
			'modelDescription' => $CONFIG{'PROGRAM_DESC'},
			'dlna:X_DLNADOC' => 'DMS-1.50',
			'deviceType' => 'urn:schemas-upnp-org:device:MediaServer:1',
			'serialNumber' => $CONFIG{'PROGRAM_SERIAL'},
			'sec:ProductCap' => 'smi,DCM10,getMediaInfo.sec,getCaptionInfo.sec',
			'UDN' => $CONFIG{'UUID'},
			'manufacturerURL' => $CONFIG{'PROGRAM_WEBSITE'},
			'manufacturer' => $CONFIG{'PROGRAM_AUTHOR'},
			'sec:X_ProductCap' => 'smi,DCM10,getMediaInfo.sec,getCaptionInfo.sec',
			'modelURL' => $CONFIG{'PROGRAM_WEBSITE'},
			'serviceList' =>
			{
				'service' =>
				[
					{
						'serviceType' => 'urn:schemas-upnp-org:service:ContentDirectory:1',
						'controlURL' => '/upnp/control/ContentDirectory1',
						'eventSubURL' => '/upnp/event/ContentDirectory1',
						'SCPDURL' => 'ContentDirectory1.xml',
						'serviceId' => 'urn:upnp-org:serviceId:ContentDirectory'
					},
					{
						'serviceType' => 'urn:schemas-upnp-org:service:ConnectionManager:1',
						'controlURL' => '/upnp/control/ConnectionManager1',
						'eventSubURL' => '/upnp/event/ConnectionManager1',
						'SCPDURL' => 'ConnectionManager1.xml',
						'serviceId' => 'urn:upnp-org:serviceId:ConnectionManager'
					},
				],
			},
			'modelNumber' => '1.0',
		},
		'xmlns:dlna' => 'urn:schemas-dlna-org:device-1-0',
		'xmlns:sec' => 'http://www.sec.co.kr/dlna'
	};
	my $response = $xml_response->XMLout(
		$xml_serverdesc,
		RootName => 'root',
		XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>',
		ContentKey => '-content',
		ValueAttr => [ 'value' ],
		NoSort => 1,
		NoAttr => 1,
	);

	print $FH $response;
}

sub stream_media
{
	my $FH = shift;
	my $content_id = shift;

	if ($content_id =~ /^(\w)_(\w)_(\d+)_(\d+)/)
	{
		my $media_type = $1;
		my $sort_type = $2;
		my $group_id = $3;
		my $item_id = $4;

		my $content_type_obj = $content->get_content_type($media_type, $sort_type);
		my $content_group_obj = $content_type_obj->content_groups()->[int($group_id)];
		my $content_item_obj = $content_group_obj->content_items()->[int($item_id)];
		my $path = $content_item_obj->path();
		my $size = $content_item_obj->size();

		if (-f $path)
		{
			PDLNA::Log::log('Streaming '.$path.'.', 1);

			print $FH "HTTP/1.0 206 Partial Content\r\n";
			print $FH "Server: $CONFIG{'PROGRAM_NAME'} v$CONFIG{'PROGRAM_VERSION'} Webserver\r\n";
			print $FH "Content-Type: video/x-avi\r\n";
			print $FH "Content-Length: ".$size."\r\n";
			print $FH "Cache-Control: no-cache\r\n";
			print $FH "contentFeatures.dlna.org:DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01500000000000000000000000000000\r\n";
			my $small_size = $size-1;
			print $FH "Content-Range: bytes 0-".$small_size."/".$size."\r\n";
			print $FH "transferMode.dlna.org:Streaming\r\n";
			print $FH "MediaInfo.sec: SEC_Duration=1280360;\r\n";
			print $FH "\r\n";

			open(FILE, $path);
			print $FH <FILE>;
			close(FILE);
		}
		else
		{
			print $FH "HTTP/1.0 404 Not found\r\n";
			print $FH "Server: $CONFIG{'PROGRAM_NAME'} v$CONFIG{'PROGRAM_VERSION'} Webserver\r\n";
			print $FH "\r\n";
		}
	}
	else
	{
		print $FH "HTTP/1.0 404 Not found\r\n";
		print $FH "Server: $CONFIG{'PROGRAM_NAME'} v$CONFIG{'PROGRAM_VERSION'} Webserver\r\n";
		print $FH "\r\n";
	}
}

sub preview_media
{
	print STDERR "Preview Media\n";
}

1;
