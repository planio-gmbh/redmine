# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-2023  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require_relative '../test_helper'

class IssueNestedSetTest < ActiveSupport::TestCase
  fixtures :projects, :users, :roles,
           :trackers, :projects_trackers,
           :issue_statuses, :issue_categories, :issue_relations,
           :enumerations,
           :issues, :journals, :journal_details

  def setup
    User.current = nil
  end

  def test_new_record_is_leaf
    i = Issue.new
    assert i.leaf?
  end

  def test_create_root_issue
    issue1 = Issue.generate!
    assert issue1.root?
    assert issue1.leaf?
    assert_nil issue1.parent
    issue2 = Issue.generate!
    assert issue2.root?
    assert issue2.leaf?
    assert_nil issue2.parent
  end

  def test_create_child_issue
    parent = Issue.generate!
    child = nil
    assert_difference 'Journal.count', 1 do
      child = parent.generate_child!
    end
    parent.reload
    child.reload
    assert !child.root?
    assert parent == child.root
    assert [child], parent.children
  end

  def test_creating_a_child_in_a_subproject_should_validate
    issue = Issue.generate!
    child = nil
    assert_difference 'Journal.count', 1 do
      child = Issue.new(:project_id => 3, :tracker_id => 2, :author_id => 1,
                        :subject => 'child', :parent_issue_id => issue.id)
      assert_save child
    end
    assert_equal issue, child.reload.parent
  end

  def test_creating_a_child_in_an_invalid_project_should_not_validate
    issue = Issue.generate!
    child = nil
    assert_no_difference 'Journal.count' do
      child = Issue.new(:project_id => 2, :tracker_id => 1, :author_id => 1,
                        :subject => 'child', :parent_issue_id => issue.id)
      assert !child.save
    end
    assert_not_equal [], child.errors[:parent_issue_id]
  end

  def test_move_a_root_to_child
    lft = new_issue_lft
    parent1 = Issue.generate!
    parent2 = Issue.generate!
    child = parent1.generate_child!
    assert_difference 'Journal.count', 2 do
      parent2.init_journal(User.find(2))
      parent2.parent_issue_id = parent1.id
      parent2.save!
    end
    child.reload
    parent1.reload
    parent2.reload
    assert parent1.children.include?(parent2)
    assert parent1.children.include?(child)
    assert parent2.leaf?
    assert child.leaf?
  end

  def test_move_a_child_to_root
    parent1 = Issue.generate!
    parent2 = Issue.generate!
    child = parent1.generate_child!
    assert_difference 'Journal.count', 2 do
      child.init_journal(User.find(2))
      child.parent_issue_id = nil
      child.save!
    end
    child.reload
    parent1.reload
    parent2.reload

    assert parent1.root?
    assert parent1.leaf?
    assert parent2.root?
    assert parent2.leaf?
    assert child.root?
    assert child.leaf?
  end

  def test_move_a_child_to_another_issue
    lft1 = new_issue_lft
    parent1 = Issue.generate!
    lft2 = new_issue_lft
    parent2 = Issue.generate!
    child = parent1.generate_child!
    assert_difference 'Journal.count', 3 do
      child.init_journal(User.find(2))
      child.parent_issue_id = parent2.id
      child.save!
    end
    child.reload
    parent1.reload
    parent2.reload
    assert parent2.children.include?(child)
    assert !parent1.children.include?(child)
  end

  def test_move_a_child_with_descendants_to_another_issue
    lft1 = new_issue_lft
    parent1 = Issue.generate!
    lft2 = new_issue_lft
    parent2 = Issue.generate!
    child = parent1.generate_child!
    grandchild = child.generate_child!
    parent1.reload
    parent2.reload
    child.reload
    grandchild.reload
    assert_equal parent1, child.parent
    assert_equal parent1, child.root
    assert_equal child, grandchild.parent
    assert_equal parent1, grandchild.root
    assert_equal [child, grandchild].map(&:id).sort, parent1.descendants.map(&:id).sort
    child.reload.parent_issue_id = parent2.id
    child.save!
    child.reload
    grandchild.reload
    parent1.reload
    parent2.reload
    assert_equal parent2, child.parent
    assert_equal parent2, child.root
    assert_equal child, grandchild.parent
    assert_equal parent2, grandchild.root
    assert_equal [child, grandchild].map(&:id).sort, parent2.descendants.map(&:id).sort
  end

  def test_move_a_child_with_descendants_to_another_project
    lft1 = new_issue_lft
    parent1 = Issue.generate!
    child = parent1.generate_child!
    grandchild = child.generate_child!
    lft4 = new_issue_lft
    child.reload
    assert_difference 'Journal.count', 2 do
      assert_difference 'JournalDetail.count', 3 do
        child.init_journal(User.find(2))
        child.project = Project.find(2)
        assert child.save
      end
    end
    child.reload
    grandchild.reload
    parent1.reload
    assert_equal 1, parent1.project_id
    assert parent1.root?
    assert parent1.leaf?
    assert_equal 2, child.project_id
    assert child.root?
    assert_equal child, grandchild.parent
    assert grandchild.leaf?
  end

  def test_moving_an_issue_to_a_descendant_should_not_validate
    parent1 = Issue.generate!
    parent2 = Issue.generate!
    child = parent1.generate_child!
    grandchild = child.generate_child!

    child.reload
    assert_no_difference 'Journal.count' do
      child.init_journal(User.find(2))
      child.parent_issue_id = grandchild.id
      assert !child.save
    end
    assert_not_equal [], child.errors[:parent_issue_id]
  end

  def test_updating_a_root_issue_should_not_trigger_update_nested_set_attributes_on_parent_change
    issue = Issue.find(Issue.generate!.id)
    issue.parent_issue_id = ""
    issue.expects(:update_nested_set_attributes_on_parent_change).never
    issue.save!
  end

  def test_updating_a_child_issue_should_not_trigger_update_nested_set_attributes_on_parent_change
    issue = Issue.find(Issue.generate!(:parent_issue_id => 1).id)
    issue.parent_issue_id = "1"
    issue.expects(:update_nested_set_attributes_on_parent_change).never
    issue.save!
  end

  def test_moving_a_root_issue_should_trigger_update_nested_set_attributes_on_parent_change
    issue = Issue.find(Issue.generate!.id)
    issue.parent_issue_id = "1"
    issue.expects(:update_nested_set_attributes_on_parent_change).once
    issue.save!
  end

  def test_moving_a_child_issue_to_another_parent_should_trigger_update_nested_set_attributes_on_parent_change
    issue = Issue.find(Issue.generate!(:parent_issue_id => 1).id)
    issue.parent_issue_id = "2"
    issue.expects(:update_nested_set_attributes_on_parent_change).once
    issue.save!
  end

  def test_moving_a_child_issue_to_root_should_trigger_update_nested_set_attributes_on_parent_change
    issue = Issue.find(Issue.generate!(:parent_issue_id => 1).id)
    issue.parent_issue_id = ""
    issue.expects(:update_nested_set_attributes_on_parent_change).once
    issue.save!
  end

  def test_destroy_should_destroy_children
    lft1 = new_issue_lft
    issue1 = Issue.generate!
    issue2 = Issue.generate!
    issue3 = issue2.generate_child!
    issue4 = issue1.generate_child!
    issue3.init_journal(User.find(2))
    issue3.subject = 'child with journal'
    issue3.save!
    assert_difference 'Issue.count', -2 do
      assert_difference 'Journal.count', -2 do
        assert_difference 'JournalDetail.count', -2 do
          Issue.find(issue2.id).destroy
        end
      end
    end
    issue1.reload
    issue4.reload
    assert !Issue.exists?(issue2.id)
    assert !Issue.exists?(issue3.id)
  end

  def test_destroy_child_should_update_parent
    lft1 = new_issue_lft
    issue = Issue.generate!
    child1 = issue.generate_child!
    child2 = issue.generate_child!
    issue.reload
    assert_equal 2, issue.children.size
    assert_difference 'Journal.count', 1 do
      child2.reload.destroy
    end
    issue.reload
    assert_equal 1, issue.children.size
  end

  def test_destroy_parent_issue_updated_during_children_destroy
    parent = Issue.generate!
    parent.generate_child!(:start_date => Date.today)
    parent.generate_child!(:start_date => 2.days.from_now)

    assert_difference 'Issue.count', -3 do
      assert_difference 'Journal.count', -2 do
        Issue.find(parent.id).destroy
      end
    end
  end

  def test_destroy_child_issue_with_children
    root = Issue.generate!
    child = root.generate_child!
    leaf = child.generate_child!
    leaf.init_journal(User.find(2))
    leaf.subject = 'leaf with journal'
    leaf.save!

    assert_difference 'Issue.count', -2 do
      assert_difference 'Journal.count', -1 do
        assert_difference 'JournalDetail.count', -1 do
          Issue.find(child.id).destroy
        end
      end
    end

    root = Issue.find(root.id)
    assert root.leaf?, "Root issue is not a leaf (#{root.inspect})"
  end

  def test_destroy_issue_with_grand_child
    lft1 = new_issue_lft
    parent = Issue.generate!
    issue = parent.generate_child!
    child = issue.generate_child!
    grandchild1 = child.generate_child!
    grandchild2 = child.generate_child!
    assert_difference 'Issue.count', -4 do
      assert_difference 'Journal.count', -2 do
        Issue.find(issue.id).destroy
      end
      parent.reload
      assert parent.leaf?
      assert parent.children.empty?
    end
  end

  def test_project_copy_should_copy_issue_tree
    p = Project.create!(:name => 'Tree copy', :identifier => 'tree-copy', :tracker_ids => [1, 2])
    i1 = Issue.generate!(:project => p, :subject => 'i1')
    i2 = i1.generate_child!(:project => p, :subject => 'i2')
    i3 = i1.generate_child!(:project => p, :subject => 'i3')
    i4 = i2.generate_child!(:project => p, :subject => 'i4')
    i5 = Issue.generate!(:project => p, :subject => 'i5')
    c = Project.new(:name => 'Copy', :identifier => 'copy', :tracker_ids => [1, 2])
    c.copy(p, :only => 'issues')
    c.reload

    assert_equal 5, c.issues.count
    ic1, ic2, ic3, ic4, ic5 = c.issues.order('subject').to_a
    assert ic1.root?
    assert_equal ic1, ic2.parent
    assert_equal ic1, ic3.parent
    assert_equal ic2, ic4.parent
    assert ic5.root?
  end

  def test_ordering_should_be_consistent
    Issue.delete_all
    i1 = Issue.generate!(:subject => '1')
    i5 = Issue.generate!(:subject => '2')
    i2 = i1.generate_child!(:subject => '1-1')
    i3 = i2.generate_child!(:subject => '1-1-1')
    i4 = i1.generate_child!(:subject => '1-2')

    assert_equal [i1, i2, i4, i3], i1.self_and_descendants
    assert_equal [i1, i2, i4, i3, i5], [i1, i2, i4, i3, i5].shuffle.sort
  end

  def test_rebuild
    i1 = Issue.generate!
    i2 = i1.generate_child!
    i3 = i1.generate_child!
    IssueHierarchy.delete_all

    Issue.rebuild!

    i1.reload
    i2.reload
    i3.reload
    assert_equal 2, i1.descendants.count
    assert_equal 2, i1.children.count
    assert_equal i1, i2.parent
    assert_equal i1, i3.parent
  end
end
