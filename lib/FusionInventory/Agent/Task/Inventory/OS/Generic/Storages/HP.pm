package FusionInventory::Agent::Task::Inventory::OS::Generic::Storages::HP;

use FusionInventory::Agent::Task::Inventory::OS::Linux::Storages;
# Tested on 2.6.* kernels
#
# Cards tested :
#
# Smart Array E200
#
# HP Array Configuration Utility CLI 7.85-18.0

use strict;

sub getHpacuacliFromWinRegistry {

    return unless eval ("use Win32::TieRegistry ( Delimiter=>\"/\",".
"ArrayValues=>0 ); 1;");
    my $machKey= $Win32::TieRegistry::Registry->Open( "LMachine", {Access=>Win32::TieRegistry::KEY_READ(),Delimiter=>"/"} );

    my $uninstallValues =
        $machKey->{'SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall/HA CUCLI'};
    use Data::Dumper;
    print Dumper($uninstallValues);
    my $uninstallString = $uninstallValues->{'/UninstallString'};
    print Dumper($uninstallString);

    my $hpacuacliPath;
    if ($uninstallString =~ /(.*\\)hpuninst\.exe/) {
        $hpacuacliPath = $1.'bin\\hpacucli.exe';
        return $hpacuacliPath if -f $hpacuacliPath;
        print "grr".$hpacuacliPath."Doesn't eixiste\n";
    }

    print "hpacuacli not found\n";
    return;
}

sub isInventoryEnabled {

    my $ret;

    my $hpacuacliPath = can_run("hpacucli")?"hpacucli":getHpacuacliFromWinRegistry();
# Do we have hpacucli ?
    if ($hpacuacliPath) {
        foreach (`$hpacuacliPath ctrl all show 2> /dev/null`) {
            if (/.*Slot\s(\d*).*/) {
                $ret = 1;
                last;
            }
        }
    }
    return $ret;

}

sub doInventory {


    my $params = shift;
    my $inventory = $params->{inventory};
    my $logger = $params->{logger};

    my ($pd, $serialnumber, $model, $capacity, $firmware, $description, $media, $manufacturer);

    my $hpacuacliPath = can_run("hpacucli")?"hpacucli":getHpacuacliFromWinRegistry();
    foreach (`$hpacuacliPath ctrl all show 2> /dev/null`) {

# Example output :
#    
# Smart Array E200 in Slot 2    (sn: PA6C90K9SUH1ZA)

        if (/.*Slot\s(\d*).*/) {

            my $slot = $1;

            foreach (`$hpacuacliPath ctrl slot=$slot pd all show 2> /dev/null`) {

# Example output :
                #
# Smart Array E200 in Slot 2
                #
#   array A
                #
#      physicaldrive 2I:1:1 (port 2I:box 1:bay 1, SATA, 74.3 GB, OK)
#      physicaldrive 2I:1:2 (port 2I:box 1:bay 2, SATA, 74.3 GB, OK)

                if (/.*physicaldrive\s(\S*)/) {
                    my $pd = $1;
                    foreach (`$hpacuacliPath ctrl slot=$slot pd $pd show 2> /dev/null`) {

# Example output :
#  
# Smart Array E200 in Slot 2
                        #
#   array A
                        #
#      physicaldrive 1:1
#         Port: 2I
#         Box: 1
#         Bay: 1
#         Status: OK
#         Drive Type: Data Drive
#         Interface Type: SATA
#         Size: 74.3 GB
#         Firmware Revision: 21.07QR4
#         Serial Number:      WD-WMANS1732855
#         Model: ATA     WDC WD740ADFD-00
#         SATA NCQ Capable: False
#         PHY Count: 1        

                        $model = $1 if /.*Model:\s(.*)/;
                        $description = $1 if /.*Interface Type:\s(.*)/;
                        $media = $1 if /.*Drive Type:\s(.*)/;
                        $capacity = 1000*$1 if /.*Size:\s(.*)/;
                        $serialnumber = $1 if /.*Serial Number:\s(.*)/;
                        $firmware = $1 if /.*Firmware Revision:\s(.*)/;
                    }
                    $serialnumber =~ s/^\s+//;
                    $model =~ s/^ATA\s+//; # ex: ATA     WDC WD740ADFD-00
                    $model =~ s/\s+/ /;
                    $manufacturer = FusionInventory::Agent::Task::Inventory::OS::Linux::Storages::getManufacturer($model);
                    if ($media eq 'Data Drive') {
                        $media = 'disk';
                    }

                    $logger->debug("HP: N/A, $manufacturer, $model, $description, $media, $capacity, $serialnumber, $firmware");

                    $inventory->addStorages({
                            NAME => $model,
                            MANUFACTURER => $manufacturer,
                            MODEL => $model,
                            DESCRIPTION => $description,
                            TYPE => $media,
                            DISKSIZE => $capacity,
                            SERIALNUMBER => $serialnumber,
                            FIRMWARE => $firmware
                        }); 
                }
            }
        }
    }
}

1;
