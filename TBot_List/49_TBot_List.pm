##############################################################################
##############################################################################
#
#     49_TBot_List.pm
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
#  TBot_List (c) Johannes Viegener / https://github.com/viegener/Telegram-fhem/tree/master/TBot_List
#
# This module interacts with TelegramBot and PostMe devices
#
# Discussed in FHEM Forum: <not yet> TODO
#
# $Id:  $
#
##############################################################################
# 0.0 2017-01-15 Started
#   add get normpeer getter to tbot
#   get data from tbot in set / get
#   setup needs to specfiy notifies
#   implement attr
#   handle reply msg
#   change key building to routine
#   change all handler calls to new parameters
#   use name in queryData
#   change key from lname to tbot
#   lname handling
#   TBot_List_handler invocations to be modified
#   check in get queryanswer if list is amtching current device
#   add handler from myutils
#   add notify function
#   change ensure cmd with name is handled correctly
#   modify tbot to call handler with querydcata -- get routine - returns undef=nothandled 0=emptyanswerbuthandled other=answer
# 0.1 2017-01-17 Initial Version - mostly tested

#   Documentation
#   changed log levels
#   
#   
##############################################################################
# TASKS 
#   
#   
#   Further testing of all multi liste
#   
#   internal value if waiting for msg or reply -- otherwise notify not looping through events
#   
#   add entry for messages sent accidentially - absed on dialog
#   
#   Further testing of end
#   
#   TODOs
#
#   setters - start list / add new entry with question
##############################################################################
# Ideas
#   
#
##############################################################################


package main;

use strict;
use warnings;

use URI::Escape;

use Scalar::Util qw(reftype looks_like_number);

#########################
# Forward declaration
sub TBot_List_Define($$);
sub TBot_List_Undef($$);

sub TBot_List_Set($@);
sub TBot_List_Get($@);

sub TBot_List_ReplacePattern( $$;$ );

sub TBot_List_handler( $$$$;$ );

#########################
# Globals


##############################################################################
##############################################################################
##
## Module operation
##
##############################################################################
##############################################################################

#####################################
# Initialize is called from fhem.pl after loading the module
#  define functions and attributed for the module and corresponding devices

sub TBot_List_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}      = "TBot_List_Define";
  $hash->{UndefFn}    = "TBot_List_Undef";
  $hash->{GetFn}      = "TBot_List_Get";
  $hash->{SetFn}      = "TBot_List_Set";
  $hash->{AttrFn}     = "TBot_List_Attr";
  $hash->{NotifyFn}     = "TBot_List_Notify";
  $hash->{AttrList}   = 
          "telegramBots:textField ".
          "optionDouble:0,1 ".
          "allowedPeers:textfield ".
          $readingFnAttributes;           
}


######################################
#  Define function is called for actually defining a device of the corresponding module
#   this includes name of the PosteMe device and the listname
#  
sub TBot_List_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  my $name = $hash->{NAME};

  Log3 $name, 3, "TBot_List_Define $name: called ";

  my $errmsg = '';
  
  my $definemsg = "define <name> TBot_List <postmedevice> <listname>";
  
  # Check parameter(s)
  if( int(@a) != 4 ) {
    $errmsg = "syntax error: $definemsg";
    Log3 $name, 1, "TBot_List $name: " . $errmsg;
    return $errmsg;
  }

  my $postme = $a[2];
  if ( ( defined( $defs{$postme} ) ) && ( $defs{$postme}{TYPE} eq "PostMe" ) ) {
    $hash->{postme} = $postme;
  } else {
    $errmsg = "specify valid PostMe device in $definemsg ";
    Log3 $name, 1, "TBot_List $name: " . $errmsg;
    return $errmsg;
  }
  
  $hash->{listname} = $a[3];
  
  $hash->{TYPE} = "TBot_List";

  $hash->{STATE} = "Undefined";

  TBot_List_Setup( $hash );

  return; 
}

#####################################
#  Undef function is corresponding to the delete command the opposite to the define function 
#  Cleanup the device specifically for external ressources like connections, open files, 
#    external memory outside of hash, sub processes and timers
sub TBot_List_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 3, "TBot_List_Undef $name: called ";

  Log3 $name, 4, "TBot_List_Undef $name: done ";
  return undef;
}

##############################################################################
##############################################################################
##
## Instance operational methods
##
##############################################################################
##############################################################################


