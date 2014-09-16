package FusionInventory::Agent::Inventory;

use strict;
use warnings;

use Config;
use English qw(-no_match_vars);

use FusionInventory::Agent::Tools;

my %fields = (
    BIOS             => [ qw/SMODEL SMANUFACTURER SSN BDATE BVERSION
                             BMANUFACTURER MMANUFACTURER MSN MMODEL ASSETTAG
                             ENCLOSURESERIAL BIOSSERIAL
                             TYPE SKUNUMBER/ ],
    HARDWARE         => [ qw/USERID OSVERSION PROCESSORN OSCOMMENTS CHECKSUM
                             PROCESSORT NAME PROCESSORS SWAP ETIME TYPE OSNAME
                             IPADDR WORKGROUP DESCRIPTION MEMORY UUID VMID DNS
                             LASTLOGGEDUSER USERDOMAIN DATELASTLOGGEDUSER
                             DEFAULTGATEWAY VMSYSTEM WINOWNER WINPRODID
                             WINPRODKEY WINCOMPANY WINLANG CHASSIS_TYPE VMID
                             VMNAME VMHOSTSERIAL/ ],
    OPERATINGSYSTEM  => [ qw/KERNEL_NAME KERNEL_VERSION NAME VERSION FULL_NAME
                             SERVICE_PACK INSTALL_DATE FQDN DNS_DOMAIN
                             SSH_KEY ARCH BOOT_TIME/ ],
    ACCESSLOG        => [ qw/USERID LOGDATE/ ],

    ANTIVIRUS        => [ qw/COMPANY ENABLED GUID NAME UPTODATE VERSION/ ],
    BATTERIES        => [ qw/CAPACITY CHEMISTRY DATE NAME SERIAL MANUFACTURER
                             VOLTAGE/ ],
    CONTROLLERS      => [ qw/CAPTION DRIVER NAME MANUFACTURER PCICLASS VENDORID
                             PRODUCTID PCISUBSYSTEMID PCISLOT TYPE REV/ ],
    CPUS             => [ qw/CACHE CORE DESCRIPTION MANUFACTURER NAME THREAD
                             SERIAL STEPPING FAMILYNAME FAMILYNUMBER MODEL
                             SPEED ID EXTERNAL_CLOCK ARCH/ ],
    DRIVES           => [ qw/CREATEDATE DESCRIPTION FREE FILESYSTEM LABEL
                             LETTER SERIAL SYSTEMDRIVE TOTAL TYPE VOLUMN/ ],
    ENVS             => [ qw/KEY VAL/ ],
    INPUTS           => [ qw/NAME MANUFACTURER CAPTION DESCRIPTION INTERFACE
                             LAYOUT POINTINGTYPE TYPE/ ],
    LICENSEINFOS     => [ qw/NAME FULLNAME KEY COMPONENTS TRIAL UPDATE OEM
                             ACTIVATION_DATE PRODUCTID/ ],
    LOCAL_GROUPS     => [ qw/ID MEMBER NAME/ ],
    LOCAL_USERS      => [ qw/HOME ID LOGIN NAME SHELL/ ],
    LOGICAL_VOLUMES  => [ qw/LV_NAME VG_NAME ATTR SIZE LV_UUID SEG_COUNT
                             VG_UUID/ ],
    MEMORIES         => [ qw/CAPACITY CAPTION FORMFACTOR REMOVABLE PURPOSE
                             SPEED SERIALNUMBER TYPE DESCRIPTION NUMSLOTS
                             MEMORYCORRECTION MANUFACTURER/ ],
    MODEMS           => [ qw/DESCRIPTION NAME/ ],
    MONITORS         => [ qw/BASE64 CAPTION DESCRIPTION MANUFACTURER SERIAL
                             UUENCODE/ ],
    NETWORKS         => [ qw/DESCRIPTION MANUFACTURER MODEL MANAGEMENT TYPE
                             VIRTUALDEV MACADDR WWN DRIVER FIRMWARE PCIID
                             PCISLOT PNPDEVICEID MTU SPEED STATUS SLAVES BASE
                             IPADDRESS IPSUBNET IPMASK IPDHCP IPGATEWAY
                             IPADDRESS6 IPSUBNET6 IPMASK6 WIFI_BSSID WIFI_SSID
                             WIFI_MODE WIFI_VERSION/ ],
    PHYSICAL_VOLUMES => [ qw/DEVICE PV_PE_COUNT PV_UUID FORMAT ATTR
                             SIZE FREE PE_SIZE VG_UUID/ ],
    PORTS            => [ qw/CAPTION DESCRIPTION NAME TYPE/ ],
    PRINTERS         => [ qw/COMMENT DESCRIPTION DRIVER NAME NETWORK PORT
                             RESOLUTION SHARED STATUS ERRSTATUS SERVERNAME
                             SHARENAME PRINTPROCESSOR SERIAL/ ],
    PROCESSES        => [ qw/USER PID CPUUSAGE MEM VIRTUALMEMORY TTY STARTED
                             CMD/ ],
    REGISTRY         => [ qw/NAME REGVALUE HIVE/ ],
    RUDDER           => [ qw/AGENT UUID HOSTNAME/ ],
    SLOTS            => [ qw/DESCRIPTION DESIGNATION NAME STATUS/ ],
    SOFTWARES        => [ qw/COMMENTS FILESIZE FOLDER FROM HELPLINK INSTALLDATE
                            NAME NO_REMOVE RELEASE_TYPE PUBLISHER
                            UNINSTALL_STRING URL_INFO_ABOUT VERSION
                            VERSION_MINOR VERSION_MAJOR GUID ARCH USERNAME
                            USERID/ ],
    SOUNDS           => [ qw/CAPTION DESCRIPTION MANUFACTURER NAME/ ],
    STORAGES         => [ qw/DESCRIPTION DISKSIZE INTERFACE MANUFACTURER MODEL
                            NAME TYPE SERIAL SERIALNUMBER FIRMWARE SCSI_COID
                            SCSI_CHID SCSI_UNID SCSI_LUN WWN/ ],
    VIDEOS           => [ qw/CHIPSET MEMORY NAME RESOLUTION PCISLOT/ ],
    USBDEVICES       => [ qw/VENDORID PRODUCTID MANUFACTURER CAPTION SERIAL
                            CLASS SUBCLASS NAME/ ],
    USERS            => [ qw/LOGIN DOMAIN/ ],
    VIRTUALMACHINES  => [ qw/MEMORY NAME UUID STATUS SUBSYSTEM VMTYPE VCPU
                             VMID MAC COMMENT OWNER SERIAL/ ],
    VOLUME_GROUPS    => [ qw/VG_NAME PV_COUNT LV_COUNT ATTR SIZE FREE VG_UUID
                             VG_EXTENT_SIZE/ ],
);

