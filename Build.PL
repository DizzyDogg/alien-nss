use strict;
use warnings;

use IPC::Cmd qw/can_run/;
use Net::FTP;
use Carp;

use Sort::Versions; # This is a requirement of Alien::Base, hence we can also use it

use Alien::Base::ModuleBuild;

my $make;

`gmake --version 2>&1`;
if ( $? == 0 ) {
	$make = 'gmake';
} elsif ( `make --version 2>&1` =~ m#GNU# ) {
	$make = 'make';
} else {
	print STDERR "No suitable make could be found\n";
	my $makeversion = `make --version 2>&1`;
	print STDERR "Result of trying make --version:\n$makeversion\n";
	exit(0);
}

my $arch = `uname -m`;
my $add64 = "";
if ( $arch =~ m#64# ) {
	$add64 = "USE_64=1";
}

my $addcc = "";
$addcc = "CC=cc" if ( (!can_run('gcc')) && can_run('cc') );

my @build_commands = (
	# patch out @execute_path...
	'perl -pi -e \'s/\@executable_path/\$\(INSTALL_DIR\)/g\' nss/lib/freebl/config.mk',
	'perl -pi -e \'s/\@executable_path/\$\(INSTALL_DIR\)/g\' nss/coreconf/Darwin.mk',
	'perl -pi -e \'s/\@executable_path/\$\(INSTALL_DIR\)/g\' nspr/configure',
	'perl -pi -e \'s/\@executable_path/\$\(INSTALL_DIR\)/g\' nspr/configure.in',
	"echo 'Option add64: $add64'",
	'uname',
	'uname -m',
	'uname -a',
	'bash -c \''.$make." -C nss nss_build_all INSTALL_DIR=%s/lib BUILD_OPT=1 $addcc ".$add64.'\'',
	'mkdir stage',
	'mkdir stage/include',
	'mkdir stage/lib',
	'cp -L dist/public/nss/* stage/include',
	'cp -L -R dist/*.OBJ/include/* stage/include',
	'cp -L -R dist/*.OBJ/lib/* stage/lib',
	'rm -r dist nss nspr'
);

my $builder = Alien::Base::ModuleBuild->new (
	(sign => 1),
	module_name => 'Alien::NSS',
	license => 'mozilla',
	configure_requires => {
		'Alien::Base' => '0.003', # 0.002 has a breaking bug, 0.001 also works
		'Module::Build' => '0.38',
		'Sort::Versions' => 0,
		'Test::More' => 0,
	},
	requires => {
		'perl' => '5.8.1',
		'Alien::Base' => '0.003',
	},
	dist_author => 'Johanna Amann <johanna@icir.org>',
	alien_name => 'nss',
	alien_repository => {
		protocol => 'ftp',
		host => 'ftp.mozilla.org',
		location => 'pub/mozilla.org/security/nss/releases/NSS_3_17_1_RTM/src/',
		pattern  => qr/^nss-([\d\.]+)-with-nspr-.*\.tar\.gz$/,
	},
	# who needs configure, etc.
	alien_install_commands => [
		'if [ ! -e %s ] ; then mkdir %s; fi',
		'if [ ! -e %s/include ] ; then mkdir %s/include; fi',
		'if [ ! -e %s/lib ] ; then mkdir %s/lib; fi',
		'if [ -d stage ]; then cp -L -R stage/include/* %s/include; fi',
		'if [ -d stage ]; then cp -L -R stage/lib/* %s/lib; fi',
	],
	license => 'mozilla',
	meta_merge => {
		resources => {
			homepage => 'https://github.com/0xxon/alien-nss',
			bugtracker  => 'https://github.com/0xxon/alien-nss/issues',
			repository  => 'https://github.com/0xxon/alien-nss.git',
		},
	},

);


my %args = $builder->args;

if ( exists $args{help} ) {
	print<<EOF;
Command line options:

--help: print this message
--patchnss: add NSS patch for processing of many certificates
--version: download specific NSS version (e.g. 3_17_1).
EOF
	exit 0;
}

warn "\nArchitecture: $arch\n";

if ( exists $args{patchnss} ) {
	print "Adding command to patch NSS to Build\n";
	unshift(@build_commands, "patch -p1 < ../../patch/nss.patch");
}

my $version;
$version = $args{version} if(exists $args{version});

if ( !defined($version) ) {
	# Not specified, so let's look it up for ourselves
	warn "Searching current download directory on FTP server...\n";
	my $ftp = Net::FTP->new($builder->alien_repository->{host}, Debug => 0) or
		croak ("Cannot connect to repository host: $@");
	$ftp->login("anonymous", '-anonymous@') or croak("Cannot login: ".$ftp->message);
	$ftp->cwd("/pub/mozilla.org/security/nss/releases/") or croak("Base download directory not found");
	my @list = $ftp->ls or croak("Could not list directory");
	$ftp->quit;

	my @versions = sort { versioncmp($a, $b) } grep(s#^NSS_(\d.*)_RTM#$1#, @list);
	$version = pop @versions;
}

my $location = "pub/mozilla.org/security/nss/releases/NSS_".$version."_RTM/src/";
$builder->alien_repository->{location} = $location;
warn "wanted NSS path: $location\n";

$builder->alien_build_commands(\@build_commands);

$builder->create_build_script;
