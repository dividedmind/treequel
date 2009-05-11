#!/usr/bin/env ruby

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent

	libdir = basedir + "lib"

	$LOAD_PATH.unshift( libdir ) unless $LOAD_PATH.include?( libdir )
}

begin
	require 'spec'
	require 'spec/lib/constants'
	require 'spec/lib/helpers'

	require 'yaml'
	require 'ldap'
	require 'ldap/schema'
	require 'treequel/schema'
rescue LoadError
	unless Object.const_defined?( :Gem )
		require 'rubygems'
		retry
	end
	raise
end


include Treequel::TestConstants
include Treequel::Constants

#####################################################################
###	C O N T E X T S
#####################################################################

describe Treequel::Schema do
	include Treequel::SpecHelpers

	before( :all ) do
		setup_logging( :debug )
		@datadir = Pathname( __FILE__ ).dirname.parent + 'data'
	end

	after( :all ) do
		reset_logging()
	end


	it "can parse the schema structure returned from LDAP::Conn#schema" do
		pending "completion of the Schema class" do
			schema_dumpfile = @datadir + 'schema.yml'
			hash = YAML.load_file( schema_dumpfile )
			schema = LDAP::Schema.new( hash )

			Treequel::Schema.new_from_schema( schema )
		end
	end



end


# vim: set nosta noet ts=4 sw=4:
