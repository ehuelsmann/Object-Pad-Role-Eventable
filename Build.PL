use strict;
use warnings;

use Module::Build;
use Object::Pad::ExtensionBuilder;
use XS::Parse::Keyword::Builder;

my $build = Module::Build->new(
   module_name => 'Object::Pad::Eventable',
   requires => {
      'perl' => '5.018',
      'Object::Pad' => '0.60',
      'XS::Parse::Keyword' => 0,
   },
   test_requires => {
      'Test2::V0' => 0,
   },
   configure_requires => {
      'Module::Build' => '0.4004',
      'Object::Pad::ExtensionBuilder' => '0.73',
      'XS::Parse::Keyword::Builder' => '0.30',
   },
   license => 'perl',
   create_license => 1,
   create_readme => 1,
);
 
Object::Pad::ExtensionBuilder->extend_module_build( $build );

XS::Parse::Keyword::Builder->extend_module_build( $build );

$build->create_build_script;

