##############################################################################
# $Id$
#
#     70_Telegram.pm
#
#     This file is part of Fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with Fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#	
#  Telegram (c) Johannes Viegener / https://github.com/viegener
#
# This module handles receiving and sending messages to the messaging service telegram (see https://telegram.org/)
# It works ONLY with a running telegram-cli (unofficial telegram cli client) --> see here https://github.com/vysheng/tg
# telegram-cli needs to be configured and running as daemon local on the fhem host
# ??? specify parameters
#
# Restriction: peer can be with or without spaces / spaces will be translated to _ (underline)
#
##############################################################################
# 0.0 2015-06-16 Started
#
#   Build structure for module
#   telegram-cli for operation
#   Basic DevIo handling
#   Attributes etc
#   Allow message sending to defaultpeer
#   basic telegram_read for only putting message into reading
# 0.1 2015-06-17 Initial Version
#   
#   General command handling analyzing results
#   _write function
#   handle initialization (client write / main session) in DoInit
#   allow host 
#   shutdown function added to send quit on connection
#   Telegram_read
#   handle readings
#   document cli command
#   document attr/set/get
#   documentation on limitations
# 0.2 2015-06-19 Running basic version with send and receive
#
#
##############################################################################
# TODO 
# - getmessage für get function
# - reopen connection command
# - is a ready function needed --> check REMAINING
# - reopen connection if needed
# - check state of connection
# - handle Attr: lastMsgId
# - read all unread messages from default peer on init
#
##############################################################################
# Ideas / Future
# - support unix socket also instead of port only
# - if ever incomplete messages are received this needs to be incorporated into the return value handling
# - allow multi parameter set for set <device> <peer> 
# - start local telegram-cli as subprocess
# - allow registration and configuration from module
# - handled online / offline messages
# - support presence messages
#
##############################################################################
#	
# define <name> Telegram  [<hostname>:]<port> 
#	
# Attr / Internal / Reading
#   - Attr: lastMsgId
#   - Attr: defaultPeer
#   - Internal: sentMsgText
#   - Internal: sentMsgResult
#   - Internal: sentMsgPeer
#   - Internal: sentMsgId????
#   - Internal: REMAINING - used for storing messages received intermediate
#   - Reading: msgText
#   - Reading: msgPeer
#   - Reading: msgId
#   - Reading: prevMsgText
#   - Reading: prevMsgPeer
#   - Reading: prevMsgId
# 
##############################################################################
#
# bin/telegram-cli -k tg-server.pub -W -C -d -P 12345 --accept-any-tcp -L test.log -l 20 -N &
#
#
# main_session
#ANSWER 65
#User First Last online (was online [2015/06/18 23:53:53])
#
#ANSWER 41
#55 [23:49]  First Last >>> test 5
#
#ANSWER 66
#User First Last offline (was online [2015/06/18 23:49:08])
#
#mark_read First_Last
#ANSWER 8
#SUCCESS
#



package main;

use strict;
use warnings;
use DevIo;

use Scalar::Util qw(reftype looks_like_number);

#########################
# Forward declaration
sub Telegram_Define($$);
sub Telegram_Undef($$);

sub Telegram_Set($@);
sub Telegram_Get($@);

sub Telegram_Read($);
sub Telegram_Write($$);
sub Telegram_Parse($$$);


#########################
# Globals
my %sets = (
	"msg" => "textField"
);

my %gets = (
	"msg" => "textField"
);




#####################################
# Initialize is called from fhem.pl after loading the module
#  define functions and attributed for the module and corresponding devices

sub Telegram_Initialize($) {
	my ($hash) = @_;

	require "$attr{global}{modpath}/FHEM/DevIo.pm";

	$hash->{ReadFn}     = "Telegram_Read";
	$hash->{WriteFn}    = "Telegram_Write";
#	$hash->{ReadyFn}    = "Telegram_Ready";

	$hash->{DefFn}      = "Telegram_Define";
	$hash->{UndefFn}    = "Telegram_Undef";
	$hash->{GetFn}      = "Telegram_Get";
	$hash->{SetFn}      = "Telegram_Set";
  $hash->{ShutdownFn} = "Telegram_Shutdown"; 
	$hash->{AttrFn}     = "Telegram_Attr";
	$hash->{AttrList}   = "lastMsgId defaultPeer ".
						$readingFnAttributes;
	
}


######################################
#  Define function is called for actually defining a device of the corresponding module
#  For telegram this is mainly the name and information about the connection to the telegram-cli client
#  data will be stored in the hash of the device as internals
#  
sub Telegram_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  my $name = $hash->{NAME};

  Log3 $name, 5, "Telegram_Define $name: called ";

  my $errmsg = '';
  
  # Check parameter(s)
  if( int(@a) != 3 ) {
    $errmsg = "syntax error: define <name> Telegram <port> ";
    Log3 $name, 3, "Telegram $name: " . $errmsg;
    return $errmsg;
  }
  
  if ( $a[2] =~ /^([[:alnum:]][[:alnum:]-]*):[[:digit:]]+$/ ) {
    $hash->{DeviceName} = $a[2];
  } elsif ( $a[2] =~ /:/ ) {
    $errmsg = "specify valid hostname and numeric port: define <name> Telegram  [<hostname>:]<port> ";
    Log3 $name, 3, "Telegram $name: " . $errmsg;
    return $errmsg;
  } elsif (! looks_like_number($a[2])) {
    $errmsg = "port needs to be numeric: define <name> Telegram  [<hostname>:]<port> ";
    Log3 $name, 3, "Telegram $name: " . $errmsg;
    return $errmsg;
  } else {
    $hash->{DeviceName} = "localhost:$a[2]";
  }
  
  $hash->{TYPE} = "Telegram";

  $hash->{Port} = $a[2];
  $hash->{Protocol} = "telnet";

  # close old dev
  Log3 $name, 5, "Telegram_Define $name: handle DevIO ";
  DevIo_CloseDev($hash);

  my $ret = DevIo_OpenDev($hash, 0, "Telegram_DoInit");

  ### initialize timer for connectioncheck
  #$hash->{helper}{nextConnectionCheck} = gettimeofday()+120;

  Log3 $name, 5, "Telegram_Define $name: done with ".(defined($ret)?$ret:"undef");
  return $ret; 
}

#####################################
#  Undef function is corresponding to the delete command the opposite to the define function 
#  Cleanup the device specifically for external ressources like connections, open files, 
#		external memory outside of hash, sub processes and timers
sub Telegram_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "Telegram_Undef $name: called ";

  RemoveInternalTimer($hash);
  # deleting port for clients
  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
		defined($defs{$d}{IODev}) &&
		$defs{$d}{IODev} == $hash) {
      Log3 $hash, 3, "Telegram $name: deleting port for $d";
      delete $defs{$d}{IODev};
    }
  }
  Log3 $name, 5, "Telegram_Undef $name: close devio ";
  
  DevIo_CloseDev($hash);

  Log3 $name, 5, "Telegram_Undef $name: done ";
  return undef;
}

####################################
# set function for executing set operations on device
sub Telegram_Set($@)
{
	my ( $hash, $name, @args ) = @_;
	
  Log3 $name, 5, "Telegram_Set $name: called ";

	### Check Args
	my $numberOfArgs  = int(@args);
	return "Telegram_Set: No value specified for set" if ( $numberOfArgs < 1 );

	my $cmd = lc(shift @args);
  my $arg = join(" ", @args );
  if ( $numberOfArgs < 2 ) {
    $arg = "";
  }

  Log3 $name, 5, "Telegram_Set $name: Processing Telegram_Set( $cmd )";

	if(!exists($sets{$cmd})) {
		my @cList;
		foreach my $k (sort keys %sets) {
			my $opts = undef;
			$opts = $sets{$k};

			if (defined($opts)) {
				push(@cList,$k . ':' . $opts);
			} else {
				push (@cList,$k);
			}
		} # end foreach

		return "Telegram_Set: Unknown argument $cmd, choose one of " . join(" ", @cList);
	} # error unknown cmd handling

  my $ret = undef;
  
	if($cmd eq 'msg') {
    if ( $numberOfArgs < 2 ) {
      return "Telegram_Set: Command $cmd, no text specified";
    }
    my $peer = AttrVal($name,'defaultPeer',undef);
    if ( ! defined($peer) ) {
      return "Telegram_Set: Command $cmd, requires defaultPeer being set";
    }
    # should return undef if succesful
    Log3 $name, 5, "Telegram_Set $name: start message send ";
    $ret = Telegram_SendMessage( $hash, $peer, $arg );

    $hash->{sentMsgText} = $arg;
    $hash->{sentMsgPeer} = $peer;
    if ( defined($ret) ) {
      $hash->{sentMsgResult} = $ret;
    } else {
      $hash->{sentMsgResult} = "SUCCESS";
    }
  }
  
  Log3 $name, 5, "Telegram_Set $name: done with $hash->{sentMsgResult}: ";
  return $ret
}

