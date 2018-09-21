Domoticz Control
================

This is a [Squeezebox](http://www.mysqueezebox.com) (Logitech Media Server) plugin for controlling [Domoticz](https://domoticz.com) devices from your Jive based player screen (Squeezebox radio, Squeezebox Touch, UE Smart Radio with squeezebox firmware).

The plugin can control ON/OFF, push, selector switches, dimmers, blinds and temperature setpoints.

Installation
------------

To install the plugin, add the repository URL http://domoticzcontrol.e-monsite.com/medias/files/repo.xml to your squeezebox plugin settings page then activate the plugin.

Usage
-----

1. For each player, go to the player settings page and choose Domoticz Control settings.

1. There you can configure URL access for Domoticz and filter for each player which control you want to get on the player screen.

1. You can also associate alarms and snoozes with Domoticz devices (On/Off commands only). This can be useful to activate Domoticz scripts through a virtual switch for instance.

1. You can associate a Domoticz device that will turn on and off at the same time as a player.

1. If you have Custom Clock, Custom Clock Helper and SuperDateTime (weather.com version 5.9.42 onwards), Domoticz Control can expose values based on devices state to Custom Clock Helper. The formatting is explained in Domoticz Control settings of the player settings page.

1. Domoticz control should appear in the Extra menu of your Jive based players.

License
-------

This project is licensed under the MIT license - see the [LICENSE](LICENSE) file for details
