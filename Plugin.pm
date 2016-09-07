package Plugins::DomoticzControl::Plugin;

use strict; 

use base qw(Slim::Plugin::Base);
use JSON::XS::VersionOneAndTwo;
use Slim::Control::Request;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Timers;
use Slim::Utils::Prefs;
use Time::HiRes;
use Slim::Utils::Strings qw (string);

my %idxTimers  = ();
my %idxLevels  = ();
my %domoUrl = ();


sub getDisplayName { 
    return 'PLUGIN_DOMOTICZCONTROL'; 
} 

my $log = Slim::Utils::Log->addLogCategory({
    'category' => 'plugin.DomoticzControl',
    'defaultLevel' => 'ERROR',
    'description' => getDisplayName(),
});

my $prefs = preferences('plugin.DomoticzControl');

#sub enabled {
#}

my $defaultPrefs = {
    'address'                   => '127.0.0.1',
    'port'                      => 8080,
    'https'                     => 0,
    'user'                      => '',
    'password'                  => '',
    'onlyFavorites'             => 1,
    'onlyUnproctected'          => 1,
    'dimmerAsOnOff'             => 1,
    'blindsPercentageAsOnOff'   => 1,
    'hideScenes'                => 0,
    'hideOnOff'                 => 0,
    'hideDimmers'               => 0,
    'hideBlinds'                => 0,
    'filterByName'              => "",
    'filterByDescription'       => "",
    'filterByPlanId'            => 0,
};

sub initPref {
    my $client = shift;
    
    $log->debug('Init pref');
    
    unless ($domoUrl{$client->id}) {
        $prefs->client($client)->init($defaultPrefs);
        $domoUrl{$client->id} = 
            $prefs->client($client)->get('https') ? 'https://' : 'http://' .
            ((!($prefs->client($client)->get('user') eq '') && ($prefs->client($client)->get('password') eq '')) ? $prefs->client($client)->get('user') . '@' : '') .
            ((!($prefs->client($client)->get('password') eq '')) ? $prefs->client($client)->get('user') . ':' . $prefs->client($client)->get('password') . '@' : '') .
            $prefs->client($client)->get('address') .
            ':' . $prefs->client($client)->get('port') .
            '/json.htm?';
        $log->debug('Setting URL to '. $domoUrl{$client->id});
    }    
}

sub _setToDomoticzCallback {
    $log->debug('Got answer from Domoticz after set');
    
    $log->debug('done');
}

sub _setToDomoticzErrorCallback {
    my $http    = shift;
    my $error   = $http->error;

    $log->error('No answer from Domoticz after set');
}

sub needsClient {
	return 1;
}

sub _setToDomoticz {
    my $client = shift;
    my $idx = shift;
    my $cmd = shift;
    my $level = shift;
    my $IP='127.0.0.1';
    my $PORT='8080';   
 #   my $trendsurl = "http://$IP:$PORT/json.htm?type=command&param=switchlight&idx=" . $idx . '&switchcmd=' . $cmd . $level;
    my $trendsurl = $domoUrl{$client->id} . 'type=command&param=switchlight&idx=' . $idx . '&switchcmd=' . $cmd . $level;
    
    $log->debug('Send data to Domoticz: '. $trendsurl);  
    
    if (exists $idxTimers{$idx}) {
        delete $idxTimers{$idx};
    }
    
    my $http = Slim::Networking::SimpleAsyncHTTP->new(
        \&_setToDomoticzCallback,
        \&_setToDomoticzErrorCallback, 
        {
            cache    => 0,		# optional, cache result of HTTP request
        }
    );
    
    $http->get($trendsurl);
}

sub setToDomoticz {
    my $request = shift;
    my $client  = $request->client();
    my $idx = $request->getParam('idx');
    my $cmd = $request->getParam('cmd');
    my $level = $request->getParam('level');
    my @args = ($idx, $cmd, $level);
    
    _setToDomoticz($client, $idx, $cmd, $level);
    
    $request->setStatusProcessing();
}



sub setToDomoticzTimer{
    my $request = shift;
    my $client  = $request->client();
    my $idx = $request->getParam('idx');
    my $cmd = $request->getParam('cmd');
    my $level = $request->getParam('level');
    
    $idxLevels{$idx} = $level;
    
    if (exists $idxTimers{$idx}) {
        Slim::Utils::Timers::killSpecific($idxTimers{$idx});
    }
    
    $idxTimers{$idx} = Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, \&_setToDomoticz, $idx, $cmd, $level);
    
    $request->setStatusDone();
}


sub menuDomoticzDimmer {
    my $request = shift;    
    my $idx = $request->getParam('idx');
    my $level = $request->getParam('level');
    my $max = $request->getParam('max');
    
    if (exists $idxLevels{$idx}) {
        $level = $idxLevels{$idx};
    }
    
    $log->debug('Slider menu');
    
    my $slider = {
        slider   => 1,
        min      => 0,
        max      => $max + 0,
        initial  => $level + 0,
        actions  => {
            do   => {
                player => 0,
                cmd    => ['setToDomoticzTimer'],
                params => {
                    idx    => $idx,
                    cmd    => 'Set%20Level&level=',
                    valtag => 'level',
                },
            },
        },
    };
    
    $request->addResult('offset', 0);
    $request->addResult('count', 1);
    $request->setResultLoopHash('item_loop', 0, $slider);
    
    $request->setStatusDone();
    
    $log->debug('done');
}


sub _filterDomoticzOnOff {
    my $client = shift;
    my $elem = shift;
    
    if ($elem->{'SwitchTypeVal'} == 0) {
        if ($prefs->client($client)->get('hideOnOff')) {
            return 0;
        }
        else {
            return 1;
        }
    }
    
    if ($elem->{'SwitchTypeVal'} == 7) {
        if ($prefs->client($client)->get('hideDimmers')) {
            return 0;
        }
        elsif ($prefs->client($client)->get('dimmerAsOnOff')) {
            return 1;
        }
        else {
            return 2;
        }
    }
    
    if (
        ($elem->{'SwitchTypeVal'} == 3)
        || ($elem->{'SwitchTypeVal'} == 6)
    ) {
        if ($prefs->client($client)->get('hideBlinds')) {
            return 0;
        }
        else {
            return 1;
        }
    }

    if (
        ($elem->{'SwitchTypeVal'} == 13)
        || ($elem->{'SwitchTypeVal'} == 16)
    ) {
        if ($prefs->client($client)->get('hideBlinds')) {
            return 0;
        }
        elsif ($prefs->client($client)->get('blindsPercentageAsOnOff')) {
            return 1;
        }
        else {
            return 2;
        }
    }
    
    return 0;
}

sub _strMatch {
    my $strmatch = shift;
    my $strToCheck = shift;
    
    if (
        !($strmatch eq "")
        && ($strToCheck !~ $strmatch)
    ) {
        return 0;
    }
    
    return 1;
}

sub _filterDomoticz {
    my $client = shift;
    my $elem = shift;
    my $planId = $prefs->client($client)->get('filterByPlanId');
    
    unless ($planId == 0) {
        if (exists($elem->{'PlanIDs'})) {
            unless ( grep( /^$planId/, @{ $elem->{'PlanIDs'} } ) ) {
                return 0;
            }
        }
    }      
    
    if (
        $prefs->client($client)->get('onlyFavorites') 
        && !$elem->{'Favorite'}
    ) {
        return 0;
    }
    
    if (
        $prefs->client($client)->get('onlyUnproctected')
        && $elem->{'Protected'}
    ) {
        return 0;
    }
    
    unless(_strMatch($prefs->client($client)->get('filterByName'), $elem->{'Name'})) {
        return 0;
    }
    
    unless (_strMatch($prefs->client($client)->get('filterByDescription'), $elem->{'Description'})) {
        return 0;
    }
    
    return 1;
}