#####################################
# get function for gaining information from device
sub Telegram_Get($@)
{
	my ( $hash, $name, @args ) = @_;
	
  Log3 $name, 5, "Telegram_Get $name: called ";

	### Check Args
	my $numberOfArgs  = int(@args);
	return "Telegram_Get: No value specified for get" if ( $numberOfArgs < 1 );

	my $cmd = lc($args[0]);
  my $arg = ($args[1] ? $args[1] : "");

  Log3 $name, 5, "Telegram_Get $name: Processing Telegram_Get( $cmd )";

	if(!exists($gets{$cmd})) {
		my @cList;
		foreach my $k (sort keys %gets) {
			my $opts = undef;
			$opts = $sets{$k};

			if (defined($opts)) {
				push(@cList,$k . ':' . $opts);
			} else {
				push (@cList,$k);
			}
		} # end foreach

		return "Telegram_Get: Unknown argument $cmd, choose one of " . join(" ", @cList);
	} # error unknown cmd handling

  
  my $ret = undef;
  
	if($cmd eq 'msg') {
    if ( $numberOfArgs != 2 ) {
      return "Telegram_Set: Command $cmd, no msg id specified";
    }
    Log3 $name, 5, "Telegram_Get $name: get message for id $arg";

    # should return undef if succesful
   $ret = Telegram_GetMessage( $hash, $arg );
  }
  
  Log3 $name, 5, "Telegram_Get $name: done with $ret: ";

  return $ret
}

##############################
# attr function for setting fhem attributes for the device
sub Telegram_Attr(@) {
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};

  Log3 $name, 5, "Telegram_Attr $name: called ";

	return "\"Telegram_Attr: \" $name does not exist" if (!defined($hash));

  Log3 $name, 5, "Telegram_Attr $name: $cmd  on $aName to $aVal";
  
	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value
	if ($cmd eq "set") {
		if($aName eq 'lastMsgId') {
			return "Telegram_Attr: value must be >=0 " if( $aVal < 0 );
		}

		if ($aName eq 'lastMsgId') {
			$attr{$name}{'lastMsgId'} = $aVal;

		} elsif ($aName eq 'defaultPeer') {
			$attr{$name}{'defaultPeer'} = $aVal;

    }
	}

	return undef;
}

######################################
#  Shutdown function is called on shutdown of server and will issue a quite to the cli 
sub Telegram_Shutdown($) {

	my ( $hash ) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "Telegram_Attr $name: called ";

  # First needs send an empty line and read all returns away
  my $buf = Telegram_DoCommand( $hash, '', undef );

  # send a quit but ignore return value
  $buf = Telegram_DoCommand( $hash, '', undef );
  Log3 $name, 5, "Telegram_Shutdown $name: Done quit with return :$buf: ";
  
  return undef;
}

  
#####################################
# _Read is called when data is available on the corresponding file descriptor 
# data to be read must be collected in hash until the data is complete
# Parse only one message at a time to be able that readingsupdates will be sent out
# to be deleted
#ANSWER 65
#User First Last online (was online [2015/06/18 23:53:53])
#
#ANSWER 41
#55 [23:49]  First Last >>> test 5
#
#ANSWER 66
#User First Last offline (was online [2015/06/18 23:49:08])
#
#mark_read First_Last
#ANSWER 8
#SUCCESS
#
sub Telegram_Read($) 
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "Telegram_Read $name: called ";

  # Read new data
	my $buf = DevIo_SimpleRead($hash);
  if ( $buf ) {
    Log3 $name, 5, "Telegram_Read $name: New read :$buf: ";
  }
  
  # append remaining content to buf
  $hash->{REMAINING} = '' if( ! defined($hash->{REMAINING}) );
  $buf = $hash->{REMAINING}.$buf;

  Log3 $name, 5, "Telegram_Read $name: Full buffer :$buf: ";

  # remove all inconsistent parts until a message with ANSWER starts
  my $msg = '';
