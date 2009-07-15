#!/usr/bin/env ruby

require 'forwardable'
require 'ldap'
require 'ldap/ldif'

require 'treequel'
require 'treequel/mixins'
require 'treequel/constants'
require 'treequel/branchset'
require 'treequel/branchcollection'


# The object in Treequel that wraps an entry. It knows how to construct other branches
# for the entries below itself, and how to search for those entries.
#
# == Subversion Id
#
#  $Id$
#
# == Authors
#
# * Michael Granger <ged@FaerieMUD.org>
# * Mahlon E. Smith <mahlon@martini.nu>
#
# :include: LICENSE
#
#--
#
# Please see the file LICENSE in the base directory for licensing details.
#
class Treequel::Branch
	include Comparable,
	        Treequel::Loggable,
	        Treequel::Constants

	extend Treequel::Delegation


	# SVN Revision
	SVNRev = %q$Rev$

	# SVN Id
	SVNId = %q$Id$


	#################################################################
	###	C L A S S   M E T H O D S
	#################################################################

	### Create a new Treequel::Branch from the given +entry+ hash from the specified +directory+.
	def self::new_from_entry( entry, directory )
		return self.new( directory, entry['dn'].first, entry )
	end


	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################

	### Create a new Treequel::Branch with the given +directory+, +rdn_attribute+, +rdn_value+, and
	### +base_dn+. If the optional +entry+ object is given, it will be used to fetch values from
	### the directory; if it isn't provided, it will be fetched from the +directory+ the first
	### time it is needed.
	def initialize( directory, dn, entry=nil )
		raise ArgumentError, "invalid DN" unless dn.match( Patterns::DISTINGUISHED_NAME )
		raise ArgumentError, "can't cast a %s to an LDAP::Entry" % [entry.class.name] unless
			entry.nil? || entry.is_a?( Hash )

		@directory = directory
		@dn        = dn
		@entry     = entry

		@values    = {}
	end


	######
	public
	######

	# Delegate some other methods to a new Branchset via the #branchset method
	def_method_delegators :branchset, :filter, :scope, :select


	# The directory the branch's entry lives in
	attr_reader :directory

	# The DN of the branch
	attr_reader :dn
	alias_method :to_s, :dn


	### Change the DN the Branch uses to look up its entry.
	def dn=( newdn )
		self.clear_caches
		@dn = newdn
	end


	### Return the attribute/s which make up this Branch's RDN.
	def rdn_attributes
		return self.rdn.split( /\s*\+\s*/ ).inject({}) do |attributes, pair|
			attrname, value = pair.split(/\s*=\s*/)
			attributes[ attrname ] = value
			attributes
		end
	end


	### Return the LDAP::Entry associated with the receiver, fetching it from the
	### directory if necessary. Returns +nil+ if the entry doesn't exist in the
	### directory.
	def entry
		return @entry ||= self.directory.get_entry( self )
	end


	### Return the RDN of the branch.
	def rdn
		return self.split_dn( 2 ).first
	end


	### Return the receiver's DN as an Array of attribute=value pairs. If +limit+ is non-zero, 
	### only the <code>limit-1</code> first pairs are split from the DN, and the remainder 
	### will be returned as the last element.
	def split_dn( limit=0 )
		return self.dn.split( /\s*,\s*/, limit )
	end


	### Return the LDAP URI for this branch
	def uri
		uri = self.directory.uri
		uri.dn = self.dn
		return uri
	end


	### Return the Branch's immediate parent node.
	def parent
		parent_dn = self.split_dn( 2 ).last
		return self.class.new( self.directory, parent_dn )
	end


	### Return the Branch's immediate children as Treeque::Branch objects.
	def children
		return self.directory.search( self, :one, '(objectClass=*)' )
	end


	### Return a Treequel::Branchset that will use the receiver as its base.
	def branchset
		return Treequel::Branchset.new( self )
	end


	### Return Treequel::Schema::ObjectClass instances for each of the receiver's
	### objectClass attributes. If any +additional_classes+ are given, 
	### merge them with the current list of the current objectClasses for the lookup.
	def object_classes( *additional_classes )
		schema = self.directory.schema

		# 5.1. objectClass
		#   The values of the objectClass attribute describe the kind of object
		#   which an entry represents.  The objectClass attribute is present in
		#   every entry, with at least two values.  One of the values is either
		#   "top" or "alias".
		object_classes = self[:objectClass] || [ :top ]
		object_classes |= additional_classes

		return object_classes.collect {|oid| schema.object_classes[oid.to_sym] }.uniq
	end


	### Return Treequel::Schema::AttributeType instances for each of the receiver's
	### objectClass's MUST attributeTypes. If any +additional_object_classes+ are given, 
	### include the MUST attributeTypes for them as well. This can be used to predict what
	### attributes would need to be present for the entry to be saved if it added the
	### +additional_object_classes+ to its own.
	def must_attribute_types( *additional_object_classes )
		return self.object_classes( *additional_object_classes ).
			collect {|oc| oc.must }.flatten.uniq
	end


	### Return OIDs (numeric OIDs as Strings, named OIDs as Symbols) for each of the receiver's
	### objectClass's MUST attributeTypes. If any +additional_object_classes+ are given, 
	### include the OIDs of the MUST attributes for them as well. This can be used to predict 
	### what attributes would need to be present for the entry to be saved if it added the
	### +additional_object_classes+ to its own.
	def must_oids( *additional_object_classes )
		return self.object_classes( *additional_object_classes ).
			collect {|oc| oc.must_oids }.flatten.uniq
	end


	### Return a Hash of the attributes required by the Branch's objectClasses. If 
	### any +additional_object_classes+ are given, include the attributes that would be
	### necessary for the entry to be saved with them.
	def must_attributes_hash( *additional_object_classes )
		entry = self.entry
		attrhash = {}

		self.must_attribute_types( *additional_object_classes ).each do |attrtype|
			# Use the existing value if the branch's entry exists already.
			if entry
				attrhash[ attrtype.name ] = self[ attrtype.name ]

			# Otherwise, set a default value based on whether it's SINGLE or not.
			elsif attrtype.single?
				attrhash[ attrtype.name ] = ''
			else
				attrhash[ attrtype.name ] = ['']
			end
		end

		attrhash[ :objectClass ] |= additional_object_classes
		return attrhash
	end


	### Return Treequel::Schema::AttributeType instances for each of the receiver's
	### objectClass's MAY attributeTypes. If any +additional_object_classes+ are given, 
	### include the MAY attributeTypes for them as well. This can be used to predict what
	### optional attributes could be added to the entry if the +additional_object_classes+ 
	### were added to it.
	def may_attribute_types( *additional_object_classes )
		return self.object_classes( *additional_object_classes ).
			collect {|oc| oc.may }.flatten.uniq
	end


	### Return OIDs (numeric OIDs as Strings, named OIDs as Symbols) for each of the receiver's
	### objectClass's MAY attributeTypes. If any +additional_object_classes+ are given, 
	### include the OIDs of the MAY attributes for them as well. This can be used to predict 
	### what optional attributes could be added to the entry if the +additional_object_classes+ 
	### were added to it.
	def may_oids( *additional_object_classes )
		return self.object_classes( *additional_object_classes ).
			collect {|oc| oc.may_oids }.flatten.uniq
	end


	### Return a Hash of the optional attributes allowed by the Branch's objectClasses. If 
	### any +additional_object_classes+ are given, include the attributes that would be
	### available for the entry if it had them.
	def may_attributes_hash( *additional_object_classes )
		entry = self.entry
		attrhash = {}

		self.may_attribute_types( *additional_object_classes ).each do |attrtype|
			self.log.debug "  adding attrtype %p to the may attributes hash" % [ attrtype ]

			# Use the existing value if the branch's entry exists already.
			if entry
				attrhash[ attrtype.name ] = self[ attrtype.name ]

			# Otherwise, set a default value based on whether it's SINGLE or not.
			elsif attrtype.single?
				attrhash[ attrtype.name ] = nil
			else
				attrhash[ attrtype.name ] = []
			end
		end

		attrhash[ :objectClass ] |= additional_object_classes
		return attrhash
	end


	### Return Treequel::Schema::AttributeType instances for the set of all of the receiver's
	### MUST and MAY attributeTypes.
	def valid_attribute_types
		return self.must_attribute_types | self.may_attribute_types
	end


	### Return a uniqified Array of OIDs (numeric OIDs as Strings, named OIDs as Symbols) for
	### the set of all of the receiver's MUST and MAY attributeTypes.
	def valid_attribute_oids
		return self.must_oids | self.may_oids
	end


	### Return a Hash of all the attributes allowed by the Branch's objectClasses. If 
	### any +additional_object_classes+ are given, include the attributes that would be
	### available for the entry if it had them.
	def valid_attributes_hash( *additional_object_classes )
		must = self.must_attributes_hash( *additional_object_classes )
		may  = self.may_attributes_hash( *additional_object_classes )

		return may.merge( must )
	end


	### Return +true+ if the specified +attrname+ is a valid attributeType given the
	### receiver's current objectClasses.
	def valid_attribute?( attroid )
		attroid = attroid.to_sym if attroid.is_a?( String ) && 
			attroid !~ NUMERICOID
		return self.valid_attribute_oids.include?( attroid )
	end


	### Returns a human-readable representation of the object suitable for
	### debugging.
	def inspect
		return "#<%s:0x%0x %s @ %s entry=%p>" % [
			self.class.name,
			self.object_id * 2,
			self.dn,
			self.directory,
			@entry,
		  ]
	end


	### Return the entry's DN as an RFC1781-style UFN (User-Friendly Name).
	def to_ufn
		return LDAP.dn2ufn( self.dn )
	end


	### Return the Branch as an LDAP::LDIF::Entry.
	def to_ldif
		ldif = "dn: %s\n" % [ self.dn ]

		self.entry.keys.reject {|k| k == 'dn' }.each do |attribute|
			self.entry[ attribute ].each do |val|
				# self.log.debug "  creating LDIF fragment for %p=%p" % [ attribute, val ]
				frag = LDAP::LDIF.to_ldif( attribute, [val.dup] )
				# self.log.debug "  LDIF fragment is: %p" % [ frag ]
				ldif << frag
			end
		end

		return LDAP::LDIF::Entry.new( ldif )
	end


	### Fetch the value/s associated with the given +attrname+ from the underlying entry.
	def []( attrname )
		attrsym = attrname.to_sym

		unless @values.key?( attrsym )
			directory = self.directory

			self.log.debug "  value is not cached; checking its attributeType"
			unless attribute = directory.schema.attribute_types[ attrsym ]
				self.log.info "no attributeType for %p" % [ attrsym ]
				return nil
			end

			self.log.debug "  attribute exists; checking the entry for a value"
			entry = self.entry or return nil
			return nil unless (( value = entry[attrsym.to_s] ))

			syntax_oid = attribute.syntax_oid

			if attribute.single?
				self.log.debug "    attributeType is SINGLE; unwrapping the Array"
				@values[ attrsym ] = directory.convert_syntax_value( syntax_oid, value.first )
			else
				self.log.debug "    attributeType is not SINGLE; keeping the Array"
				@values[ attrsym ] = value.collect do |raw|
					directory.convert_syntax_value( syntax_oid, raw )
				end
			end

			@values[ attrsym ].freeze
		else
			self.log.debug "  value is cached."
		end

		return @values[ attrsym ]
	end


	### Set attribute +attrname+ to a new +value+.
	def []=( attrname, value )
		value = [ value ] unless value.is_a?( Array )
		self.log.debug "Modifying %s to %p" % [ attrname, value ]
		self.directory.modify( self, attrname.to_s => value )
		@values.delete( attrname.to_sym )
		self.entry[ attrname.to_s ] = value
	end


	### Make the changes to the entry specified by the given +attributes+.
	def merge( attributes )
		self.directory.modify( self, attributes )
		self.clear_caches

		return true
	end
	alias_method :modify, :merge


	### Delete the entry associated with the branch from the directory.
	def delete
		self.directory.delete( self )
		return true
	end


	### Create the entry for this Branch with the specified +attributes+.
	def create( attributes={} )
		return self.directory.create( self, attributes )
	end


	### Copy the entry under this branch to a new entry indicated by +rdn+ and
	### with the given +attributes+, returning a new Branch object for it on success.
	def copy( rdn, attributes={} )
		self.log.debug "Asking the directory for a copy of myself called %p" % [ rdn ]
		return self.directory.copy( self, rdn, attributes )
	end


	### Move the entry associated with this branch to a new entry indicated by +rdn+. If 
	### any +attributes+ are given, also replace the corresponding attributes on the new
	### entry with them.
	def move( rdn, attributes={} )
		self.log.debug "Asking the directory to move me to an entry called %p" % [ rdn ]
		return self.directory.move( self, rdn, attributes )
	end


	### Comparable interface: Returns -1 if other_branch is less than, 0 if other_branch is 
	### equal to, and +1 if other_branch is greater than the receiving Branch.
	def <=>( other_branch )
		# Try the easy cases first
		return nil unless other_branch.respond_to?( :dn ) &&
			other_branch.respond_to?( :split_dn )
		return 0 if other_branch.dn == self.dn

		# Try comparing reversed attribute pairs
		rval = nil
		pairseq = self.split_dn.reverse.zip( other_branch.split_dn.reverse )
		pairseq.each do |a,b|
			comparison = (a <=> b)
			return comparison if !comparison.nil? && comparison.nonzero?
		end

		# The branches are related, so directly comparing DN strings will work
		return self.dn <=> other_branch.dn
	end


	### Addition operator: return a Treequel::BranchCollection that contains both the receiver
	### and +other_branch+.
	def +( other_branch )
		return Treequel::BranchCollection.new( self.branchset, other_branch.branchset )
	end



	#########
	protected
	#########

	### Proxy method: if the first argument matches a valid attribute in the directory's
	### schema, return a new Branch for the RDN made by using the first two arguments as
	### attribute and value, and the remaining hash as additional attributes.
	### 
	### E.g.,
	###   branch = Treequel::Branch.new( directory, 'ou=people,dc=acme,dc=com' )
	###   branch.uid( :chester ).dn
	###   # => 'uid=chester,ou=people,dc=acme,dc=com'
	###   branch.uid( :chester, :employeeType => 'admin' ).dn
	###   # => 'uid=chester+employeeType=admin,ou=people,dc=acme,dc=com'
	def method_missing( attribute, value=nil, additional_attributes={} )
		return super( attribute ) if value.nil?
		valid_types = self.directory.schema.attribute_types

		return super(attribute) unless
			valid_types.key?( attribute ) &&
			additional_attributes.keys.all? {|ex_attr| valid_types.key?(ex_attr) }

		rdn = self.rdn_from_pair_and_hash( attribute, value, additional_attributes )
		newdn = [ rdn, self.dn ].join( ',' )

		return self.class.new( self.directory, newdn )
	end


	### Make an RDN string (RFC 4514) from the primary +attribute+ and +value+ pair plus any 
	### +additional_attributes+ (for multivalue RDNs).
	def rdn_from_pair_and_hash( attribute, value, additional_attributes={} )
		additional_attributes.merge!( attribute => value )
		return additional_attributes.sort_by {|k,v| k.to_s }.
			collect {|pair| pair.join('=') }.
			join('+')
	end


	### Split the given +rdn+ into an Array of the iniital RDN attribute and value, and a
	### Hash containing any additional pairs.
	def pair_and_hash_from_rdn( rdn )
		initial, *trailing = rdn.split( '+' )
		initial_pair = initial.split( /\s*=\s*/ )
		trailing_pairs = trailing.inject({}) do |hash,pair|
			k,v = pair.split( /\s*=\s*/ )
			hash[ k ] = v
			hash
		end

		return initial_pair + [ trailing_pairs ]
	end


	### Clear any cached values when the structural state of the object changes.
	def clear_caches
		@entry = nil
		@values.clear
	end


end # class Treequel::Branch


