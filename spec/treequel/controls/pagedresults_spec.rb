#!/usr/bin/env ruby

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent.parent

	libdir = basedir + "lib"

	$LOAD_PATH.unshift( basedir ) unless $LOAD_PATH.include?( basedir )
	$LOAD_PATH.unshift( libdir ) unless $LOAD_PATH.include?( libdir )
}

require 'rspec'

require 'spec/lib/helpers'

require 'treequel'
require 'treequel/behavior/control'
require 'treequel/controls/pagedresults'


#####################################################################
###	C O N T E X T S
#####################################################################
describe Treequel::PagedResultsControl do

	before( :all ) do
		setup_logging( :fatal )
	end

	before( :each ) do
		@conn = mock( "ldap connection object" )
		@conn.stub( :bound? ).and_return( false )
		@directory = get_fixtured_directory( @conn )
		@directory.register_controls( Treequel::PagedResultsControl )

		@branch = Treequel::Branch.new( @directory, TEST_PEOPLE_DN )
		@branchset = @branch.branchset
	end

	after( :all ) do
		reset_logging()
	end


	it_should_behave_like "A Treequel::Control"


	it "adds a paged_results_setsize attribute to extended branchsets" do
		@branchset.should respond_to( :paged_results_setsize )
	end

	it "adds a paged_results_cookie attribute to extended branchsets" do
		@branchset.should respond_to( :paged_results_cookie )
	end

	it "can add paging of a specific size to a Branchset via the #with_paged_results mutator" do
		@branchset.with_paged_results( 17 ).paged_results_setsize.should == 17
	end

	it "can create an unpaged Branchset from a paged one by passing nil to #with_paged_results" do
		paged_branchset = @branchset.with_paged_results( 25 )
		paged_branchset.with_paged_results( nil ).paged_results_setsize.should == nil
	end

	it "can create an unpaged Branchset from a paged one by passing 0 to #with_paged_results" do
		paged_branchset = @branchset.with_paged_results( 25 )
		paged_branchset.with_paged_results( 0 ).paged_results_setsize.should == nil
	end

	it "can create an unpaged Branchset from a paged one via the #without_paging mutator" do
		paged_branchset = @branchset.with_paged_results( 25 )
		paged_branchset.without_paging.paged_results_setsize.should == nil
	end

	it "can remove any existing paging from a Branchset via the #without_paging! imperative method" do
		paged_branchset = @branchset.with_paged_results( 25 )
		paged_branchset.without_paging!
		paged_branchset.paged_results_setsize.should == nil
	end

	it "knows that there are (potentially) more paged results if the cookie isn't set" do
		paged_branchset = @branchset.with_paged_results( 25 )
		paged_branchset.should_not be_done_paging()
	end

	it "knows that there are more paged results if the cookie is set" do
		paged_branchset = @branchset.with_paged_results( 25 )
		paged_branchset.paged_results_cookie = "\230\t\000\000\000\000\000\000"
		paged_branchset.should_not be_done_paging()
	end

	it "knows that there are no more paged results if the cookie is blank" do
		paged_branchset = @branchset.with_paged_results( 25 )
		paged_branchset.paged_results_cookie = ''
		paged_branchset.should be_done_paging()
	end

	it "injects the correct server-control structure into the search when iterating" do
		oid = Treequel::PagedResultsControl::OID
		expected_asn1_string = "0\005\002\001\031\004\000"
		expected_control = LDAP::Control.new( oid, expected_asn1_string, true )

		resultbranch  = mock( "Paged result branch" )
		resultcontrol = mock( "Paged result control" )

		@branch.should_receive( :search ).with( :subtree,
			instance_of(Treequel::Filter),
			{
				:limit           => 0,
				:selectattrs     => [],
				:timeout         => 0,
				:server_controls => [ expected_control ],
				:client_controls => []
			}
		  ).and_yield( resultbranch )

		resultbranch.should_receive( :controls ).and_return([ resultcontrol ])
		resultcontrol.should_receive( :oid ).
			and_return( Treequel::PagedResultsControl::OID )
		resultcontrol.should_receive( :decode ).and_return([ 25, "cookievalue" ])

		@branchset.with_paged_results( 25 ).each do |*args|
			args.should == [ resultbranch ]
		end
	end

	it "doesn't add a paging control if no set size has been set" do
		resultbranch = mock( "Result branch" )

		@branch.should_receive( :search ).with( :subtree,
			instance_of(Treequel::Filter),
			{
				:limit           => 0,
				:selectattrs     => [],
				:timeout         => 0,
				:server_controls => [],
				:client_controls => []
			}
		  ).and_yield( resultbranch )

		resultbranch.should_receive( :controls ).and_return( [] )

		@branchset.without_paging.each do |*args|
			args.should == [ resultbranch ]
		end
	end


end

# vim: set nosta noet ts=4 sw=4:
