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
use POSIX qw(ceil floor);

my %idxTimers  = ();
my %idxLevels  = ();
my %domoUrl = ();
my %cachedResults = ();
my $funcptr = undef;
my @requestsQueue = ();
my $requestProcessing = 0;

use constant SWITCH_TYPE_PUSH        => 5;
use constant SWITCH_TYPE_SELECTOR    => 4;
use constant SWITCH_TYPE_TEMPERATURE => 3;
use constant SWITCH_TYPE_DIMMER      => 2;
use constant SWITCH_TYPE_SWITCH      => 1;
use constant SWITCH_TYPE_NONE        => 0;
use constant CACHE_TIME              => 30;

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
    'hideGroups'                => 0,
    'hideOnOff'                 => 0,
    'hideDimmers'               => 0,
    'hideBlinds'                => 0,
    'filterByName'              => '',
    'filterByDescription'       => '',
    'filterByPlanId'            => 0,
    'deviceOnOff'               => 0,
    'generalAlarm'              => 0,
    'generalSnooze'             => 0,
};

sub getPrefNames {
    my @prefNames = keys %$defaultPrefs;
    return @prefNames;
}

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
        my $anoDomoUrl = 
            $prefs->client($client)->get('https') ? 'https://' : 'http://' .
            ((!($prefs->client($client)->get('user') eq '') && ($prefs->client($client)->get('password') eq '')) ? 'username@' : '') .
            ((!($prefs->client($client)->get('password') eq '')) ? 'username:********@' : '') .
            $prefs->client($client)->get('address') .
            ':' . $prefs->client($client)->get('port') .
            '/json.htm?';
        $log->debug('Setting URL to '. $anoDomoUrl);
    }
    return $domoUrl{$client->id};
}

sub clientEvent {
    my $request = shift;
    my $client  = $request->client;

    $log->debug('Client event');
    
    if (defined $client) {
        $log->debug('Client event with client defined');
        initPref($client);
    }    
}

