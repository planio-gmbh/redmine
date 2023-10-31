# frozen_string_literal: true

module Redmine
  module NestedSet
    module IssueClosureTree
      extend ActiveSupport::Concern

      prepended do
        before_destroy :destroy_descendants # order matters, has to be set up before has_closure_tree
        has_closure_tree dependent: nil
        alias_method :is_descendant_of?, :descendant_of?
        alias_method :is_ancestor_of?, :ancestor_of?
      end

      def is_or_is_ancestor_of?(other)
        other == self || ancestor_of?(other)
      end

      def move_possible?(issue)
        new_record? || !is_or_is_ancestor_of?(issue)
      end

      def destroy_without_descendants
        @without_descendants = true
        destroy
      end

      def destroy_descendants
        return if @without_descendants

        descendants.find_each do |d|
          d.destroy_without_descendants
        end
      end

      def root_id
        @root_id ||= (parent_id.nil? ? id : ancestors.where(parent_id: nil).pick(:id))
      end

      # Returns the ancestors of the issue, starting with root
      def ancestors
        super.reorder("issue_hierarchies.generations DESC")
      end
    end
  end
end