#  Log3 $name, 5, "Telegram_Read $name: matches :$2:" if ( $buf =~ /^ANSWER\s(\d+)\n(.*)/s ) ;
  while ( (length( $buf )>0) && ( $buf !~ /^ANSWER\s(\d+)\n(.*)$/s ) ) {
    if ( $buf =~ /^[^\n]*\n(.*)$/s) {
      $buf = $1;
    } else {
      $buf = '';
    }
    Log3 $name, 5, "Telegram_Read $name: Strip buffer to :$buf:";
  }

  # Split the message from the rest based on length of the Answer tag
  if (length( $buf )>0) {
    my $count = $1;
    $buf = $2;
    
    Log3 $name, 5, "Telegram_Read $name: found something in buffer with length $count";
    if ( length($buf) > $count ) {
      $msg = substr $buf, 0, $count;  
      $buf = substr $buf, $count;
    }
  }

  # Do we have a message found
  if (length( $msg )>0) {
    Log3 $name, 5, "Telegram_Read $name: message in buffer :$msg:";
    readingsBeginUpdate($hash);

    readingsBulkUpdate($hash, "lastmessage", $msg);				

    #55 [23:49]  First Last >>> test 5
    # Ignore all none received messages
    if ( $msg =~ /^(\d+)\s\[[^\]]+\]\s+([^\s][^>]*)\s>>>\s(.*)\n$/s  ) {
      my $mid = $1;
      my $mpeer = $2;
      my $mtext = $3;
 
      readingsBulkUpdate($hash, "prevMsgId", $hash->{READINGS}{msgId}{VAL});				
      readingsBulkUpdate($hash, "prevMsgPeer", $hash->{READINGS}{mpeer}{VAL});				
      readingsBulkUpdate($hash, "prevMsgText", $hash->{READINGS}{mtext}{VAL});				

      readingsBulkUpdate($hash, "msgId", $mid);				
      readingsBulkUpdate($hash, "msgPeer", $mpeer);				
      readingsBulkUpdate($hash, "msgText", $mtext);				
    }

    readingsEndUpdate($hash, 1);
  }

  # store remaining message
  $hash->{REMAINING} =  $buf;
  
  
}

#####################################
# Initialize a connection to the telegram-cli
# requires to ensure commands are accepted / set this as main_session, get last msg id 
sub Telegram_Write($$) {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "Telegram_Write $name: called ";

  return Telegram_DoCommand( $hash, $msg, undef );  

} 




##############################################################################
##############################################################################
##
## HELPER
##
##############################################################################
##############################################################################

#####################################
# Initialize a connection to the telegram-cli
# requires to ensure commands are accepted / set this as main_session, get last msg id 
sub Telegram_DoInit($)
{
	my ( $hash ) = @_;
  my $name = $hash->{NAME};

	my $buf = '';
	
  Log3 $name, 5, "Telegram_DoInit $name: called ";

  # First needs send an empty line and read all returns away
  $buf = Telegram_DoCommand( $hash, '', undef );
  Log3 $name, 5, "Telegram_DoInit $name: Inital response is :".(defined($buf)?$buf:"undef").": ";

  # Send "main_session" ==> returns empty
  $buf = Telegram_DoCommand( $hash, 'main_session', undef );
  Log3 $name, 5, "Telegram_DoInit $name: Response on main_session is :".(defined($buf)?$buf:"undef").": ";
  return "DoInit failed on main_session with return :".(defined($buf)?$buf:"undef").":" if ( defined($buf) && ( length($buf) > 0 ));
  
  # Send "help" ==> returns empty
  $buf = Telegram_DoCommand( $hash, 'main_session', undef );
  Log3 $name, 5, "Telegram_DoInit $name: Response on main_session is :".(defined($buf)?$buf:"undef").": ";
  return "DoInit failed on main_session with return :".(defined($buf)?$buf:"undef").":" if ( defined($buf) && ( length($buf) > 0 ));
  
  #	- handle initialization (client write / main session / read msg id and checks) in DoInit
  $hash->{STATE} = "Initialized" if(!$hash->{STATE});

  # ??? last message id and read all missing messages for default peer
  
  $hash->{STATE} = "Ready" if(!$hash->{STATE});
  
  return undef;
}