my %checks = (
    STORAGES => {
        INTERFACE => qr/^(SCSI|HDC|IDE|USB|1394|Serial-ATA|SAS)$/
    },
    VIRTUALMACHINES => {
        STATUS => qr/^(running|blocked|idle|paused|shutdown|crashed|dying|off)$/
    },
    SLOTS => {
        STATUS => qr/^(free|used)$/
    },
    NETWORKS => {
        TYPE => qr/^(ethernet|wifi|aggregate|alias|dialup|loopback|bridge)$/
    },
    CPUS => {
        ARCH => qr/^(MIPS|MIPS64|Alpha|SPARC|SPARC64|m68k|i386|x86_64|PowerPC|PowerPC64|ARM|AArch64)$/
    }
);

# convert fields list into fields hashes, for fast lookup
foreach my $section (keys %fields) {
    $fields{$section} = { map { $_ => 1 } @{$fields{$section}} };
}

sub new {
    my ($class, %params) = @_;

    my $self = {
        logger         => $params{logger},
        fields         => \%fields,
        content        => {
            HARDWARE => {
                ARCHNAME => $Config{archname},
                VMSYSTEM => "Physical" # Default value
            },
            VERSIONCLIENT => $FusionInventory::Agent::AGENT_STRING
        }
    };
    bless $self, $class;

    $self->setTag($params{tag});

    return $self;
}

sub getContent {
    my ($self) = @_;

    return $self->{content};
}

sub mergeContent {
    my ($self, $content) = @_;

    die "no content" unless $content;

    foreach my $section (keys %$content) {
        if (ref $content->{$section} eq 'ARRAY') {
            # a list of entry
            foreach my $entry (@{$content->{$section}}) {
                $self->addEntry(section => $section, entry => $entry);
            }
        } else {
            # single entry
            SWITCH: {
                if ($section eq 'HARDWARE') {
                    $self->setHardware($content->{$section});
                    last SWITCH;
                }
                if ($section eq 'BIOS') {
                    $self->setBios($content->{$section});
                    last SWITCH;
                }
                if ($section eq 'ACCESSLOG') {
                    $self->setAccessLog($content->{$section});
                    last SWITCH;
                }
                $self->addEntry(
                    section => $section, entry => $content->{$section}
                );
            }
        }
    }
}

sub addEntry {
    my ($self, %params) = @_;

    my $entry = $params{entry};
    die "no entry" unless $entry;

    my $section = $params{section};
    my $fields = $fields{$section};
    my $checks = $checks{$section};
    die "unknown section $section" unless $fields;

    foreach my $field (keys %$entry) {
        if (!$fields->{$field}) {
            # unvalid field, log error and remove
            $self->{logger}->debug("unknown field $field for section $section");
            delete $entry->{$field};
            next;
        }
        if (!defined $entry->{$field}) {
            # undefined value, remove
            delete $entry->{$field};
            next;
        }
        # sanitize value
        my $value = getSanitizedString($entry->{$field});
        # check value if appliable
        if ($checks->{$field}) {
            $self->{logger}->debug(
                "invalid value $value for field $field for section $section"
            ) unless $value =~ $checks->{$field};
        }
        $entry->{$field} = $value;
    }

    # avoid duplicate entries
    if ($params{noDuplicated}) {
        my $md5 = md5_base64(Dumper($entry));
        return if $self->{seen}->{$section}->{$md5};
        $self->{seen}->{$section}->{$md5} = 1;
    }

    if ($section eq 'STORAGES') {
        $entry->{SERIALNUMBER} = $entry->{SERIAL} if !$entry->{SERIALNUMBER}
    }

    push @{$self->{content}{$section}}, $entry;
}

sub computeLegacyValues {
    my ($self) = @_;

    # CPU-related values
    my $cpus = $self->{content}->{CPUS};
    if ($cpus) {
        my $cpu = $cpus->[0];

        $self->setHardware({
            PROCESSORN => scalar @$cpus,
            PROCESSORS => $cpu->{SPEED},
            PROCESSORT => $cpu->{NAME},
        });
    }

    # network related values
    my $interfaces = $self->{content}->{NETWORKS};
    if ($interfaces) {
        my @ip_addresses =
            grep { ! /^127/ }
            grep { $_ }
            map { $_->{IPADDRESS} }
            @$interfaces;

        $self->setHardware({
            IPADDR => join('/', @ip_addresses),
        });
    }

    # user-related values
    my $users = $self->{content}->{USERS};
    if ($users) {
        my $user = $users->[-1];

        my ($domain, $id);
        if ($user->{LOGIN} =~ /(\S+)\\(\S+)/) {
            # Windows fully qualified username: domain\user
            $domain = $1;
            $id = $2;
        } else {
            # simple username: user
            $id = $user->{LOGIN};
        }

        $self->setHardware({
            USERID     => $id,
            USERDOMAIN => $domain,
        });
    }
}

sub setHardware {
    my ($self, $args) = @_;

    foreach my $field (keys %$args) {
        if (!$fields{HARDWARE}->{$field}) {
            $self->{logger}->debug("unknown field $field for section HARDWARE");
            next
        }

        # Do not overwrite existing value with undef
        next unless $args->{$field};

        $self->{content}->{HARDWARE}->{$field} =
            getSanitizedString($args->{$field});
    }
}

