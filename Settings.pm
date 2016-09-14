package Plugins::DomoticzControl::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Alarm;

my $pluginprefs = preferences('plugin.DomoticzControl');
my $serverprefs = preferences('server');

my @prefNames = ('address', 'port', 'https', 'user', 'password', 'onlyFavorites', 'onlyUnproctected', 'dimmerAsOnOff', 'blindsPercentageAsOnOff', 'hideScenes', 'hideOnOff', 'hideDimmers', 'hideBlinds', 'filterByName', 'filterByDescription', 'filterByPlanId');

sub needsClient {
    return 1;
}

sub name {
    return Slim::Web::HTTP::CSRF->protectName('PLUGIN_DOMOTICZCONTROL_BASIC_SETTINGS');
}

sub page {
    return Slim::Web::HTTP::CSRF->protectURI('plugins/DomoticzControl/settings/basic.html');
}

sub prefs {
    my ($class, $client) = @_;

    return ($pluginprefs->client($client), @prefNames);
}

sub handler {
    my ($class, $client, $paramRef) = @_;

    my ($prefsClass, @prefs) = $class->prefs($client);
    my @alarmsObj = Slim::Utils::Alarm->getAlarms($client);
    my %savedAlarms;
    my %savedSnoozes;
#    Data::Dump::dump(%domoAlarmsId);
#    Data::Dump::dump(%domoSnoozesId);
    
#    $Template::Stash::PRIVATE = undef;

    if ($paramRef->{'saveSettings'}) {
        foreach my $alarm (@alarmsObj) {
            my $id = $alarm->id();
            $savedAlarms{$id} = $paramRef->{'alarmId' . $id};
            $savedSnoozes{$id} = $paramRef->{'snoozeId' . $id};
	}
        $prefsClass->set('alarms', \%savedAlarms);
        $prefsClass->set('snoozes', \%savedSnoozes);
    }
    else {
        my $prefsAlarms = $prefsClass->get('alarms');
	my $prefsSnoozes = $prefsClass->get('snoozes');
        if ($prefsAlarms) {
            %savedAlarms = %{ $prefsAlarms };
        }
        if ($prefsSnoozes) {
            %savedSnoozes = %{ $prefsSnoozes };
        }
    }
#    Data::Dump::dump(%savedAlarms);
#    Data::Dump::dump(%savedSnoozes);

    my @alarms;
    foreach my $alarm (@alarmsObj) {
        my $id = $alarm->id();
        my %rec;
        $rec{"id"} = $id;
        $rec{"alarm"} = $savedAlarms{$id};
        $rec{"snooze"} = $savedSnoozes{$id};
        push @alarms, \%rec;
    }

    $paramRef->{'alarms'} = \@alarms;
    
#    Data::Dump::dump(\@alarms);
  
    return $class->SUPER::handler($client, $paramRef);    
}

1;

__END__