#####################################
# INTERNAL: Function to send a message to a peer and handle result
sub Telegram_SendMessage($$$)
{
	my ( $hash, $peer, $msg ) = @_;
  my $name = $hash->{NAME};
	
  Log3 $name, 5, "Telegram_SendMessage $name: called ";

  # trim and convert spaces in peer to underline 
  my $peer2 = $peer;
     $peer2 =~ s/^\s+|\s+$//g;
     $peer2 =~ s/ /_/g;
    
  my $cmd = "msg $peer2 $msg";
  
  return Telegram_DoCommand( $hash, $cmd, "SUCCESS" );
}


#####################################
# INTERNAL: Function to send a command handle result
# Parameter
#   hash
#   cmd - command line to be executed
#   expect - expect response - undef : no check / <string> expect string after answer <n> for checking ok: 
#   >>> returns : COMPLETE response on expect = undef / undef = string matched / response after answer <n> string else
sub Telegram_DoCommand($$$)
{
	my ( $hash, $cmd, $expect ) = @_;
  my $name = $hash->{NAME};
	my $buf = '';
  
  Log3 $name, 5, "Telegram_DoCommand $name: called ";

  Log3 $name, 5, "Telegram_DoCommand $name: send command :$cmd: ";
  
  # Check for message in outstanding data from device
  $hash->{REMAINING} = '' if( ! defined($hash->{REMAINING}) );

  $buf = DevIo_SimpleReadWithTimeout($hash, 0.01);
  if ( $buf ) {
    Log3 $name, 5, "Telegram_DoCommand $name: Remaining read :$buf: ";
    $hash->{REMAINING} = $hash->{REMAINING}.$buf;
  }
  
  # Now write the message
  DevIo_SimpleWrite($hash, $cmd."\n", 0);

  Log3 $name, 5, "Telegram_DoCommand $name: send command DONE ";

  $buf = DevIo_SimpleReadWithTimeout($hash, 0.1);
  Log3 $name, 5, "Telegram_DoCommand $name: returned :".(defined($buf)?$buf:"undef").": ";
  
  if ( defined( $expect ) ) {
    ### check for correct response
    # match for ANSWER <n>\n<real response>
    if ( $buf =~ /^ANSWER\s(\d+)\n(.*)\n$/s ) {
      # OK I got an answer
      my $count = $1;
      my $buf = $2;
      
      return $buf if ( length($buf) != ($count-1) );
      
      return undef if ( $buf =~ /^$expect/ );
      
    }
  }
  
  return $buf;
}


##############################################################################
##############################################################################
##
## Documentation
##
##############################################################################
##############################################################################

1;

=pod
=begin html