sub setOperatingSystem {
    my ($self, $args) = @_;

    foreach my $field (keys %$args) {
        if (!$fields{OPERATINGSYSTEM}->{$field}) {
            $self->{logger}->debug(
                "unknown field $field for section OPERATINGSYSTEM"
            );
            next
        }
        $self->{content}->{OPERATINGSYSTEM}->{$field} =
            getSanitizedString($args->{$field});
    }
}

sub setBios {
    my ($self, $args) = @_;

    foreach my $field (keys %$args) {
        if (!$fields{BIOS}->{$field}) {
            $self->{logger}->debug("unknown field $field for section BIOS");
            next
        }

        $self->{content}->{BIOS}->{$field} =
            getSanitizedString($args->{$field});
    }
}

sub setAccessLog {
    my ($self, $args) = @_;

    foreach my $field (keys %$args) {
        if (!$fields{ACCESSLOG}->{$field}) {
            $self->{logger}->debug(
                "unknown field $field for section ACCESSLOG"
            );
            next
        }

        $self->{content}->{ACCESSLOG}->{$field} =
            getSanitizedString($args->{$field});
    }
}

sub setTag {
    my ($self, $tag) = @_;

    return unless $tag;

    $self->{content}{ACCOUNTINFO} = [{
        KEYNAME  => "TAG",
        KEYVALUE => $tag
    }];

}

sub computeChecksum {
    my ($self) = @_;

    my %mask = (
        HARDWARE      => 1,
        BIOS          => 2,
        MEMORIES      => 4,
        SLOTS         => 8,
        REGISTRY      => 16,
        CONTROLLERS   => 32,
        MONITORS      => 64,
        PORTS         => 128,
        STORAGES      => 256,
        DRIVES        => 512,
        INPUT         => 1024,
        MODEMS        => 2048,
        NETWORKS      => 4096,
        PRINTERS      => 8192,
        SOUNDS        => 16384,
        VIDEOS        => 32768,
        SOFTWARES     => 65536,
    );

    # compute maximal checksum, for OCS compatibility
    my $checksum = 0;
    foreach my $section (keys %mask) {
        $checksum |= $mask{$section}; ## no critic (ProhibitBitwise)
    }

    $self->setHardware({CHECKSUM => $checksum});
}

1;
__END__

=head1 NAME

FusionInventory::Agent::Inventory - Inventory data structure

=head1 DESCRIPTION

This is a data structure corresponding to an hardware and software inventory.

=head1 METHODS

=head2 new(%params)

The constructor. The following parameters are allowed, as keys of the
%params hash:

=over

=item I<logger>

a logger object

=item I<statedir>

a path to a writable directory containing the last serialized inventory

=item I<tag>

an arbitrary label, used for server-side filtering

=back

=head2 getContent()

Get content attribute.

=head2 mergeContent($content)

Merge content to the inventory.

=head2 addEntry(%params)

Add a new entry to the inventory. The following parameters are allowed, as keys
of the %params hash:

=over

=item I<section>

the entry section (mandatory)

=item I<entry>

the entry (mandatory)

=item I<noDuplicated>

ignore entry if already present

=back

=head2 setTag($tag)

Set inventory tag, an arbitrary label used for filtering on server side.

=head2 setHardware()

Save global information regarding the machine.

=head2 setOperatingSystem()

Operating System information.

=head2 setBios()

Set BIOS information.

=head2 setAccessLog()

What is that for? :)

=head2 computeChecksum()

Compute the inventory checksum. This information is used by the server to
know which parts of the inventory have changed since the last one.

=head2 computeLegacyValues()

Compute the inventory global values, meaning values in hardware section such as
CPU number, speed and model, computed from other values, but needed for OCS
compatibility.

=head1 DATA MODEL

This section presents the various entry types, with their attributes. The names
correspond to the historical OCS format.

=head2 BIOS

=over

=item SMODEL

System model

=item SMANUFACTURER

System manufacturer

=item SSN

System Serial number

=item BDATE

BIOS release date in the Month/Day/Year format (e.g: 09/27/2010)

=item BVERSION

The BIOS revision