####################################
# set function for executing set operations on device
sub TBot_List_Set($@)
{
  my ( $hash, $name, @args ) = @_;
  
  Log3 $name, 5, "TBot_List_Set $name: called ";

  ### Check Args
  my $numberOfArgs  = int(@args);
  return "TBot_List_Set: No cmd specified for set" if ( $numberOfArgs < 1 );

  my $cmd = shift @args;

  my $addArg = ($args[0] ? join(" ", @args ) : undef);

  Log3 $name, 4, "TBot_List_Set $name: Processing TBot_List_Set( $cmd ) - args :".(defined($addArg)?$addArg:"<undef>").":";

  # check cmd / handle ?
  my $ret = TBot_List_CheckSetGet( $hash, $cmd, $hash->{setoptions} );

  if ( $ret ) {

    # do nothing if error/ret is defined

  } elsif ($cmd eq 'start')  {
    Log3 $name, 4, "TBot_List_Set $name: start of dialog requested ";
    $ret = "start requires a telegrambot and optionally a peer" if ( ( $numberOfArgs < 2 ) && ( $numberOfArgs > 3 ) );
    
    my $tbot;
    my $tpeer;
    if ( ! $ret ) {
      $tbot = $args[0];
      $ret = "No telegramBot specified :$tbot:" if ( ! TBot_List_isTBot( $hash, $tbot ) );
    }  

    if ( ! $ret ) {
      $ret = "TelegramBot specified :$tbot: is not monitored" if ( ! TBot_List_hasConfigTBot( $hash, $tbot ) );
    }
    
    if ( ! $ret ) {
      if ( $numberOfArgs == 2 ) {
        $tpeer = ReadingsVal( $tbot, "msgPeerId", "" );
      } else {
        $tpeer = fhem( "get $tbot peerId ".$args[1] );
      }
      $ret = "No peer found or specified :$tbot: ".(( $numberOfArgs == 2 )?"":$args[1]) if ( ! $tpeer );
    }  

    if ( ! $ret ) {
      # listno will be calculated at start of new dialog
      my $pcnt = ReadingsNum($hash->{postme},"postmeCnt",0);
      my $curr = 0;
      my $listNo;
#      Debug "pcnt : ".$pcnt;
  
      while ( $curr < $pcnt ) {
        $curr++;
        my $rd = "postme".sprintf("%2.2d",$curr)."Name";
#        Debug "rd : ".$rd;
        if ( ReadingsVal($hash->{postme},$rd,"") eq $hash->{listname} ) {
          $listNo = $curr;
          last;
        }
      }

      if ( ! $listNo ) {
        $ret = "specify valid list for PostMe device ".$hash->{postme}." in $name :".$hash->{listname}.":";
        Log3 $name, 1, "TBot_List $name: " . $ret;
      }
    
      $hash->{listno} = $listNo;
    }
    
    Log3 $name, 1, "TBot_List_Set $name: Error :".$ret if ( $ret );
    
    # start uses a botname and an optional peer
    $ret = TBot_List_handler( $hash, "list", $tbot, $tpeer ) if ( ! $ret );

  } elsif($cmd eq 'end') {
    Log3 $name, 4, "TBot_List_Set $name: end of dialog requested ";
    $ret = "end requires a telegrambot and optionally a peer" if ( $numberOfArgs != 3 );
    
    my $tbot;
    my $tpeer;
    if ( ! $ret ) {
      $tbot = $args[0];
      $ret = "No telegramBot specified :$tbot:" if ( ! TBot_List_isTBot( $hash, $tbot ) );
    }  
    
    if ( ! $ret ) {
      $tpeer = fhem( "get $tbot peerId ".$args[1] );
      $ret = "No peer found or specified :$tbot: ".$args[1] if ( ! $tpeer );
    }  
  
    # start uses a botname and an optional peer
    $ret = TBot_List_handler( $hash, "end", $tbot, $tpeer ) if ( ! $ret );
  }

  Log3 $name, 4, "TBot_List_Set $name: $cmd ".((defined( $ret ))?"failed with :$ret: ":"done succesful ");
  return $ret
}

