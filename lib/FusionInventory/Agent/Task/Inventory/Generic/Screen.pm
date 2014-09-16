package FusionInventory::Agent::Task::Inventory::Generic::Screen;

use strict;
use warnings;

use English qw(-no_match_vars);
use MIME::Base64;
use UNIVERSAL::require;

use File::Find;
use FusionInventory::Agent::Tools;
use FusionInventory::Agent::Tools::Generic;

sub isEnabled {
    my (%params) = @_;
    return 0 if $params{no_category}->{monitor};
    return 1;
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};

    foreach my $screen (_getScreens(
        logger  => $params{logger},
    )) {

        if ($screen->{edid}) {
            my $info = _getEdidInfo(
                edid    => $screen->{edid},
                logger  => $params{logger},
                datadir => $params{datadir},
            );
            $screen->{CAPTION}      = $info->{CAPTION};
            $screen->{DESCRIPTION}  = $info->{DESCRIPTION};
            $screen->{MANUFACTURER} = $info->{MANUFACTURER};
            $screen->{SERIAL}       = $info->{SERIAL};

            $screen->{BASE64} = encode_base64($screen->{edid});
        }

        if (defined($screen->{edid})) {
            delete $screen->{edid};
        }

        $inventory->addEntry(
            section => 'MONITORS',
            entry   => $screen
        );
    }
}

sub _getEdidInfo {
    my (%params) = @_;

    Parse::EDID->require();
    if ($EVAL_ERROR) {
        $params{logger}->debug(
            "Parse::EDID Perl module not available, unable to parse EDID data"
        ) if $params{logger};
        return;
    }

    my $edid = Parse::EDID::parse_edid($params{edid});
    if (my $error = Parse::EDID::check_parsed_edid($edid)) {
        $params{logger}->debug("bad edid: $error") if $params{logger};
        return;
    }

    my $info = {
        CAPTION      => $edid->{monitor_name},
        DESCRIPTION  => $edid->{week} . "/" . $edid->{year},
        MANUFACTURER => getEDIDVendor(
                            id      => $edid->{manufacturer_name},
                            datadir => $params{datadir}
                        ) || $edid->{manufacturer_name}
    };

    # they are two different serial numbers in EDID
    # - a mandatory 4 bytes numeric value
    # - an optional 13 bytes ASCII value
    # we use the ASCII value if present, the numeric value as an hex string
    # unless for a few list of known exceptions deserving specific handling
    # References:
    # http://forge.fusioninventory.org/issues/1607
    # http://forge.fusioninventory.org/issues/1614
    if (
        $edid->{EISA_ID} &&
        $edid->{EISA_ID} =~ /^ACR(0018|0020|0024|00A8|7883|ad49|adaf)$/
    ) {
        $info->{SERIAL} =
            substr($edid->{serial_number2}->[0], 0, 8) .
            sprintf("%08x", $edid->{serial_number})    .
            substr($edid->{serial_number2}->[0], 8, 4) ;
    } elsif (
        $edid->{EISA_ID} &&
        $edid->{EISA_ID} eq 'GSM4b21'
    ) {
        # split serial in two parts
        my ($high, $low) = $edid->{serial_number} =~ /(\d+) (\d\d\d)$/x;

        # translate the first part using a custom alphabet
        my @alphabet = split(//, "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ");
        my $base     = scalar @alphabet;

        $info->{SERIAL} =
            $alphabet[$high / $base] . $alphabet[$high % $base] .
            $low;
    } else {
        $info->{SERIAL} = $edid->{serial_number2} ?
            $edid->{serial_number2}->[0]           :
            sprintf("%08x", $edid->{serial_number});
    }

    return $info;
}

sub _getScreensFromWindows {
    my (%params) = @_;

    FusionInventory::Agent::Tools::Win32->use();

    my @screens;

    # Vista and upper, able to get the second screen
    foreach my $object (getWMIObjects(
        moniker    => 'winmgmts:{impersonationLevel=impersonate,authenticationLevel=Pkt}!//./root/wmi',
        class      => 'WMIMonitorID',
        properties => [ qw/InstanceName/ ]
    )) {
        next unless $object->{InstanceName};

        $object->{InstanceName} =~ s/_\d+//;
        push @screens, {
            id => $object->{InstanceName}
        };
    }

    # The generic Win32_DesktopMonitor class, the second screen will be missing
    foreach my $object (getWMIObjects(
        class => 'Win32_DesktopMonitor',
        properties => [ qw/
            Caption MonitorManufacturer MonitorType PNPDeviceID Availability
        / ]
    )) {
        next unless $object->{Availability};
        next unless $object->{PNPDeviceID};
        next unless $object->{Availability} == 3;

        push @screens, {
            id           => $object->{PNPDeviceID},
            NAME         => $object->{Caption},
            TYPE         => $object->{MonitorType},
            MANUFACTURER => $object->{MonitorManufacturer},
            CAPTION      => $object->{Caption}
        };
    }

    foreach my $screen (@screens) {
        next unless $screen->{id};
        $screen->{edid} = getRegistryValue(
            path => "HKEY_LOCAL_MACHINE/SYSTEM/CurrentControlSet/Enum/$screen->{id}/Device Parameters/EDID",
            logger => $params{logger}
        ) || '';
        $screen->{edid} =~ s/^\s+$//;
        delete $screen->{id};
    }

    return @screens;
}

sub _getScreensFromUnix {
    my (%params) = @_;

    my $logger = $params{logger};
    $logger->debug("trying to get EDID data...");

    if (-d '/sys/devices') {
        my @screens;
        my $wanted = sub {
            return unless $_ eq 'edid';
            return unless -e $File::Find::name;
            my $edid = getAllLines(file => $File::Find::name);
            push @screens, { edid => $edid } if $edid;
        };

        no warnings 'File::Find';
        File::Find::find($wanted, '/sys/devices');

        _log_result($logger, 'reading /sys/devices content', @screens);

        return @screens if @screens;
    } else {
        _log_unavailability($logger, '/sys/devices directory');
    }

    if (canRun('monitor-get-edid-using-vbe')) {
        my $edid = getAllLines(command => 'monitor-get-edid-using-vbe');
        _log_result($logger, 'running monitor-get-edid-using-vbe command', $edid);
        return { edid => $edid } if $edid;
    } else {
        _log_unavailability($logger, 'monitor-get-edid-using-vbe command');
    }

    if (canRun('monitor-get-edid')) {
        my $edid = getAllLines(command => 'monitor-get-edid');
        _log_result($logger, 'running monitor-get-edid command', $edid);
        return { edid => $edid } if $edid;
    } else {
        _log_unavailability($logger, 'monitor-get-edid command');
    }

    if (canRun('get-edid')) {
        my $edid;
        foreach (1..5) { # Sometime get-edid return an empty string...
            $edid = getFirstLine(command => 'get-edid');
            last if $edid;
        }
        _log_result($logger, 'running get-edid command', $edid);
        return { edid => $edid } if $edid;
    } else {
        _log_unavailability($logger, 'get-edid command');
    }

    return;
}

sub _getScreens {
    return $OSNAME eq 'MSWin32' ?
        _getScreensFromWindows(@_) : _getScreensFromUnix(@_);
}

sub _log_result {
    my ($logger, $message, $result) = @_;
    return unless $logger;
    $logger->debug(
        sprintf('%s: %s', $message, $result ? 'success' : 'no result')
    );
}

sub _log_unavailability {
    my ($logger, $message) = @_;
    return unless $logger;
    $logger->debug(
        sprintf('%s not available', $message)
    );
}

1;