=item BMANUFACTURER

BIOS manufacturer

=item MMANUFACTURER

Motherboard Manufacturer

=item MSN

Motherboard Serial

=item MMODEL

Motherboard model

=item ASSETTAG

=item ENCLOSURESERIAL

=item BIOSSERIAL

The optional asset tag for this machine.

=item TYPE

depcreated, replace by HARDWARE/CHASSIS_TYPE

=back

=head2 CONTROLLERS

=over

=item CAPTION

Windows CAPTION field or subsystem Name from the pci.ids table

=item DRIVER

=item NAME

The device name, the on from the PCIIDs DB

=item MANUFACTURER

The manifacturer name, the on from the PCIIDs DB

=item PCICLASS

The PCI class ID

=item PCIID

The PCI ID, e.g: 8086:2a40 (only for PCI device)

=item PCISUBSYSTEMID

The PCI subsystem ID, e.g: 8086:2a40 (only for PCI device)

=item PCISLOT

The PCI slot, e.g: 00:02.1 (only for PCI device)

=item TYPE

The controller revision, e.g: rev 02. This field may be renamed
in the future.

=item REV

Revision of the device in the XX format (e.g: 04)

=back

=head2 MEMORIES

=over

=item CAPACITY

=item CAPTION

E.g: Physical Memory

=item DESCRIPTION

=item FORMFACTOR

Only available on Windows, See Win32_PhysicalMemory documentation on MSDN.

=item REMOVABLE

=item PURPOSE

Only avalaible on Windows, See Win32_PhysicalMemory documentation on MSDN.

=item SPEED

In Mhz, e.g: 800

=item TYPE

=item NUMSLOTS

Eg. 2, start at 1, not 0

=item SERIALNUMBER

=back

=head2 CPUS

=over

=item ARCH

The CPU architecture

=item CACHESIZE

The total CPU cache size in KB. e.g: 3072

=item CORE

Number of core.

=item DESCRIPTION

=item MANUFACTURER

AMD/Intel/Transmeta/Cyrix/VIA/Sun Microsystems//Fujitsu

=item NAME

The name of the CPU, e.g: Intel(R) Core(TM)2 Duo CPU     P8600  @ 2.40GHz

=item THREAD

Number of thread per core.

=item SERIAL

Serial number

=item SPEED

Frequency in MHz

=item ID

The CPU ID: http://en.wikipedia.org/wiki/CPUID

=item STEPPING

Stepping value (Contained in CPUID)

=item MODEL

Model value (Contained in CPUID)

=item FAMILYNUMBER

Family value (Contained in CPUID)

=item FAMILYNAME

Family Name

=back

=head2 DRIVES

Drive is actually a filesystem. Virtual filesystem like /proc or /sys are ignored.

=over

=item CREATEDATE

Date of creation of the filesystem in DD/MM/YYYY format.

=item DESCRIPTION

=item FREE

Free space (MB)

=item FILESYSTEM

File system name. e.g: ext3

=item LABEL

Name of the partition given by the user.

=item LETTER

Windows driver letter. Windows only

=item SERIAL

Partition serial number or UUID

=item SYSTEMDRIVE

Boolean. Is this the system partition?

=item TOTAL

Total space available (MB)

=item TYPE

The mount point on UNIX.

=item VOLUMN

System name of the partition (e.g: /dev/sda1 or server:/directory for NFS)

=back

=head2 HARDWARE

=over

=item USERID

The current user list, '/' is the delimiter. This field is deprecated, you
should use the USERS section instead.

=item OSVERSION

Version number of the operating system. This field will be deprecated in the
future, please use OPERATINGSYSTEM/VERSION or OPERATINGSYSTEM/KERNEL_VERSION
instead.

=item PROCESSORN

=item OSCOMMENTS

Service Pack on Windows, kernel build date on Linux

=item CHECKSUM

Deprecated, OCS only.

=item PROCESSORT

Deprecated, OCS only.

=item NAME

=item PROCESSORS

The processor speed in MHz, this field is deprecated, see CPUS instead.

=item SWAP

The swap space in MB.

=item ETIME