<a name="Telegram"></a>
<h3>Telegram</h3>
<ul>
  The Telegram module allows the usage of the instant messaging service <a href="https://telegram.org/">Telegram</a> from FHEM in both directions (sending and receiving). 
  So FHEM can use telegram for notifications of states or alerts, general informations and actions can be triggered.
  <br>
  <br>
  Precondition is the installation of the telegram-cli (for unix) see here <a href="https://github.com/vysheng/tg">https://github.com/vysheng/tg</a>
  telegram-cli needs to be configured and registered for usage with telegram. Best is the usage of a dedicated phone number for telegram, 
  so that messages can be sent to and from a dedicated account and read status of messages can be managed. 
  telegram-cli needs to run as a daemon listening on a tcp port to enable communication with FHEM. 
  <br><br>
  <code>
    telegram-cli -k <path to key file e.g. tg-server.pub> -W -C -d -P <portnumber> [--accept-any-tcp] -L <logfile> -l 20 -N &
  </code>
  <br><br>
  <dl> 
    <dt>keyfile</dt>
    <dd>Path to the keyfile for telegram-cli, usually something like <code>tg-server.pub</code></dd>
    <dt>portnumber</dt>
    <dd>Port number on which the daemon should be listening e.g. 12345</dd>
    <dt>--accept-any-tcp</dt>
    <dd>Allows the access to the daemon also from distant machines. This is only needed of the telegram-cli is not running on the same host than fhem.
      <br>
      ATTENTION: There is normally NO additional security requirement to access telegram-cli, so use this with care!</dd>
    <dt>logfile</dt>
    <dd>Specify the path to the logfile for telegram-cli. This is especially helpful for debugging purposes and 
      used in conjunction with the specifed log level (<code>-l 20</code>)</dd>
  </dl>
  <br><br>
  More details to the command line parameters of telegram-cli can be found here: <a href="https://github.com/vysheng/tg/wiki/Telegram-CLI-Arguments>Telegram CLI Arguments</a>
  <br><br>
  In my environment, I could not run telegram-cli as part of normal raspbian startup as a daemon as described here:
   <a href="https://github.com/vysheng/tg/wiki/Running-Telegram-CLI-as-Daemon">Running Telegram CLI as Daemon</a> but rather start it currently manually as a background daemon process.
  <code>
    telegram-cli -k tg-server.pub -W -C -d -P 12345 --accept-any-tcp -L test.log -l 20 -N &
  </code>
  <br><br>
  The Telegram module allows receiving of (text) messages to any peer (telegram user) and sends text messages to the default peer specified as attribute.
  <br>
  <br><br>
  <a name="Telegramlimitations"></a>
  <br>
  <b>Limitations and possible extensions</b>
  <ul>
    <li>Message id handling is currently not yet implemented<br>This specifically means that messages received 
    during downtime of telegram-cli and / or fhem are not handled when fhem and telegram-cli are getting online again.</li> 
    <li>Running telegram-cli as a daemon with unix sockets is currently not supported</li> 
    <li>Get function for message not yet implemented</li> 
    <li>Connection state is not handled</li> 
    <li>Ready function not implemented to handled remaining messages that need to be handled in the read function</li> 
    <li>... and a lot more</li> 
  </ul>

  <br><br>
  <a name="Telegramdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Telegram  [&lt;hostname&gt;:]&lt;port&gt; </code><br><br>
    <br><br>

    Defines a Telegram device either running locally on the fhem server host by specifying only a port number or remotely on a different host by specifying host and portnumber separated by a colon.
    
    Examples:
    <ul>
      <code>define user1 Telegram 12345</code><br>
      <code>define admin Telegram myserver:22222</code><br>
    </ul>
    <br>
  </ul>
  <br><br>

  <a name="Telegramset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;what&gt; [&lt;value&gt;]</code>
    <br><br>
    where &lt;what&gt; is one of
    <br><br>
    <li>msg &lt;text&gt;<br>Sends the given message to the currently defined default peer user</li>
  </ul>
  <br><br>

  <a name="Telegramget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;what&gt; [&lt;value&gt;]</code>
    <br><br>
    where &lt;what&gt; is one of
    <br><br>
    <li>msg &lt;message id&gt;<br>Retrieves the message identifed by the corresponding message id</li>
  </ul>
  <br><br>

  <a name="Telegramattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li>defaultPeer &lt;name&gt;<br>Specify first name last name of the default peer to be used for sending messages</li> 
    <li>lastMsgId &lt;number&gt;<br>Specify the last message handled by Telegram.<br>NOTE: Not yet handled</li> 
    <li><a href="#verbose">verbose</a></li>
  </ul>
  <br><br>
  
  <a name="Telegramreadings"></a>
  <b>Readings</b>
  <br><br>
  <ul>
    <li>msgId &lt;text&gt;<br>The id of the last received message is stored in this reading.</li> 
    <li>msgPeer &lt;text&gt;<br>The sender of the last received message.</li> 
    <li>msgText &lt;text&gt;<br>The last received message text is stored in this reading.</li> 
    <li>prevMsgId &lt;text&gt;<br>The id of the SECOND last received message is stored in this reading.</li> 
    <li>prevMsgPeer &lt;text&gt;<br>The sender of the SECOND last received message.</li> 
    <li>prevMsgText &lt;text&gt;<br>The SECOND last received message text is stored in this reading.</li> 
  </ul>
  <br><br>
  
</ul>

=end html
=cut