sub _getScenesFromDomoticzCallback {
    my $http = shift;
    my $request = $http->params('request');
    my $client = $request->client();
    my @devices = @{ $http->params('devices') };
    my @menu = ();
    my $level;
    
    undef %idxLevels;
    
    $log->debug('Got answer from Domoticz after get scenes');
    
    my $content = $http->content();
    my $decoded = decode_json($content);
    my @results = @{ $decoded->{'result'} };
    
    unless ($prefs->client($client)->get('hideScenes')) {
        foreach my $f ( @results ) {
            $log->debug($f->{'Name'} . ' (idx=' . $f->{'idx'} . ') is ' . $f->{'Status'} . $f->{'Favorite'} . $f->{'Protected'});
            if (_filterDomoticz($client, $f)) {
                push @menu, {
                    text => $f->{'Name'},
                    checkbox => (($f->{'Status'} eq 'On') || ($f->{'Status'} eq 'Open')) + 0,
                    actions  => {
                        on   => {
                            player => 0,
                            cmd    => ['setToDomoticz'],
                            params => {
                                idx    => $f->{'idx'},
                                cmd    => 'On',
                            },
                        },
                        off   => {
                            player => 0,
                            cmd    => ['setToDomoticz'],
                            params => {
                                idx    => $f->{'idx'},
                                cmd    => 'Off',
                            },
                        },
                    },		
                };
            }
        }
    }
    
    foreach my $f ( @devices ) {
        if (_filterDomoticz($client, $f)) {
            # Percentage (dimmer, blind, etc.)
            if (_filterDomoticzOnOff($client, $f) == 2) {
                $log->debug($f->{'Name'} . ' (idx=' . $f->{'idx'} . ') is ' . $f->{'Status'});
                $log->debug('Dimmer ' . $f->{'MaxDimLevel'} . ' (LevelInt=' . $f->{'LevelInt'} . ')');
                
                if (
                    ($f->{'Status'} eq 'On')
                    || ($f->{'Status'} eq 'Open')
                ) {
                    $level = $f->{'MaxDimLevel'};
                }
                elsif (
                    ($f->{'Status'} eq 'Off')
                    || ($f->{'Status'} eq 'Closed')
                ) {
                    $level = 0;
                }
                else {
                    $level = $f->{'LevelInt'};
                }
                push @menu, {
                    text     => $f->{'Name'},
                    actions  => {
                        go => {
                            player => 0,
                            cmd    => ['menuDomoticzDimmer'],
                            params => {
                                idx    => $f->{'idx'},
                                level  => $level,
                                max    => $f->{'MaxDimLevel'},
                            },
                        },
                    },
                };
            }
            # Normal On/Off
            elsif (_filterDomoticzOnOff($client, $f) == 1) {
                push @menu, {
                    text     => $f->{'Name'},
                    checkbox => (!($f->{'Status'} eq 'Off') && !($f->{'Status'} eq 'Closed')) + 0,
                    actions  => {
                        on   => {
                            player => 0,
                            cmd    => ['setToDomoticz'],
                            params => {
                                idx    => $f->{'idx'},
                                cmd    => 'On',
                            },
                        },
                        off  => {
                            player => 0,
                            cmd    => ['setToDomoticz'],
                            params => {
                                idx    => $f->{'idx'},
                                cmd    => 'Off',
                            },
                        },
                    },		
                };
            }
        }
    }

    my $numitems = scalar(@menu);

    if ($numitems > 0) {
        $request->addResult('count', $numitems);
        $request->addResult('offset', 0);
        my $cnt = 0;
        for my $eachPreset (@menu[0..$#menu]) {
            $request->setResultLoopHash('item_loop', $cnt, $eachPreset);
            $cnt++;
        }
    }

    $request->setStatusDone();
    
    $log->debug('done');
}

sub _getScenesFromDomoticzErrorCallback {
    my $http    = shift;
    my $error   = $http->error;
    my $request = $http->params('request');

    # Not sure what status to use here
    $request->setStatusBadParams();
    $log->debug('No answer from Domoticz after get scenes');
}

sub _getFromDomoticzCallback {
    my $http = shift;
    my $request = $http->params('request');
    my $client  = $request->client();
    my @menu = ();
    my $trendsurl = $domoUrl{$client->id} . 'type=scenes&used=true';

    $log->debug('Got answer from Domoticz after get for devices');
    
    my $content = $http->content();
    my $decoded = decode_json($content);
    my @results = @{ $decoded->{'result'} };
  
    $log->debug('Ask scenes to Domoticz: '. $trendsurl);  
    
    my $http = Slim::Networking::SimpleAsyncHTTP->new(
	\&_getScenesFromDomoticzCallback,
	\&_getScenesFromDomoticzErrorCallback, 
	{
		request  => $request,
		devices  => \@results,
		cache    => 0,		# optional, cache result of HTTP request
	}
    );
    
    $http->get($trendsurl);
}

sub _getFromDomoticzErrorCallback {
    my $http    = shift;
    my $error   = $http->error;
    my $request = $http->params('request');

    # Not sure what status to use here
    $request->setStatusBadParams();
    $log->error('No answer from Domoticz after get devices');
}

sub getFromDomoticz {
    my $request = shift;
    my $client  = $request->client();

    initPref($client);
    
    my $idx = $request->getParam('_idx');
    my $cmd = $request->getParam('_cmd');
    my $trendsurl = $domoUrl{$client->id} . 'type=devices&filter=light&used=true';

    $log->debug('Ask devices to Domoticz: '. $trendsurl);  
    
    my $http = Slim::Networking::SimpleAsyncHTTP->new(
	\&_getFromDomoticzCallback,
	\&_getFromDomoticzErrorCallback, 
	{
		request  => $request,
		cache    => 0,		# optional, cache result of HTTP request
	}
    );
    
    $http->get($trendsurl);
    
    $request->setStatusProcessing();
}

sub setAlarmToDomoticz {
    my $request = shift;
    my $client  = $request->client();
    my $alarmType = $request->getRequest(1);
    my $alarmId = $request->getParam('_id');
    my $idx;
    my $cmd;
    my %alarms = %{ $prefs->client($client)->get('alarms') };
    my %snoozes = %{ $prefs->client($client)->get('snoozes') };
   
    initPref($client);
    
    #Data::Dump::dump($request);
    
    if ($alarmType eq "sound") {
        $log->debug('Alarm on to Domoticz: '. $alarmId);
        $idx = $alarms{$alarmId};
        $cmd = 'On';
        if (length $idx) {
            _setToDomoticz($client, $idx, $cmd);
        }
    }
    elsif ($alarmType eq "end") {
        $log->debug('Alarm off to Domoticz: '. $alarmId);
        $idx = $alarms{$alarmId};
        $cmd = 'Off';
        if (length $idx) {
            _setToDomoticz($client, $idx, $cmd);
        }
    }
    elsif ($alarmType eq "snooze") {
        $log->debug('Snooze on to Domoticz: '. $alarmId);
        $idx = $snoozes{$alarmId};
        $cmd = 'On';
        if (length $idx) {
            _setToDomoticz($client, $idx, $cmd);
        }
    }
    elsif ($alarmType eq "snooze_end") {
        $log->debug('Snooze off to Domoticz: '. $alarmId);
        $idx = $snoozes{$alarmId};
        $cmd = 'Off';
        if (length $idx) {
            _setToDomoticz($client, $idx, $cmd);
        }
    }
}

sub initPlugin {
    my $class = shift;

    if (main::WEBUI) {
        require Plugins::DomoticzControl::Settings;
        Plugins::DomoticzControl::Settings->new();
    }

    $class->SUPER::initPlugin();

    Slim::Control::Request::addDispatch(['menuDomoticzDimmer'],[1, 0, 1, \&menuDomoticzDimmer]);	
    Slim::Control::Request::addDispatch(['setToDomoticz'],[1, 0, 1, \&setToDomoticz]);	
    Slim::Control::Request::addDispatch(['setToDomoticzTimer'],[1, 0, 1, \&setToDomoticzTimer]);
    Slim::Control::Request::addDispatch(['getFromDomoticz'],[1, 0, 1, \&getFromDomoticz]);	

    my @menu = ({
        stringToken   => getDisplayName(),
        id     => 'pluginDomoticzControlmenu',
        'icon-id' => Plugins::DomoticzControl::Plugin->_pluginDataFor('icon'),
        weight => 15,
	actions => {
            go => {
                player => 0,
                cmd	 => ['getFromDomoticz'],
            }
        }
    });

#    Slim::Control::Jive::registerAppMenu(\@menu);
#    $class->addNonSNApp();
    Slim::Control::Jive::registerPluginMenu(\@menu, 'extras');
    
    # Subscribe to alarms
    Slim::Control::Request::subscribe(
            \&setAlarmToDomoticz,
            [['alarm'],['sound', 'end', 'snooze', 'snooze_end']]
    );
}

sub shutdownPlugin {
    my $class = shift;
    Slim::Control::Request::unsubscribe(\&setAlarmToDomoticz);
    Slim::Control::Jive::deleteMenuItem('pluginDomoticzControlmenu');
}

1;

__END__