The time needed to run the inventory on the agent side.

=item TYPE

=item OSNAME

Full name of the operating system as reported by itself. This field will be
deprecated in the future, please use OPERATINGSYSTEM/NAME or
OPERATINGSYSTEM/FULL_NAME instead.

=item IPADDR

=item WORKGROUP

=item DESCRIPTION

Computer description (Windows only so far)

=item MEMORY

Total system memory in MB

=item UUID

=item DNS

=item LASTLOGGEDUSER

The login of the last logged user.

=item USERDOMAIN

This field is deprecated, you should use the USERS section instead.

=item DATELASTLOGGEDUSER

=item DEFAULTGATEWAY

=item VMSYSTEM

The virtualization technology used if the machine is a virtual machine.

Can be:

=over 5

=item Physical: (default)

=item Xen

=item VirtualBox

=item Virtual Machine: Generic if it's not possible to correctly identify the solution

=item VMware: ESX, ESXi, server, etc

=item QEMU

=item SolarisZone

=item VServer

=item OpenVZ

=item BSDJail

=item Parallels

=item Hyper-V

=item AIX_LPAR

=back

=item VMID

The ID of the Virtual machine on the hypervisor (VM only).

=item VMNAME

The name of the Virtual machine on the hypervisor (VM only).

=item WINOWNER

=item WINPRODID

=item WINPRODKEY

=item WINCOMPANY

=item WINLANG

Language code of the Windows

=item CHASSIS_TYPE

The computer chassis format (e.g: Notebook, Laptop, Server, etc)

=item ARCHNAME

Architecture of the perl binary used to call the agent, MSWin32-x86-multi-thread.

=back

=head2 OPERATINGSYSTEM

=over

=item KERNEL_NAME

The name of the kernel used by this operating system, e.g freebsd, linux, hpux,
win32, etc (linux for android).

=item KERNEL_VERSION

Version of the operating system's kernel, e.g 2.6.32 for Linux, 5.2.x.y on
Windows Server 2003, etc.

=item NAME

Name of the Operating System ("Distributor ID" in LSB terms), e.g Debian,
Ubuntu, CentOS, SUSE LINUX, Windows, MacOSX, FreeBSD, AIX, Android, etc.

=item VERSION

Version of the operating system distribution ("Release" in LSB terms), e.g 11.04
on Ubuntu natty, 5.0.8 on Debian Lenny, 5.4 on CentOS 5.4, 2003 for Windows
Server 2003, etc.

=item FULL_NAME

Full name of the operating system as reported by itself, e.g "Debian GNU/Linux
unstable (sid)" or "Microsoft(R) Windows(R) Server 2003, Enterprise Edition
x64". This is also contained in the HARDWARE/OSNAME field which will be
deprecated in the future.

=item SERVICE_PACK

The Service Pack level reported by the operating system. This field is only
present on systems which use this notion.

=item INSTALL_DATE

The operating system installation date.

=item ARCH

Operating system architecture.

=item BOOT_TIME

The date of the boot of the computer, e.g: 2012-12-09 15:58:20

=back

=head2 MONITORS

=over

=item BASE64

The uuencoded EDID trame. Optional.

=item CAPTION

=item DESCRIPTION

=item MANUFACTURER

The manufacturer retrieved from the EDID trame.

=item SERIAL

The serial number retrieved from the EDID trame.

=item UUENCODE

The uuencoded EDID trame. Optional.

=back

=head2 PORTS

Serial, Parallel, SATA, etc

=over

=item CAPTION

=item DESCRIPTION

=item NAME

=item TYPE

=back

=head2 SLOTS

Represents physical connection points including ports, motherboard slots and
peripherals, and proprietary connection points.

This information is hardly reliable.

=over

=item DESCRIPTION

The bus type.

=item DESIGNATION

=item NAME

The slot identifier.

=item STATUS

The slot usage status (free or used).

=back

=head2 STORAGES

=over

=item DESCRIPTION

The long name of the device displayed to the user.

=item DISKSIZE

The disk size in MB.

=item INTERFACE

