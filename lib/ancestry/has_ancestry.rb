require 'ancestry/constants'
require 'ancestry/class_methods'
require 'ancestry/instance_methods'
require 'ancestry/exceptions'

class ActiveRecord::Base

  def self.has_ancestry(options = {})

    unless(options.is_a?(Hash))
      msg = "Options for has_ancestry must be in a hash."
      raise Ancestry::AncestryException.new(msg)
    end

    options.each do |key, value|
      unless Ancestry::PLUGIN_OPTIONS.include?(key)
        msg  = "Unknown option for has_ancestry:"
        msg += " #{key.inspect} => #{value.inspect}"
        raise Ancestry::AncestryException.new(msg)
      end
    end

    include Ancestry::InstanceMethods
    extend Ancestry::ClassMethods

    cattr_accessor :ancestry_column
    self.ancestry_column = options[:ancestry_column] || :ancestry

    cattr_reader :orphan_strategy
    self.orphan_strategy =
      options[:orphan_strategy] || Ancestry::DEFAULT_ORPHAN_STRATEGY

    # Save self as base class (for STI).
    cattr_accessor :base_class
    self.base_class = self
    
    validates_format_of ancestry_column,
                        :with => /\A[0-9]+(\/[0-9]+)*\Z/, :allow_nil => true

    validate :ancestry_exclude_self
    
    scope :roots, where(ancestry_column => nil)

    scope :ancestors_of,
          lambda { |object| where(to_node(object).ancestor_conditions) }

    scope :children_of,
          lambda { |object| where(to_node(object).child_conditions) }

    scope :descendants_of,
          lambda { |object| where(to_node(object).descendant_conditions) }

    scope :subtree_of,
          lambda { |object| where(to_node(object).subtree_conditions) }

    scope :siblings_of,
          lambda { |object| where(to_node(object).sibling_conditions) }

    scope :ordered_by_ancestry,
          order("#{ancestry_column} is not null, #{ancestry_column}")

    scope :ordered_by_ancestry_and,
      lambda { |arg|
        order("#{ancestry_column} is not null, #{ancestry_column}, #{arg}")
      }
    
    before_save :update_descendants_with_new_ancestry

    before_destroy :apply_orphan_strategy

    if options[:cache_depth]
      self.cattr_accessor :depth_cache_column
      self.depth_cache_column = options[:depth_cache_column] || :ancestry_depth

      # Cache depth in depth cache column before save.
      before_validation :cache_depth

      validates_numericality_of depth_cache_column,
                                :greater_than_or_equal_to => 0,
                                :only_integer => true,
                                :allow_nil => false
    end
    
    # Create named scopes for depth.
    Ancestry::DEPTH_SCOPES.each do |scope_name, operator|
      scope scope_name, lambda { |depth|
        unless options[:cache_depth]
          msg  = "Named scope '#{scope_name}' is only available"
          msg += "when depth caching is enabled."
          raise Ancestry::AncestryException.new(msg)
        end
        where("#{depth_cache_column} #{operator} ?", depth)
      }
    end
  end
  
  # Alias has_ancestry with acts_as_tree, if it's available.
  class << self
    if !respond_to?(:acts_as_tree)
      alias_method :acts_as_tree, :has_ancestry
    end
  end

end