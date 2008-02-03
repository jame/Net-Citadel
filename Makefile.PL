use 5.008008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Net::Citadel',
    VERSION_FROM      => 'lib/Net/Citadel.pm', # finds $VERSION
    PREREQ_PM         => {
	'Config::YAML' => '1.42',
    },

    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Net/Citadel.pm', # retrieve abstract from module
       AUTHOR         => 'Robert Barta <rho@devc.at>') : ()),
);

package MY;

sub depend {
    return <<MAKE

inject:
	mcpani --add --module Net::Citadel --authorid DRRHO --modversion \$(VERSION) --file Net-Citadel-\$(VERSION).tar.gz
	sudo mcpani --inject

debian:
	(cd /usr/local/share/packages; rm -rf Net-Cita* ; dh-make-perl --cpan-mirror file:/usr/local/share/minicpan --build --cpan Net::Citadel --notest)


upload:
	cpan-upload-http Net-Citadel-\$(VERSION).tar.gz

MAKE
}