INTERFACE can be SCSI/HDC/IDE/USB/1394/Serial-ATA/SAS or empty if unknown

=item MANUFACTURER

=item MODEL

The commercial name of the device

=item NAME

The name of the device as seen by the system. E.g: hda (Linux), \\.\PHYSICALDRIVE0 (Windows)

=item TYPE

The kind of device. There is no standard for the format of the string in this field.

=item SERIAL

The harddrive serial number

=item SERIALNUMBER

Deprecated. The harddrive serial number, same as SERIAL.

=item FIRMWARE

=item SCSI_COID

=item SCSI_CHID

=item SCSI_UNID

=item SCSI_LUN

=item WWN

World Wide Name http://fr.wikipedia.org/wiki/World_Wide_Name

=back

=head2 SOFTWARES

=over

=item COMMENTS

=item FILESIZE

=item FOLDER

=item FROM

Where the information about the software came from, can be:
registry, rpm, deb, etc

=item HELPLINK

=item INSTALLDATE

Installation day in DD/MM/YYYY format. Windows only.

=item NAME

=item NO_REMOVE

Can the software be removed.

=item RELEASE_TYPE

Windows only for now, come from the registry

=item PUBLISHER

=item UNINSTALL_STRING

Windows only, come from the registry

=item URL_INFO_ABOUT

=item VERSION

=item VERSION_MINOR

Windows only, come from the registry

=item VERSION_MAJOR

Windows only, come from the registry

=item IS64BIT

If the software is in 32 or 64bit, (1/0)

=item GUID

Windows software GUID

=item USERNAME

Name of the owner of the software.

=item USERID

ID of the owner of the software. SID on Windows.

=back

=head2 USERS

=over

=item LOGIN

=item DOMAIN

The Windows domain of the user, if available.

=back

=head2 VIDEOS

=over

=item CHIPSET

=item MEMORY

Video card memory in MB

=item NAME

=item RESOLUTION

Resolution in pixel. 1024x768.

=item PCISLOT

The local PCI slot ID if the video card use PCI.

=back

=head2 VIRTUALMACHINES

=over

=item MEMORY

Memory size, in MB.

=item NAME

The name of the virtual machine.

=item UUID

=item STATUS

The VM status: running, idle, paused, shutdown, crashed, dying, off

=item SUBSYSTEM

The virtualisation software.
E.g: VmWare ESX

=item VMTYPE

The name of the virtualisation system family. The same type found is HARDWARE/VMSYSTEM

=item VCPU

Number of CPU affected to the virtual machine

=item VMID

The ID of virtual machine in the virtual managment system.

=item MAC

The list of the MAC addresses of the virtual machine. The delimiter is '/'. e.g: 00:23:18:91:db:8d/00:23:57:31:sb:8e

=item COMMENT

a comment

=item OWNER

=back

=head2 SOUNDS

=over

=item DESCRIPTION

=item MANUFACTURER

=item NAME

=back

=head2 MODEMS

=over

=item DESCRIPTION

=item NAME

=back

=head2 ENVS

Environment variables

=over

=item KEY

=item VAL

=back

=head2 UPDATES

Windows updates

=over

=item ID

Update Id

=item KB

List of KB, delimiter is '/'

=back

=head2 USBDEVICES

USB Devices

=over

=item VENDORID

Vendor USB ID. 4 hexa char.

=item PRODUCTID

Product USB ID. 4 hexa char.

=item SERIAL

=item CLASS

USB Class (e.g: 8 for Mass Storage)

=item SUBCLASS

USB Sub Class

=item NAME

The name of the device (optional)

=back

=head2 NETWORKS

A network configuration, ie either an adressless interface, either a
combination of an interface and an IP address.

=over

=item DESCRIPTION

The interface name, as seen in the OS settings, e.g: eth0 (Linux) or AMD PCNET Family Ethernet Adapter (Windows)

=item MANUFACTURER

The interface manufacturer

=item MODEL

The interface model

=item MANAGEMENT

True for HP iLO, Sun SC, HP MP or other kind of Remote Management Interface

=item TYPE