sub resetPref {
    my $client = shift;
    
    $log->debug('Reset pref');
    
    if (exists $domoUrl{$client->id}) {
        delete $domoUrl{$client->id};
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
    my $param = shift;
    my $cmd = shift;
    my $level = shift;
    my $IP='127.0.0.1';
    my $PORT='8080';   
 #   my $trendsurl = 'http://$IP:$PORT/json.htm?type=command&param=switchlight&idx=' . $idx . '&switchcmd=' . $cmd . $level;
    my $trendsurl = initPref($client) . 'type=command&param=' . $param . '&idx=' . $idx . '&' . $cmd . '=' . $level;
    
    $log->debug('Send data to Domoticz: '. $trendsurl);  
    
    if (exists $idxTimers{$idx}) {
        delete $idxTimers{$idx};
    }
    
    my $http = Slim::Networking::SimpleAsyncHTTP->new(
        \&_setToDomoticzCallback,
        \&_setToDomoticzErrorCallback, 
        {
            cache    => 0, # optional, cache result of HTTP request
        }
    );
    
    $http->get($trendsurl);
}

sub setToDomoticz {
    my $request = shift;
    my $client  = $request->client();
    my $idx = $request->getParam('idx');
    my $param = $request->getParam('param');
    my $cmd = $request->getParam('cmd');
    my $level = $request->getParam('level');
    my @args = ($idx, $cmd, $level, $param);
    
    _setToDomoticz($client, $idx, $param, $cmd, $level);
    
    $request->setStatusProcessing();
}

sub setToDomoticzTimer{
    my $request = shift;
    my $client  = $request->client();
    my $idx = $request->getParam('idx');
    my $param = $request->getParam('param');
    my $cmd = $request->getParam('cmd');
    my $level = $request->getParam('level');
    
    $idxLevels{$idx} = $level;
    
    if (exists $idxTimers{$idx}) {
        Slim::Utils::Timers::killSpecific($idxTimers{$idx});
    }
    
    $idxTimers{$idx} = Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, \&_setToDomoticz, $idx, $param, $cmd, $level);
    
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
                    param  => 'switchlight',
                    cmd    => 'switchcmd=Set%20Level&level',
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


sub _filterDomoticzSupportedDevice {
    my $client = shift;
    my $elem = shift;

    if (defined $elem->{'LevelNames'}) {
        return SWITCH_TYPE_SELECTOR;
    }
    
    if (defined $elem->{'SetPoint'}) {
        return SWITCH_TYPE_TEMPERATURE;
    }
    
    if (!defined $elem->{'SwitchType'}) {
        return SWITCH_TYPE_NONE;
    }
    
    if (!defined $elem->{'SwitchTypeVal'}) {
        return SWITCH_TYPE_NONE;
    }
    
    if ($elem->{'SwitchTypeVal'} == 0) {
        if ($prefs->client($client)->get('hideOnOff')) {
            return SWITCH_TYPE_NONE;
        }
        else {
            return SWITCH_TYPE_SWITCH;
        }
    }
    
    if (
        ($elem->{'SwitchTypeVal'} == 9)
        || ($elem->{'SwitchTypeVal'} == 10)
    ) {
        if ($prefs->client($client)->get('hideOnOff')) {
            return SWITCH_TYPE_NONE;
        }
        else {
            return SWITCH_TYPE_PUSH;
        }
    }
    
    if ($elem->{'SwitchTypeVal'} == 7) {
        if ($prefs->client($client)->get('hideDimmers')) {
            return SWITCH_TYPE_NONE;
        }
        elsif ($prefs->client($client)->get('dimmerAsOnOff')) {
            return SWITCH_TYPE_SWITCH;
        }
        else {
            return SWITCH_TYPE_DIMMER;
        }
    }
    
    if (
        ($elem->{'SwitchTypeVal'} == 3)
        || ($elem->{'SwitchTypeVal'} == 6)
    ) {
        if ($prefs->client($client)->get('hideBlinds')) {
            return SWITCH_TYPE_NONE;
        }
        else {
            return SWITCH_TYPE_SWITCH;
        }
    }

    if (
        ($elem->{'SwitchTypeVal'} == 13)
        || ($elem->{'SwitchTypeVal'} == 16)
    ) {
        if ($prefs->client($client)->get('hideBlinds')) {
            return SWITCH_TYPE_NONE;
        }
        elsif ($prefs->client($client)->get('blindsPercentageAsOnOff')) {
            return SWITCH_TYPE_SWITCH;
        }
        else {
            return SWITCH_TYPE_DIMMER;
        }
    }
    
    return SWITCH_TYPE_NONE;
}

sub _strMatch {
    my $strmatch = shift;
    my $strToCheck = shift;
    
    if (
        !($strmatch eq '')
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
        if ($elem->{'PlanIDs'}) {
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
    my $request = $http->params('slimrequest');
    my $client = $request->client();
    my @devices;
    my @menu;
    my $level;

    if ($http->params('devices')) {
        @devices = @{ $http->params('devices') };
    }
    
    %idxLevels = ();

    $log->debug('Got answer from Domoticz after get scenes');
    
    my $content = $http->content();
    my $decoded = decode_json($content);
    my @results;

    if ($decoded->{'result'}) {
        @results = @{ $decoded->{'result'} };
    }
    
    # cf. http://wiki.slimdevices.com/index.php/SBS_SqueezePlay_interface for menu architecture
    foreach my $f ( @results ) {
        $log->debug($f->{'Name'} . ' (idx=' . $f->{'idx'} . ') is ' . $f->{'Status'} . ' favorite '  .  $f->{'Favorite'} . ' protected '  . $f->{'Protected'});
        if (_filterDomoticz($client, $f)) {
            if (
                !$prefs->client($client)->get('hideScenes') 
                && ($f->{'Type'} eq 'Scene')
            ) {
                push @menu, {
                    text => $f->{'Name'},
                    radio => 0,
                    nextWindow => 'refresh',
                    actions  => {
                        do   => {
                            player => 0,
                            cmd    => ['setToDomoticz'],
                            params => {
                                idx    => $f->{'idx'},
                                param  => 'switchscene',
                                cmd    => 'switchcmd',
                                level  => 'On',
                            },
                        },
                    },
                };
            }
            if (
                !$prefs->client($client)->get('hideGroups') 
                && ($f->{'Type'} eq 'Group')
            ) {
                push @menu, {
                    text => $f->{'Name'},
                    #nextWindow => 'refresh',
                    checkbox => (($f->{'Status'} eq 'On') || ($f->{'Status'} eq 'Open')) + 0,
                    actions  => {
                        on   => {
                            player => 0,
                            cmd    => ['setToDomoticz'],
                            params => {
                                idx    => $f->{'idx'},
                                param  => 'switchscene',
                                cmd    => 'switchcmd',
                                level  => 'On',
                            },
                        },
                        off   => {
                            player => 0,
                            cmd    => ['setToDomoticz'],
                            params => {
                                idx    => $f->{'idx'},
                                param  => 'switchscene',
                                cmd    => 'switchcmd',
                                level  => 'Off',
                            },
                        },
                    },
                };
            }
        }
    }
    
    foreach my $f ( @devices ) {
        if (_filterDomoticz($client, $f)) {
            # Selector
            if (_filterDomoticzSupportedDevice($client, $f) == SWITCH_TYPE_SELECTOR) {
                $log->debug($f->{'Name'} . ' (idx=' . $f->{'idx'} . ') is ' . $f->{'Status'});
                $log->debug('Selector LevelInt=' . $f->{'LevelInt'});
                
                my @choiceStrings = split(/\|/, $f->{'LevelNames'});
                my @choiceActions;
                my $currentSetting = 0;
                my $level = 0;

                if ($f->{'LevelOffHidden'}) {
                    splice(@choiceStrings, 0, 1);
                }
                for my $iii (0..$#choiceStrings) {
                    $level = $iii * 10;
                    if ($f->{'LevelOffHidden'}) {
                        $level = $level + 10;
                    }
                    if ($f->{'LevelInt'} == $level) {
                        $currentSetting = $iii+1;
                    }
                    push @choiceActions, 
                    {
                        player => 0,
                        cmd    => ['setToDomoticz'],
                        params => {
                            idx    => $f->{'idx'},
                            param  => 'switchlight',
                            cmd    => 'switchcmd=Set%20Level&level',
                            level  => $level,
                        },
                    },
                }

                push @menu, {
                    text     => $f->{'Name'},
                    selectedIndex => $currentSetting,
                    choiceStrings => [ @choiceStrings ],
                    actions  => {
                        do => {
                            choices => [ @choiceActions ],
                        },
                    },
                };
            }
            # Setpoint
            elsif (_filterDomoticzSupportedDevice($client, $f) == SWITCH_TYPE_TEMPERATURE) {
                $log->debug($f->{'Name'} . ' (idx=' . $f->{'idx'} . ') is ' . $f->{'Status'});
                $log->debug('Setpoint ' . $f->{'SetPoint'});
                
                push @menu, {
                    text     => $f->{'Name'} . ': '. $f->{'SetPoint'},
                    nextWindow => 'parent',
                    input    => {
                        initialText => $f->{'SetPoint'},
                        len => 1,
                        allowedChars => '.0123456789',
                    },
                    window   => {
                        text => $f->{'Name'},
                    },
                    actions  => {
                        go => {
                            player => 0,
                            cmd    => ['setToDomoticz'],
                            params => {
                                idx    => $f->{'idx'},
                                param  => 'udevice',
                                cmd    => 'nvalue=0&svalue',
                                level  => '__TAGGEDINPUT__',
                            },
                        },
                    },
                };
            }
            # Percentage (dimmer, blind, etc.)
            elsif (_filterDomoticzSupportedDevice($client, $f) == SWITCH_TYPE_DIMMER) {
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
            elsif (_filterDomoticzSupportedDevice($client, $f) == SWITCH_TYPE_SWITCH) {
                push @menu, {
                    text     => $f->{'Name'},
                    checkbox => (($f->{'Status'} eq 'On') || ($f->{'Status'} eq 'Open')) + 0,
                    actions  => {
                        on   => {
                            player => 0,
                            cmd    => ['setToDomoticz'],
                            params => {
                                idx    => $f->{'idx'},
                                param  => 'switchlight',
                                cmd    => 'switchcmd',
                                level  => 'On',
                            },
                        },
                        off  => {
                            player => 0,
                            cmd    => ['setToDomoticz'],
                            params => {
                                idx    => $f->{'idx'},
                                param  => 'switchlight',
                                cmd    => 'switchcmd',
                                level  => 'Off',
                            },
                        },
                    },
                };
            }
            # push On/Off
            elsif (_filterDomoticzSupportedDevice($client, $f) == SWITCH_TYPE_PUSH) {
                my $doLevel;
                if ($f->{'SwitchType'} =~ m/Off/) {
                    $doLevel = 'Off';
                }
                else {
                    $doLevel = 'On';
                }
                push @menu, {
                    text     => $f->{'Name'},
                    radio    => 0,
                    nextWindow => 'refresh',
                    actions  => {
                        do   => {
                            player => 0,
                            cmd    => ['setToDomoticz'],
                            params => {
                                idx    => $f->{'idx'},
                                param  => 'switchlight',
                                cmd    => 'switchcmd',
                                level  => $doLevel,
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
    my $request = $http->params('slimrequest');

    # Not sure what status to use here
    $request->setStatusBadParams();
    $log->error('No answer from Domoticz after get scenes');
}

sub _getFromDomoticzCallback {
    my $http = shift;
    my $request = $http->params('slimrequest');
    my $client  = $request->client();
    my @menu;
    my $trendsurl = initPref($client) . 'type=scenes&used=true';

    $log->debug('Got answer from Domoticz after get for devices');
    
    my $content = $http->content();
    my $decoded = decode_json($content);
    my @results;

    if ($decoded->{'result'}) {
        @results = @{ $decoded->{'result'} };
    }
  
    $log->debug('Ask scenes to Domoticz: '. $trendsurl);  
    
    my $http = Slim::Networking::SimpleAsyncHTTP->new(
        \&_getScenesFromDomoticzCallback,
        \&_getScenesFromDomoticzErrorCallback, 
        {
            slimrequest  => $request,
            devices  => \@results,
            cache    => 0, # optional, cache result of HTTP request
        }
    );
    
    $http->get($trendsurl);
}

sub _getFromDomoticzErrorCallback {
    my $http    = shift;
    my $error   = $http->error;
    my $request = $http->params('slimrequest');

    # Not sure what status to use here
    $request->setStatusBadParams();
    $log->error('No answer from Domoticz after get devices');
}

sub getFromDomoticz {
    my $request = shift;
    my $client  = $request->client();
    
    my $trendsurl = initPref($client) . 'type=devices&used=true';

    $log->debug('Ask devices to Domoticz: '. $trendsurl);  
    
    my $http = Slim::Networking::SimpleAsyncHTTP->new(
        \&_getFromDomoticzCallback,
        \&_getFromDomoticzErrorCallback, 
        {
            slimrequest  => $request,
            cache    => 0, # optional, cache result of HTTP request
        }
    );
    
    $http->get($trendsurl);
    
    $request->setStatusProcessing();
}

sub powerCallback {
    my $request = shift;
    my $client = $request->client() || return;
    my $param = 'switchlight';
    my $cmd = 'switchcmd';
    my $level;
    my $idx = $prefs->client($client)->get('deviceOnOff');

    if ($idx > 0) {
        if ($client->power()) {
            $level = 'On';
        }
        else {
            $level = 'Off';
        }
        initPref($client);
        _setToDomoticz($client, $idx, $param, $cmd, $level);
    }
 }

sub setAlarmToDomoticz {
    my $request = shift;
    my $client  = $request->client() || return;
    my $alarmType = $request->getRequest(1);
    my $alarmId = $request->getParam('_id');
    my $idx;
    my $level;
    my $param = 'switchlight';
    my $cmd = 'switchcmd';
    my %alarms;
    my %snoozes;
    initPref($client);
    my $generalAlarm = $prefs->client($client)->get('generalAlarm');
    my $generalSnooze = $prefs->client($client)->get('generalSnooze');
    my $prefsAlarms = $prefs->client($client)->get('alarms');
    my $prefsSnoozes = $prefs->client($client)->get('snoozes');
    if ($prefsAlarms) {
        %alarms = %{ $prefsAlarms };
    }
    if ($prefsSnoozes) {
        %snoozes = %{ $prefsSnoozes };
    }
   
    
    #Data::Dump::dump($request);
    
    if ($alarmType eq 'sound') {
        $log->debug('Alarm on to Domoticz: '. $alarmId);
        $idx = $alarms{$alarmId};
        $level = 'On';
        if ((length $idx) && ($idx > 0)) {
            _setToDomoticz($client, $idx, $param, $cmd, $level);
        }
        if ((length $generalAlarm) && ($generalAlarm > 0)) {
            _setToDomoticz($client, $generalAlarm, $param, $cmd, $level);
        }
    }
    elsif ($alarmType eq 'end') {
        $log->debug('Alarm off to Domoticz: '. $alarmId);
        $idx = $alarms{$alarmId};
        $level = 'Off';
        if ((length $idx) && ($idx > 0)) {
            _setToDomoticz($client, $idx, $param, $cmd, $level);
        }
        if ((length $generalAlarm) && ($generalAlarm > 0)) {
            _setToDomoticz($client, $generalAlarm, $param, $cmd, $level);
        }
    }
    elsif ($alarmType eq 'snooze') {
        $log->debug('Snooze on to Domoticz: '. $alarmId);
        $idx = $snoozes{$alarmId};
        $level = 'On';
        if ((length $idx) && ($idx > 0)) {
            _setToDomoticz($client, $idx, $param, $cmd, $level);
        }
        if ((length $generalSnooze) && ($generalSnooze > 0)) {
            _setToDomoticz($client, $generalSnooze, $param, $cmd, $level);
        }
    }
    elsif ($alarmType eq 'snooze_end') {
        $log->debug('Snooze off to Domoticz: '. $alarmId);
        $idx = $snoozes{$alarmId};
        $level = 'Off';
        if ((length $idx) && ($idx > 0)) {
            _setToDomoticz($client, $idx, $param, $cmd, $level);
        }
        if ((length $generalSnooze) && ($generalSnooze > 0)) {
            _setToDomoticz($client, $generalSnooze, $param, $cmd, $level);
        }
    }
}

sub _manageMacroStringQueue {
    my $request = shift;

    if (!$request) {
        $requestProcessing = 0;
        $log->debug('Next request');
        $request = shift @requestsQueue;
    }

    if ($request) {
        if (!$requestProcessing) {
            $log->debug('Processing request');
            my $client = $request->client();
            
            if (defined $cachedResults{$client->id} && (time < $cachedResults{$client->id}[0])) {
                $log->debug('Using cached results');
                _macroStringResult($request, $cachedResults{$client->id}[1]);
            }
            else {        
                my $trendsurl = initPref($client) . 'type=devices&used=true';

                $request->setStatusProcessing();
                $log->debug('Ask devices to Domoticz: '. $trendsurl);  
                
                my $http = Slim::Networking::SimpleAsyncHTTP->new(
                    \&_getDevicesOnlyFromDomoticzCallback,
                    \&_getDevicesOnlyFromDomoticzErrorCallback, 
                    {
                            slimrequest  => $request,
                            cache    => 0, # optional, cache result of HTTP request
                    }
                );

                $requestProcessing = 1;
                $http->get($trendsurl);
            }
        }
        else {
            push @requestsQueue, $request;
            $request->setStatusProcessing();
            $log->debug('Already processing, waiting for end of previous request');
        }
    }
    else {
        $log->debug('Request queue empty');
    }
}

sub _macroSubFunc {
    my $replaceStr = shift;
    my $func = shift;
    my $funcArg = shift;
    my $result = eval {
        if ($func eq 'truncate') {
            my $dec = $funcArg + 0; 
            my $val = $replaceStr + 0.0;
            if ($dec > 0) {
                return sprintf('%.' . $dec . 'f', $val); 
            }
            else {
                return sprintf('%d', $val); 
            }
        }
        elsif ($func eq 'ceil') {
            return sprintf('%d', ceil($replaceStr + 0.0)); 
        }
        elsif ($func eq 'floor') {
            return sprintf('%d', floor($replaceStr + 0.0)); 
        }
        elsif ($func eq 'round') {
            my $dec = $funcArg + 0; 
            my $val = 5*10**(-1*($dec + 1));
            if (($replaceStr + 0.0) >= 0.0) {
                $val += $replaceStr + 0.0;
            }
            else {
                $val += $replaceStr + 0.0;
            }
            if ($dec > 0) {
                return sprintf('%.' . $dec . 'f', $val); 
            }
            else {
                return sprintf('%d', $val); 
            }
        }
        elsif ($func eq 'shorten') {
            return substr($replaceStr, 0, $funcArg + 0);
        }
        else {
            return $replaceStr;
        }
    };
    if ($@) {
        $log->error('Error while trying to eval macro function: [' . $@ . ']');
        return $replaceStr;
    }
    else {
        return $result;
    }
}

sub _macroCallNextMacro {
    my $request = shift;
    my $result = shift;
    
    $request->addResult('macroString', $result);
    $log->debug('Result: ' . $result);
    
    if (defined $funcptr && ref($funcptr) eq 'CODE') {
        $log->debug('Calling next function');
        $request->addParam('format', $result);        
        eval { &{$funcptr}($request) };

        # arrange for some useful logging if we fail
        if ($@) {
            $log->error('Error while trying to run function coderef: [' . $@ . ']');
            $request->setStatusBadDispatch();
            $request->dump('Request');
        }
    }
    else {
        $log->debug('Done');
        $request->setStatusDone();
    }    
}

sub _macroStringResult {
    my $request = shift;
    my $data = shift;
    my $format = $request->getParam('format');
#     $format = 'test ~i216~Type~shorten~2~ ~nMode absence~Status~°C';
    my $result = $format;
    
    if (defined $data) {
        $log->debug('Search in results for ' . $format);
        my @jsonElements = @{ $data };
        while ($format =~ /(~i([0-9]+?)~(\S+?)(~(\S+?))?(~(\S+?))?~)/g) {
            $log->debug('Got match idx');
            my $whole = $1;
            my $idx = $2 + 0;
            my $element = $3;
            my $func = $5;
            my $funcArg = $7;
            foreach my $f (@jsonElements) {
                if ($f->{'idx'} == $idx) {
                    $log->debug('Found element idx ' . $idx);
                    if (defined $f->{$element}) {
                        my $replaceStr = _macroSubFunc($f->{$element}, $func, $funcArg);
                        $log->debug('Will replace by: ' . $replaceStr);
                        $result =~ s/${whole}/${replaceStr}$1/;
                    }
                }
            }
        }
        while ($format =~ /(~n(.+?)~(\S+?)(~(\S+?))?(~(\S+?))?~)/g) {
            $log->debug('Got match name');
            my $whole = $1;
            my $name = $2;
            my $element = $3;
            my $func = $5;
            my $funcArg = $7;
            foreach my $f (@jsonElements) {
                if ($f->{'Name'} eq $name) {
                    $log->debug('Found element name ' . $name);
                    if (defined $f->{$element}) {
                        my $replaceStr = _macroSubFunc($f->{$element}, $func, $funcArg);
                        $log->debug('Will replace by: ' . $replaceStr);
                        $result =~ s/${whole}/${replaceStr}$1/;
                    }
                }
            }
        }
    }
    
    _macroCallNextMacro($request, $result);
    _manageMacroStringQueue(undef);
}

sub _getDevicesOnlyFromDomoticzCallback {
    my $http = shift;
    my $request = $http->params('slimrequest');
    my $client = $request->client();

    $log->debug('Got answer from Domoticz after get devices');
    
    my $content = $http->content();
    my $decoded = decode_json($content);
    my $results = undef;
    
    if ($decoded->{'result'}) {
        $results = $decoded->{'result'};
        $cachedResults{$client->id} = [time + CACHE_TIME, $results];
    }
    
    _macroStringResult($request, $results);
}

sub _getDevicesOnlyFromDomoticzErrorCallback {
    my $http = shift;
    my $request = $http->params('slimrequest');
    my @results;
    
    $log->error('No answer from Domoticz after get devices');
    
    _macroStringResult($request, undef);
}

sub macroString {
    my $request = shift;
    my $format = $request->getParam('format');
#     $format = 'test ~i216~Type~shorten~2~ ~nMode absence~Status~°C';

    $log->debug('Inside CLI request macroString for ' . $format . ' status ' . $request->getStatusText());
    
    # Check that there is a pattern for us
    if (
        ($format =~ m/~i[0-9]+?~\S+~/)
        || ($format =~ m/~n.+?~\S+~/)
    ) {
        _manageMacroStringQueue($request);
    }
    # No pattern, jump to next dispatched sdtMacroString
    else {
        $log->debug('No pattern for us');
        _macroCallNextMacro($request, $format);
    }
}

sub initPlugin {
    my $class = shift;

    if (main::WEBUI) {
        require Plugins::DomoticzControl::PlayerSettings;
        Plugins::DomoticzControl::PlayerSettings->new();
    }

    $class->SUPER::initPlugin();

                                                        #        |requires Client
                                                        #        |  |is a Query
                                                        #        |  |  |has Tags
                                                        #        |  |  |  |Function to call
                                                        #        C  Q  T  F
    $funcptr = Slim::Control::Request::addDispatch(['sdtMacroString'], [1, 1, 1, \&macroString]);
    Slim::Control::Request::addDispatch(['menuDomoticzDimmer'],[1, 0, 1, \&menuDomoticzDimmer]);
    Slim::Control::Request::addDispatch(['setToDomoticz'],[1, 0, 1, \&setToDomoticz]);
    Slim::Control::Request::addDispatch(['setToDomoticzTimer'],[1, 0, 1, \&setToDomoticzTimer]);
    Slim::Control::Request::addDispatch(['getFromDomoticz'],[1, 0, 1, \&getFromDomoticz]);

    my @menu = ({
        stringToken   => getDisplayName(),
        id     => 'pluginDomoticzControlmenu',
        'icon-id' => Plugins::DomoticzControl::Plugin->_pluginDataFor('icon'),
        weight => 50,
        actions => {
            go => {
                player => 0,
                cmd => ['getFromDomoticz'],
            }
        }
    });

#    Slim::Control::Jive::registerAppMenu(\@menu);
#    $class->addNonSNApp();
#    Slim::Control::Jive::registerPluginMenu(\@menu, 'extras');
    Slim::Control::Jive::registerPluginMenu(\@menu, 'home');
    
    # Subscribe to on/off
    Slim::Control::Request::subscribe(
            \&powerCallback,
            [['power']]
    );
    
    # Subscribe to alarms
    Slim::Control::Request::subscribe(
            \&setAlarmToDomoticz,
            [['alarm'],['sound', 'end', 'snooze', 'snooze_end']]
    );

    # Init pref when client connects
    Slim::Control::Request::subscribe(
        \&clientEvent,
        [['client'],['new','reconnect','disconnect']]
    );
}

sub shutdownPlugin {
    my $class = shift;
    Slim::Control::Request::unsubscribe(\&clientEvent);
    Slim::Control::Request::unsubscribe(\&setAlarmToDomoticz);
    Slim::Control::Request::unsubscribe(\&powerCallback);
    Slim::Control::Jive::deleteMenuItem('pluginDomoticzControlmenu');
}

1;

__END__