#####################################
# get function for gaining information from device
sub TBot_List_Get($@)
{
  my ( $hash, $name, @args ) = @_;
  
  Log3 $name, 5, "TBot_List_Get $name: called ";

  ### Check Args
  my $numberOfArgs  = int(@args);
  return "TBot_List_Get: No value specified for get" if ( $numberOfArgs < 1 );

  my $cmd = $args[0];
  my $arg = $args[1];

  Log3 $name, 5, "TBot_List_Get $name: Processing TBot_List_Get( $cmd )";

  # check cmd / handle ?
  my $ret = TBot_List_CheckSetGet( $hash, $cmd, $hash->{getoptions} );

  if ( $ret ) {
    # do nothing if error/ret is defined

  } elsif($cmd eq 'queryAnswer') {
    # parameters cmd - queryAnswer <tbot> <peer> <querydata> 
    if ( $numberOfArgs != 4 ) {
      $ret = "queryAnswer requires a telegrambot peer and querydata to be specified";
    } else {
      Log3 $name, 4, "TBot_List_Get $name: queryAnswer requested tbot:".$args[1].":   peer:".$args[2].":   qdata:".$args[3].":";
    }
    
    my $tbot;
    my $tpeer;
    my $qdata = $args[3];
    
    if ( $qdata =~ s/^(.*)%(.*)$/$2/ ) {
      my $qname = $1;

      if ( $qname eq $name ) {
        # handle this only if name in query data is me

        if ( ! $ret ) {
          $tbot = $args[1];
          $ret = "No telegramBot specified :$tbot:" if ( ! TBot_List_isTBot( $hash, $tbot ) );
        }
        if ( ! $ret ) {
          $tpeer = fhem( "get $tbot peerId ".$args[2] );
          $ret = "No peer specified :$tbot: ".$args[2] if ( ! $tpeer );
        }
        
        # end uses a botname and a peer
        $ret = TBot_List_handler( $hash, $qdata, $tbot, $tpeer ) if ( ! $ret );
      }
      
    } else {
      # $ret = "query data does not contain a name and cmd separated with \% :$qdata: ".$args[1];
      # no return if qdata not in corresponding form
    }

  }
  
  Log3 $name, 4, "TBot_List_Get $name: $cmd ".(($ret)?"failed with :$ret: ":"done succesful ");

  return $ret
}

##############################
# attr function for setting fhem attributes for the device
sub TBot_List_Attr(@) {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};

  Log3 $name, 5, "TBot_List_Attr $name: called ";

  return "\"TBot_List_Attr: \" $name does not exist" if (!defined($hash));

  if (defined($aVal)) {
    Log3 $name, 5, "TBot_List_Attr $name: $cmd  on $aName to $aVal";
  } else {
    Log3 $name, 5, "TBot_List_Attr $name: $cmd  on $aName to <undef>";
  }
  # $cmd can be "del" or "set"
  # $name is device name
  # aName and aVal are Attribute name and value
  if ($cmd eq "set") {

    if ( ($aName eq 'optionDouble') ) {
      $aVal = ($aVal eq "1")? "1": "0";

    } elsif ($aName eq 'allowedPeers') {
      return "\"TBot_List_Attr: \" $aName needs to be given in digits - and space only" if ( $aVal !~ /^[[:digit: -]]$/ );

    }

    $_[3] = $aVal;
  
  }

  return undef;
}
  
#####################################
#  notify function provide dev and 
# is corresponding to the delete command the opposite to the define function 
sub TBot_List_Notify($$)
{
  my ($hash,$dev) = @_;
  
  return undef if(!defined($hash) or !defined($dev));

  my $name = $hash->{NAME};
  my $events;

  my $devname = $dev->{NAME};
  
#  Debug "notify  name:".$name.":   - dev : ".$devname;
  if ( TBot_List_hasConfigTBot( $hash, $devname ) ) {
    # yes it is monitored 
    
    # grab events if not yet defined
    $events = deviceEvents($dev,0);
    
    TBot_List_handleEvents( $hash, $devname, $events );
  }

}


  
  
##############################################################################
##############################################################################
##
## Helper list handling
##
##############################################################################
##############################################################################

##############################################
# get the different config values
#
sub TBot_List_getConfigListname($)
{
  my ($hash) = @_;
  return $hash->{listname};
}
  
sub TBot_List_getConfigListno($)
{
  my ($hash) = @_;
  return $hash->{listno};
}
  
sub TBot_List_getConfigPostMe($)
{
  my ($hash) = @_;
  return $hash->{postme};
}
sub TBot_List_isAllowed($$)
{
  my ($hash, $peer) = @_;
  my $name = $hash->{NAME};
  
  my $peers = AttrVal($name,'allowedPeers',undef);
  
  return 1 if ( ! $peers );

  $peers = " ".$peers." ";
  return ( $peers =~ / $peer / );
}

sub TBot_List_hasOptionDouble($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  return ( AttrVal($name,'optionDouble',0) ? 1:0 );
}

sub TBot_List_hasConfigTBot($$)
{
  my ($hash, $tbot) = @_;
  my $name = $hash->{NAME};
  
  my $bots = AttrVal($name,'telegramBots',undef);
  return 0 if ( ! $bots );

  $bots = " ".$bots." ";
#  Debug "Bots  :".$bots.":  tbot :".$tbot.":";
  
  return ( $bots =~ / $tbot / );
}



##############################################
# list or specific entry number
#
sub TBot_List_getList($;$)
{
  my ($hash, $entry) = @_;
  my $name = $hash->{NAME};

  my $rd = "postme".sprintf("%2.2d",TBot_List_getConfigListno($hash))."Name";
  if ( ReadingsVal(TBot_List_getConfigPostMe($hash),$rd,"") ne TBot_List_getConfigListname($hash) ) {
    Log3 $name, 1, "TBot_List_getList: list ".TBot_List_getConfigListname($hash)." not matching listno ".TBot_List_getConfigListno($hash);
    return undef;
  }
  
  $rd = "postme".sprintf("%2.2d",TBot_List_getConfigListno($hash))."Cont";
  my $listCont = ReadingsVal(TBot_List_getConfigPostMe($hash),$rd,"");
    
  my @entries = split( /,/, $listCont );
  
  if ( defined( $entry ) ) {
    return undef if ( ( $entry < 0 ) || ( $entry > scalar(@entries) ) );
    
    return $entries[$entry];
  }

  return @entries;
}




##############################################
# list or specific entry number
#
sub TBot_List_getTextList($$)
{ 
  my ($hash) = @_;

  my @list = TBot_List_getList( $hash );
   
  return "<LEER>" if ( scalar( @list ) == 0 );
   
  return join("\r\n", @list );
}

##############################################
# set text message to wait for or undef
# undef, store, reply, textmsg, ...
sub TBot_List_setMsgId($$$;$$) {
  my ($hash, $tbot, $peer, $msgId, $postfix) = @_;

  my $key = $tbot."_".$peer.(defined($postfix)?"_".$postfix:"");
  if ( defined( $msgId ) ) {
    $msgId =~ s/\s//g;
    $hash->{inlinechats}{$key} = $msgId;
  } else {
    delete( $hash->{inlinechats}{$key} );
  }
}


##############################################
# set text message to wait for or undef
#
sub TBot_List_getMsgId($$$;$) {
  my ($hash, $tbot, $peer, $postfix) = @_;

  my $key = $tbot."_".$peer.(defined($postfix)?"_".$postfix:"");
  return $hash->{inlinechats}{$key};
}


##############################################################################
##############################################################################
##
## Handling of List in central routine from myUtils
##
##############################################################################
##############################################################################

##############################################
##############################################
# hash, tbot, events
#
sub TBot_List_handleEvents($$$)
{
  my ($hash, $tbot, $events ) = @_;
  my $name = $hash->{NAME};

  # events - look for sentMsgId / msgReplyMsgId
  foreach my $event ( @{$events} ) {
    $event = "" if(!defined($event));
    
    if ( $event =~ /sentMsgId\:/ ) {
      Log3 $name, 4, "TBot_List_handleEvents $name: found sentMsgId ". $event;
      my $msgPeer = InternalVal( $tbot, "sentMsgPeerId", "" );  
      my $msgWait = TBot_List_getMsgId( $hash, $tbot, $msgPeer, "textmsg" );
      my $msgSent = InternalVal( $tbot, "sentMsgText", "" );
      $msgSent =~ s/\s//g;
#      Debug "wait :".$msgWait.":   sent :".$msgSent.":"; 
      if ( defined( $msgWait ) && (  $msgSent eq $msgWait ) ) {
        my $arg = ReadingsVal($tbot,"sentMsgId","");
        
        # store key set means a reply is expected
        if ( defined( TBot_List_getMsgId( $hash, $tbot, $msgPeer, "store") ) ) {
          # reply received
          TBot_List_setMsgId( $hash, $tbot, $msgPeer, $arg, "reply");

          TBot_List_setMsgId( $hash, $tbot, $msgPeer, undef, "store");

        } else {
        
          TBot_List_setMsgId( $hash, $tbot, $msgPeer, $arg );

          # remove old entry ids from chg entries
          TBot_List_setMsgId( $hash, $tbot, $msgPeer, undef, "entry");
        }
        
        # set internal msg
        TBot_List_setMsgId( $hash, $tbot, $msgPeer, undef, "textmsg" );
        
      }
      
    } elsif ( $event =~ /msgReplyMsgId\:/ ) {
      Log3 $name, 4, "TBot_List_handleEvents $name: found msgReplyMsgId ". $event;
      my $msgPeer = ReadingsVal( $tbot, "msgPeerId", "" );  
      my $msgReplyId = ReadingsVal($tbot,"msgReplyMsgId","");
      $msgReplyId =~ s/\s//g;

      my $replyMsg = TBot_List_getMsgId( $hash, $tbot, $msgPeer, "reply");
      if ( $replyMsg eq $msgReplyId ) {
        TBot_List_setMsgId( $hash, $tbot, $msgPeer, undef, "reply");
        
        my $msgText = ReadingsVal( $tbot, "msgText", "" );

        # now check if an id of an entry was stored then this is edit
        my $entryno = TBot_List_getMsgId( $hash, $tbot, $msgPeer, "entry");
        if ( defined( $entryno ) ) {
          TBot_List_setMsgId( $hash, $tbot, $msgPeer, undef, "entry");

          TBot_List_handler( $hash, "list_chg-$entryno", $tbot, $msgPeer, $msgText );
        } else {
          TBot_List_handler( $hash,  "list_add", $tbot, $msgPeer, $msgText );
        }
      }
    }
  
  }
}

##############################################
##############################################
# hash, cmd, bot, peer, opt: arg
#
sub TBot_List_handler($$$$;$)
{
  my ($hash, $cmd, $tbot, $peer, $arg ) = @_;
  my $name = $hash->{NAME};

  my $ret;

  Log3 $name, 4, "JVLISTMGR_handler: $name - $tbot  peer :$peer:   cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");

  my $lname = TBot_List_getConfigListname($hash);
  my $msgId;
  my @list;
  
  if ( ! $ret ) {
    $ret = "TBot_List_handler: $name - $tbot  ERROR - $peer not allowed" if ( ! TBot_List_isAllowed( $hash, $peer ) );
  }
  
  # get Msgid and list as prefetch
  if ( ! $ret ) {
    $msgId = TBot_List_getMsgId( $hash, $tbot, $peer );
    @list = TBot_List_getList( $hash );
  }
  
  #####################  
  if ( $ret ) {
    # do nothing if error found already
#    Log 1,$ret;

  #####################  
  } elsif ( $cmd eq "list_ok" ) {
    # ok means clean buttons and show only list
    
    # start the inline
    my $inline = " ";
    
    # get the list of entries in the list
    my $liste = "";
    foreach my $entry ( @list )  {
      $liste .= "\n".$entry; 
    }
    
    my $textmsg = "Liste ".$lname;
    $textmsg .= " ist leer " if ( scalar(@list) == 0 );
    $textmsg .= " : $arg " if ( defined($arg) );
    $textmsg .= $liste;
    
    if ( defined($msgId ) ) {
      # show new list 
      fhem( "set ".$tbot." queryEditInline $msgId ".'@'.$peer." $inline $textmsg" );
      TBot_List_setMsgId( $hash, $tbot, $peer );
    } else {
      $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer:   cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
    }
    
  #####################  
  } elsif ( $cmd eq "list_done" ) {
    # done means clean buttons and show only list
    
    if ( defined($msgId ) ) {
      # show new list 
      fhem( "set ".$tbot." queryEditInline $msgId ".'@'.$peer." DONE" );
    } else {
      $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer:   cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
    }
    
  #####################  
  } elsif ( ( $cmd eq "list" ) || ( $cmd eq "list_edit" ) ) {
    # list means create button table with list entries
    
    # start the inline
    my $inline = "";
    
    # get the list of entries in the list
    my $nre = 0;
    
    my $double = (TBot_List_hasOptionDouble( $hash )?1:0);
    foreach my $entry (  @list ) {
      $entry =~ s/[\(\):]/_/g;

      if ( $double == 1 ) {
        $inline .= "(".$entry.":".$name."\%"."list_idx-".$nre; 
        $double = 2;
      } elsif ( $double == 2 ) {
        $inline .= "|".$entry.":".$name."\%"."list_idx-".$nre.") "; 
        $double = 1;
      } else {
        $inline .= "(".$entry.":".$name."\%"."list_idx-".$nre.") "; 
      }
      $nre++;
    }
    
    $inline .= ") " if ( $double == 2 );

    $inline .= "(ok:".$name."\%"."list_ok|leeren:".$name."\%"."list_askclr|hinzu:".$name."\%"."list_askadd)";
    
    my $textmsg = "Liste ".$lname;
    $textmsg .= " ist leer " if ( scalar(@list) == 0 );
    $textmsg .= " : $arg " if ( defined($arg) );
    
    if ( $cmd eq "list" ) {
      # remove msgId
      if ( defined($msgId ) ) {
        # done old list now and start a new list message
        TBot_List_handler( $hash,  "list_done", $tbot, $peer );
        TBot_List_setMsgId( $hash, $tbot, $peer );
      }
      
      # store text msg to recognize msg id in dummy
      TBot_List_setMsgId( $hash, $tbot, $peer, $textmsg, "textmsg" );
      
      # send msg and keys
      fhem( "set ".$tbot." queryInline ".'@'.$peer." $inline $textmsg" );
      
    } else {
      if ( defined($msgId ) ) {
        # show new list 
        fhem( "set ".$tbot." queryEditInline $msgId ".'@'.$peer." $inline $textmsg" );
      } else {
        $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer:   cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
      }
    }
    
  #####################  
  } elsif ( $cmd =~ /^list_idx-(\d+)$/ ) {
    # means change the entry or delete - ask for which option
    my $no = $1;
    
    if ( ( $no >= 0 ) && ( $no < scalar(@list) ) ) {
    
      # post new msg to ask for change
      if ( defined($msgId ) ) {
        # show ask for removal
        my $textmsg = "Liste ".$lname."\nEintrag ".($no+1)." (".$list[$no].") ?";
        # show ask msg 
        fhem( "set ".$tbot." queryEditInline $msgId ".'@'.$peer." (Entfernen:".$name."\%"."list_rem-$no|Aendern:".$name."\%"."list_askchg-$no) (Nach Oben:".$name."\%"."list_totop-$no|Zurueck:".$name."\%"."list_edit) $textmsg" );
      } else {
        $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer:   cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
      }
    
    }
    
  #####################  
  } elsif ( $cmd =~ /^list_totop-(\d+)$/ ) {
    # totop means make it first entry in the 
    
    my $no = $1;
    
    if ( ( $no >= 0 ) && ( $no < scalar(@list) ) ) {
      my $topentry = $list[$no];
      my $text = $topentry;
      foreach my $entry (  @list ) {
        $text .= ",".$entry if ( $entry ne $topentry );
      }
       
      fhem( "set ".TBot_List_getConfigPostMe($hash)." clear $lname " );
      fhem( "set ".TBot_List_getConfigPostMe($hash)." add $lname $text" );
    
      # show updated list -> call recursively
      TBot_List_handler( $hash,  "list_edit", $tbot, $peer, " Nach oben gesetzt" );
    }
    
  #####################  
  } elsif ( $cmd =~ /^list_rem-(\d+)$/ ) {
    # means remove a numbered entry from list - first ask
    my $no = $1;
    
    if ( ( $no >= 0 ) && ( $no < scalar(@list) ) ) {
    
      # post new msg to ask for removal
      if ( defined($msgId ) ) {
        # show ask for removal
        my $textmsg = "Liste ".$lname."\nSoll der Eintrag ".($no+1)." (".$list[$no].") entfernt werden?";
        # show ask msg 
        fhem( "set ".$tbot." queryEditInline $msgId ".'@'.$peer." (Ja:".$name."\%"."list_remyes-$no) (Nein:".$name."\%"."list_edit) $textmsg" );
      } else {
        $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer:   cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
      }
    }
     
  #####################  
  } elsif ( $cmd =~ /^list_remyes-(\d+)$/ ) {
    # means remove a numbered entry from list - now it is confirmed
    my $no = $1;
    
    if ( ( $no >= 0 ) && ( $no < scalar(@list) ) ) {
    
      fhem( "set ".TBot_List_getConfigPostMe($hash)." remove $lname ".$list[$no] );

      # show updated list -> call recursively
      TBot_List_handler( $hash,  "list_edit", $tbot, $peer, " Eintrag geloescht" );
    
    }
    
  #####################  
  } elsif ( $cmd eq "list_askclr" ) {
    # post new msg to ask for clr
    if ( defined($msgId ) ) {
      # show ask for removal
      my $textmsg = "Liste ".$lname."\nSoll die gesamte Liste ".scalar(@list)." Einträge gelöscht werden?";
      # show ask msg 
      fhem( "set ".$tbot." queryEditInline $msgId ".'@'.$peer." (Ja - Liste löschen:".$name."\%"."list_clryes|Nein:".$name."\%"."list_edit) $textmsg" );
    } else {
      $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer:   cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
    }

  #####################  
  } elsif ( $cmd eq "list_clryes" ) {
    # means remove all entries - now it is confirmed
    fhem( "set ".TBot_List_getConfigPostMe($hash)." clear $lname " );

    # show updated list -> call recursively
    TBot_List_handler( $hash,  "list_edit", $tbot, $peer, " Liste geloescht" );
    
          
  #####################  
  } elsif ( $cmd eq "list_askadd" ) {
    TBot_List_setMsgId( $hash, $tbot, $peer, $msgId, "store" );

    my $textmsg = "Liste ".$lname." Neuen Eintrag eingeben:";
    
    # store text msg to recognize msg id in dummy
    TBot_List_setMsgId( $hash, $tbot, $peer, $textmsg, "textmsg" );
    
    # means ask for an entry to be added to the list
    fhem( "set ".$tbot." msgForceReply ".'@'.$peer." $textmsg" );

  #####################  
  } elsif ( $cmd eq "list_add" ) {
    # means add entry to list
    
    # ! means put on top
    if ( $arg =~ /^\!(.+)$/ ) {
      my $text = $1;
      foreach my $entry (  @list ) {
        $text .= ",".$entry ;
      }
       
      fhem( "set ".TBot_List_getConfigPostMe($hash)." clear $lname " );
      fhem( "set ".TBot_List_getConfigPostMe($hash)." add $lname $text" );
    
    } else {
      fhem( "set ".TBot_List_getConfigPostMe($hash)." add $lname ".$arg );
    }
    
    if ( defined($msgId ) ) {
      # show new list -> call recursively
      $ret = "Eintrag hinzugefuegt";
      TBot_List_handler( $hash,  "list", $tbot, $peer, $ret );
      $ret = undef;
      
    } else {
      $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer:   cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
    }
    
  #####################  
  } elsif ( $cmd =~ /^list_askchg-(\d+)$/ ) {
    my $no = $1;

    if ( ( $no >= 0 ) && ( $no < scalar(@list) ) ) {

      TBot_List_setMsgId( $hash, $tbot, $peer, $msgId, "store" );
      
      # remove old entry ids from chg entries
      TBot_List_setMsgId( $hash, $tbot, $peer, $no, "entry" );

      my $textmsg = "Liste ".$lname." Eintrag ".($no+1)." ändern : ".$list[$no];
      
      # store text msg to recognize msg id in dummy
      TBot_List_setMsgId( $hash, $tbot, $peer, $textmsg, "textmsg" );

      # means ask for an entry to be added to the list
      fhem( "set ".$tbot." msgForceReply ".'@'.$peer." $textmsg" );
      
    }

  #####################  
  } elsif ( $cmd =~ /^list_chg-(\d+)$/ ) {
    # means add entry to list
    my $no = $1;
    
    if ( ( $no >= 0 ) && ( $no < scalar(@list) ) ) {
      my $nre = 0;
      my $text = "";
      foreach my $entry (  @list ) {
        if ( $nre == $no ) {
          $text .= ",".$arg ;
        } else {
          $text .= ",".$entry ;
        }
        $nre++;
      }
      fhem( "set ".TBot_List_getConfigPostMe($hash)." clear $lname " );
      fhem( "set ".TBot_List_getConfigPostMe($hash)." add $lname $text" );
    }
    
    if ( defined($msgId ) ) {
      # show new list -> call recursively
      $ret = "Eintrag hinzugefuegt";
      TBot_List_handler( $hash,  "list", $tbot, $peer, $ret );
      $ret = undef;
      
    } else {
      $ret = "TBot_List_handler: $name - $tbot  ERROR no msgId known for peer :$peer:   cmd :$cmd:  ".(defined($arg)?"arg :$arg:":"");
    }
    
  }

  Log3 $name, 1, $ret if ( $ret );

  return $ret;
  
}

  

   
  