The interface type: ethernet|wifi|loopback|alias|aggregate|bridge|dialup

=item VIRTUALDEV

True for virtual interfaces

=item DRIVER

The driver name

=item FIRMWARE

=item PCISLOT

The PCI slot name

=item PCIID

The PCI ID

=item PNPDEVICEID

The PCI ID (windows-specific format)

=item IPADDRESS

The IPv4 address

=item IPSUBNET

=item IPMASK

=item IPDHCP

The IP address of the DHCP server

=item IPGATEWAY

The IP address of the gateway

=item IPADDRESS6

The IPv6 address of the interface

=item IPSUBNET6

=item IPMASK6

=item MACADDR

=item WWN

World Wide Name http://fr.wikipedia.org/wiki/World_Wide_Name

=item MTU

=item SPEED

Interface speed in Mb/s

=item STATUS

Up or Down

=item SLAVES

Comma-sepatated list of component interfaces, for aggregate and bridges

=item BASE

Actual interface for aliases

=item WIFI_BSSID

Wifi Access point MAC Address

=item WIFI_SSID

Wifi Access point name

=item WIFI_MODE

Wifi mode

=item WIFI_Version

Wifi protocol version

=back

=head2 BATTERIES

=over

=item CAPACITY

Battery capacity in mWh

=item DATE

Manufacture date in DD/MM/YYYY format

=item NAME

Name of the device

=item SERIAL

Serial number

=item MANUFACTURER

Battery manufacturer

=item VOLTAGE

Voltage in mV

=back

=head2 PRINTERS

=over

=item COMMENT

=item DESCRIPTION

=item DRIVER

=item NAME

=item NETWORK

Network: True (1) if it's a network printer

=item PORT

=item RESOLUTION

Resolution: eg. 600x600

=item SHARED

Shared: True if the printer is shared (Win32)

=item STATUS

Status: See Win32_Printer.PrinterStatus

=item ERRSTATUS

ErrStatus: See Win32_Printer.ExtendedDetectedErrorState

=item SERVERNAME

=item SHARENAME

=item PRINTPROCESSOR

=item SERIAL

The serial number

=back

=head2 PROCESSES

=over

=item USER

The process owner

=item PID

The process Id

=item CPUUSAGE

The CPU usage.

=item MEM

The memory.

=item VIRTUALMEMORY

=item TTY

=item STARTED

When the process has been started in YYYY/MM/DD HH:MM format

=item CMD

The command.

=back

=head2 ANTIVIRUS

=over

=item COMPANY

Comapny name

=item NAME

=item GUID

Unique ID

=item ENABLED

1 if the antivirus is enabled.

=item UPTODATE

1 if the antivirus is up to date.

=item VERSION

=back

=head2 LOGICAL_VOLUMES

A LVM Logical Volume

=over

=item LVNAME

The volume name.

=item VGNAME

The volume group name.

=item ATTR

The special attribue used on this volume (e.g: a-)

=item SIZE

The size of the volume on MB.

=item UUID

The volume UUID.

=back

=head2 PHYSICAL_VOLUMES

=over

=item DEVICE

The device name. Eg.: /dev/sda1 on Linux.

=item PV_NAME

The physical device name.

=item FORMAT

The format. E.g: lvm2.

=item ATTR

The LVM attribue in use for this phyisical device.

=item SIZE

The size in MB.

=item PV_UUID

The UUID.

=item PV_PE_COUNT

Item PV_PE_COUNT

=item PE_SIZE

Item PE_SIZE

=back

=head2 VOLUME_GROUPS

A LVM Volume group.

=over

=item VGNAME

The name of the volume group.

=item PV_COUNT

=item LV_COUNT

=item ATTR

The volume group LVM attribue.

=item SIZE

The size.

=item FREE

The free space.

=item UUID

The UUID

=back

=head2 LICENSEINFOS

A license

=over

=item NAME

The name of the license

=item FULLNAME

The full name of the license (optional)

=item KEY

The key used to register the license (optional)

=item COMPONENTS

The components covered by the license (optional)

=item PRODUCTID

The ID of the installation (optional)

=back
