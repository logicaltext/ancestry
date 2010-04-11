module Ancestry
  module InstanceMethods 

    # Validate that the ancestors don't include this node.
    #
    # @return [String, nil] The error message added to the node, or +nil+ if
    #         the node's ancestry doesn't include itself.
    #
    def ancestry_exclude_self
      if ancestor_ids.include?(self.id)
        msg = "#{self.class.name.humanize} cannot be a descendant of itself."
        errors[:base] << msg
      end
    end

    # Update descendants with new ancestry if the current node's ancestry has
    # been changed.
    #
    # @return [Array,nil] The node's descendants if the current node's
    #         ancestry has been changed and ancestry callbacks are not
    #         disabled, otherwise +nil+.
    #
    def update_descendants_with_new_ancestry
      return if ancestry_callbacks_disabled?

      if valid_and_ancestry_column_has_been_updated?
        value = read_attribute(self.class.ancestry_column)
        descendants.each do |node|
          node.without_ancestry_callbacks do
            pattern       = %r[^#{self.child_ancestry}]
            replacement   = value.blank? ? id.to_s : "#{value}/#{id}"
            node_ancestry = node.read_attribute(node.class.ancestry_column)
            updated       = node_ancestry.gsub(pattern, replacement)
            updates       = { self.base_class.ancestry_column => updated }

            node.update_attributes(updates)
          end
        end
      end
    end

    # Apply orphan strategy unless the node is a new record.
    #
    # @return [Array, nil] A collection of nodes depending on the orphan
    #         strategy: if the orphan strategy is +:rootify+, then the node's
    #         descendants will be returned; if the orphan strategy is
    #         +:destroy+, then the node's destroyed descendants will be
    #         returned; if the orphan strategy is +:restrict+, an error will
    #         be raised unless the node is childless. +nil+ will be returned
    #         if the ancestry callbacks are disabled or if the node is a new
    #         record.
    #
    def apply_orphan_strategy
      return if ancestry_callbacks_disabled?

      unless new_record?
        case self.base_class.orphan_strategy
        when :rootify  then make_all_children_root
        when :destroy  then destroy_all_descendants
        when :restrict then raise_restrict_exception_if_childless
        end
      end
    end

    # Returns the ancestry value for this node's children.
    #
    # @return [String] The ancestry value for this node's children.
    #
    def child_ancestry
      raise_child_ancestry_exception_if_new_record
      attribute = "#{self.base_class.ancestry_column}_was"
      self.send(attribute).blank? ? id.to_s : "#{self.send(attribute)}/#{id}"
    end

    # Returns an array of the node's ancestor ids.
    #
    # @return [Array<Integer>] An array of the node's ancestor ids.
    #
    def ancestor_ids
      column = self.base_class.ancestry_column
      read_attribute(column).to_s.split('/').map(&:to_i)
    end
    
    # Returns a hash representing the finder conditions for the {#ancestors}
    # method.
    #
    # @return [Hash] Finder conditions.
    #
    def ancestor_conditions
      {self.base_class.primary_key => ancestor_ids}
    end

    # Returns a dynamic scope for ancestors based on the supplied relative
    # depth options.
    #
    # @param  [Hash] depth_options The depth options.
    # @option depth_options [Integer] :key The relative depth of the node in
    #         question, where +:key+ is one of the keys defined in
    #         {Ancestry::DEPTH_SCOPES}.
    # @return [ActiveRecord::NamedScope::Scope] The +NamedScope+.
    #
    def ancestors(depth_options = {})
      initial_scope = self.base_class.scope_depth(depth_options, depth)
      initial_scope.ordered_by_ancestry.where(ancestor_conditions)
    end
    
    # Returns an array of the node's path ids.
    #
    # @return [Array<Integer>] An array of the node's path ids.
    #
    def path_ids
      ancestor_ids + [id]
    end

    # Returns a hash representing the finder conditions for the {#path}
    # method.
    #
    # @return [Hash] Finder conditions.
    #
    def path_conditions
      {self.base_class.primary_key => path_ids}
    end

    # Returns a dynamic scope for ancestors based on the supplied relative
    # depth options.
    #
    # @param  [Hash] depth_options The depth options.
    # @option depth_options [Integer] :key The relative depth of the node in
    #         question, where +:key+ is one of the keys defined in
    #         {Ancestry::DEPTH_SCOPES}.
    # @return [ActiveRecord::NamedScope::Scope] The +NamedScope+.
    #
    def path(depth_options = {})
      initial_scope = self.base_class.scope_depth(depth_options, depth)
      initial_scope.ordered_by_ancestry.where(path_conditions)
    end
    
    # Returns the depth of the node.
    #
    # @return [Integer] The depth of the node.
    #
    def depth
      ancestor_ids.size
    end

    # Cache the depth of the node in the depth cache column.
    #
    # @return [Integer] The depth of the node.
    #
    def cache_depth
      write_attribute(self.base_class.depth_cache_column, depth)
    end

    # Sets the node's parent.
    #
    # @param  [#is_a?(self.class)] parent The parent node.
    # @return [String] The node's new ancestry value.
    #
    def parent=(parent)
      value = parent.blank? ? nil : parent.child_ancestry
      write_attribute(self.base_class.ancestry_column, value)
    end

    # Sets the node's parent via the parent id.
    #
    # @param  [Integer] parent_id The parent id.
    # @return [String] The node's new ancestry value.
    #
    def parent_id=(parent_id)
      self.parent = parent_id.blank? ? nil : self.base_class.find(parent_id)
    end

    # Returns the node's parent id.
    #
    # @return [Integer] The node's parent id.
    #
    def parent_id
      ancestor_ids.empty? ? nil : ancestor_ids.last
    end

    # Return the node's parent.
    #
    # @return  [#is_a?(self.class), nil] The node's parent or +nil+ if the
    #          node has no parent.
    #
    def parent
      parent_id.blank? ? nil : self.base_class.find(parent_id)
    end

    # Returns the node's root id.
    #
    # @return [Integer] The node's root id.
    #
    def root_id
      ancestor_ids.empty? ? id : ancestor_ids.first
    end

    # Returns the node's root.
    #
    # @return [#is_a?(self.class), self] The node's parent or the node itself
    #         if it is its own root.
    #
    def root
      (root_id == id) ? self : self.base_class.find(root_id)
    end

    # Returns +true+ or +false+ depending on whether the node is a root node.
    #
    # @return [true, false] depending on whether the node is a root node.
    #
    def is_root?
      read_attribute(self.base_class.ancestry_column).blank?
    end

    # Returns a hash representing the finder conditions for the {#children}
    # method.
    #
    # @return [Hash] Finder conditions.
    #
    def child_conditions
      {self.base_class.ancestry_column => child_ancestry}
    end

    # Returns a named scope for the node's children.
    #
    # @return [ActiveRecord::NamedScope::Scope] The +NamedScope+.
    #
    def children
      self.base_class.scoped :conditions => child_conditions
    end

    # Returns an array of the node's child ids.
    #
    # @return [Array<Integer>] An array of the node's child ids.
    #
    def child_ids
      nodes = children.select(self.base_class.primary_key)
      nodes.all.map(&self.base_class.primary_key.to_sym)
    end

    # Returns +true+ or +false+ depending on whether the node has children.
    #
    # @return [true, false] depending on whether the node has any children.
    #
    def has_children?
      children.exists? {}
    end

    # Returns +true+ or +false+ depending on whether the node is childless.
    #
    # @return [true, false] depending on whether the node is childless.
    #
    def is_childless?
      !has_children?
    end

    # Returns a hash representing the finder conditions for the {#siblings}
    # method.
    #
    # @return [Hash] Finder conditions.
    #
    def sibling_conditions
      value = read_attribute(self.base_class.ancestry_column)
      {self.base_class.ancestry_column => value}
    end

    # Returns a named scope for the node's siblings.
    #
    # @return [ActiveRecord::NamedScope::Scope] The +NamedScope+.
    #
    def siblings
      self.base_class.scoped :conditions => sibling_conditions
    end

    # Returns an array of the node's sibling ids.
    #
    # @return [Array<Integer>] An array of the node's sibling ids.
    #
    def sibling_ids
      nodes = siblings.select(self.base_class.primary_key)
      nodes.all.map(&self.base_class.primary_key.to_sym)
    end

    # Returns +true+ or +false+ depending on whether the node has any siblings.
    #
    # @return [true, false] depending on whether the node has any siblings.
    #
    def has_siblings?
      siblings.count > 1
    end

    # Returns +true+ or +false+ depending on whether the node is any only
    # child.
    #
    # @return [true, false] depending on whether the node is an only child.
    #
    def is_only_child?
      !has_siblings?
    end

    # Returns an array representing the finder conditions for the
    # {#descendants} method.
    #
    # @return [Array<String>] Finder conditions.
    #
    def descendant_conditions
      column     = self.base_class.ancestry_column
      c_ancestry = child_ancestry
      ["#{column} like ? or #{column} = ?", "#{c_ancestry}/%", c_ancestry]
    end

    # Returns a dynamic relation for descendants based on the supplied
    # relative depth options.
    #
    # @param  [Hash] depth_options The depth options.
    # @option depth_options [Integer] :key The relative depth of the node in
    #         question, where +:key+ is one of the keys defined in
    #         {Ancestry::DEPTH_SCOPES}.
    # @return [ActiveRecord::Relation] The +Relation+.
    #
    def descendants(depth_options = {})
      initial_scope = self.base_class.ordered_by_ancestry
      initial_scope = initial_scope.scope_depth(depth_options, depth)

      # initial_scope.scoped :conditions => descendant_conditions
      initial_scope.where(descendant_conditions)
    end

    # Returns an array of the node's descendant ids based on the supplied
    # relative depth options.
    #
    # @param  [Hash] depth_options The depth options.
    # @option depth_options [Integer] :key The relative depth of the node in
    #         question, where +:key+ is one of the keys defined in
    #         {Ancestry::DEPTH_SCOPES}.
    # @return [Array<Integer>] An array of the node's descendant ids.
    #
    def descendant_ids(depth_options = {})
      column = self.base_class.primary_key
      descendants(depth_options).select(column).all.map(&column.to_sym)
    end
    
    # Returns an array representing the finder conditions for the
    # {#subtree} method.
    #
    # @return [Array<String>] Finder conditions.
    #
    def subtree_conditions
      pk         = self.base_class.primary_key
      column     = self.base_class.ancestry_column
      conditions = ["#{pk} = ? or #{column} like ? or #{column} = ?"]
      conditions << self.id << "#{child_ancestry}/%" << child_ancestry
    end

    # Returns a dynamic relation for subtree based on the supplied relative
    # depth options.
    #
    # @param  [Hash] depth_options The depth options.
    # @option depth_options [Integer] :key The relative depth of the node in
    #         question, where +:key+ is one of the keys defined in
    #         {Ancestry::DEPTH_SCOPES}.
    # @return [ActiveRecord::Relation] The +Relation+.
    #
    def subtree(depth_options = {})
      initial_scope = self.base_class.ordered_by_ancestry
      initial_scope = initial_scope.scope_depth(depth_options, depth)

      initial_scope.where(subtree_conditions)
    end

    # Returns an array of the node's subtree ids based on the supplied
    # relative depth options.
    #
    # @param  [Hash] depth_options The depth options.
    # @option depth_options [Integer] :key The relative depth of the node in
    #         question, where +:key+ is one of the keys defined in
    #         {Ancestry::DEPTH_SCOPES}.
    # @return [Array<Integer>] An array of the node's subtree ids.
    #
    def subtree_ids(depth_options = {})
      column = self.base_class.primary_key
      subtree(depth_options).select(column).all.map(&column.to_sym)
    end

    # Yields a block for the node while temporarily disabling ancestry
    # callbacks.
    #
    # @yield A block for processing the node without ancestry callbacks.
    #
    def without_ancestry_callbacks
      @disable_ancestry_callbacks = true
      yield
      @disable_ancestry_callbacks = false
    end

    # Returns +true+ or +false+ depending on whether the ancestry callbacks
    # are disabled.
    #
    # @return [true, false] depending on whether ancestry callbacks are
    #         disabled.
    #
    def ancestry_callbacks_disabled?
      @disable_ancestry_callbacks
    end


    private

    def valid_and_ancestry_column_has_been_updated?
      ancestry_column = self.base_class.ancestry_column.to_s
      changed.include?(ancestry_column) && !new_record? && valid?
    end

    def make_all_children_root
      descendants.each do |node|
        node.without_ancestry_callbacks do
          updated = nil
          unless node.ancestry == child_ancestry
            updated = node.ancestry.gsub(/^#{child_ancestry}\//, '')
          end
          updates = { node.class.ancestry_column => updated }

          node.update_attributes(updates)
        end
      end
    end

    def destroy_all_descendants
      descendants.all.each do |node|
        node.without_ancestry_callbacks { node.destroy }
      end
    end

    def raise_restrict_exception_if_childless
      unless is_childless?
        msg = "Cannot delete record because it has descendants."
        raise Ancestry::AncestryException.new(msg)
      end
    end

    def raise_child_ancestry_exception_if_new_record
      if new_record?
        msg  = "No child ancestry for new record."
        msg += " Save record before performing tree operations."
        raise Ancestry::AncestryException.new(msg)
      end
    end

  end
end