##############################################################################
##############################################################################
##
## HELPER
##
##############################################################################
##############################################################################


#####################################
#  INTERNAL: get pattern replaced
# TODO - adapt for texts
sub TBot_List_ReplacePattern( $$;$ ) {
  my ( $pattern, $id, $name ) = @_;

 $pattern =~ s/q_id_q/$id/g if ( defined($id) );
 $pattern =~ s/q_name_q/$name/g if ( defined($name) );

 return $pattern;
}

#####################################
#  notify function provide dev and 
# is corresponding to the delete command the opposite to the define function 
sub TBot_List_isTBot($$)
{
  my ($hash,$tbot) = @_;
  
  my @tbots = devspec2array( "TYPE=TelegramBot" );
  foreach my $abot ( @tbots ) {
    return 1 if ( $abot eq $tbot ) ;
  }
  
  return 0;
}





#####################################
#  INTERNAL: Get Id for a camera or list of all cameras if no name or id was given or undef if not found
sub TBot_List_CheckSetGet( $$$ ) {
  my ( $hash, $cmd, $options ) = @_;

  if (!exists($options->{$cmd}))  {
    my @cList;
    foreach my $k (keys %$options) {
      my $opts = undef;
      $opts = $options->{$k};

      if (defined($opts)) {
        push(@cList,$k . ':' . $opts);
      } else {
        push (@cList,$k);
      }
    } # end foreach

    return "TBot_List_Set: Unknown argument $cmd, choose one of " . join(" ", @cList);
  } # error unknown cmd handling
  return undef;
}

##############################################################################
##############################################################################
##
## Setup
##
##############################################################################
##############################################################################

  


######################################
#  make sure a reinitialization is triggered on next update
#  
sub TBot_List_Setup($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "TBot_List_Setup $name: called ";

  $hash->{STATE} = "Undefined";
  
  my %sets = (
    "start" => undef,
    "end" => undef,

  );

  my %gets = (
    "queryAnswer" => undef,

  );

  $hash->{getoptions} = \%gets;
  $hash->{setoptions} = \%sets;
  
  my %hh = ();
  $hash->{inlinechats} = \%hh;
  
  # get global notifications and from all telegramBots
  $hash->{NOTIFYDEV} = "global,TYPE=TelegramBot";

  $hash->{STATE} = "Defined";

  Log3 $name, 4, "TBot_List_Setup $name: ended ";

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
=item summary    Dialogs for PostMe lists in TelegramBot 
=item summary_DE Dialoge über TelegramBot für PostMe-Listen
=begin html

<a name="TBot_List"></a>
<h3>TBot_List</h3>
<ul>

  This module connects for allowing inline keyboard interactions between a telegramBot and PostMe lists.
  
  <br><br>
  <a name="TBot_Listdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TBot_List &lt;PostMe device&gt; &lt;listname&gt; </code>
    <br><br>
    Defines a TBot_List device, which will allow interaction between the telegrambot and the postme device
    <br><br>
    Example: <code>define testtbotlist TBot_List testposteme testlist</code><br>
    <br>
  </ul>
  <br><br>   
  
  <a name="TBot_Listset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;what&gt; [&lt;value&gt;]</code>
    <br>
    where &lt;what&gt; / &lt;value&gt; is one of

  <br><br>
    <li><code>start &lt;telegrambot name&gt; [ &lt;peerid&gt; ]</code><br>Initiate a new dialog for the given peer (or the last peer sending a message on the given telegrambot)
    </li>
    <li><code>end &lt;telegrambot name&gt; &lt;peerid&gt;</code><br>Finalize a new dialog for the given peer  on the given telegrambot
    </li>
    
  </ul>

  <br><br>

  <a name="TBot_Listget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;what&gt; [&lt;value&gt;]</code>
    <br>
    where &lt;what&gt; / &lt;value&gt; is one of

  <br><br>
    <li><code>querAnswer &lt;telegrambot name&gt; &lt;peerid&gt; &lt;queryData&gt; </code><br>Get the queryAnswer for the given query data in the dialog (will be called internally by the telegramBot on receiving querydata) 
    </li>
    
  </ul>

  <br><br>

  <a name="TBot_Listattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>telegramBots &lt;list of telegramBot names separated by space&gt;</code><br>This attribute takes the names of telegram bots, that are monitored by this Tbot_List device
    </li> 

    <li><code>optionDouble &lt;1 or 0&gt;</code><br>Specify if the list shall be done in two columns (double=1) or in a single column (double=0 or not set).
    </li> 
    
    <li><code>allowedPeers &lt;list of peer ids&gt;</code><br>If specifed further restricts the users for the given list to these peers. It can be specifed in the same form as in the telegramBot msg command but without the leading @ (so ids will be just numbers).
    </li> 
  </ul>

  <br><br>


    <a name="TBot_Listreadings"></a>
  <b>Readings</b>
  
  <ul>
    <li>currently none</li> 
    
    <br>
    
  </ul> 

  <br><br>   
</ul>



=end html
=cut