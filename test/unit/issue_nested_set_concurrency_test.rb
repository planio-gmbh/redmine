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

class IssueNestedSetConcurrencyTest < ActiveSupport::TestCase
  fixtures :projects, :users,
           :trackers, :projects_trackers,
           :enabled_modules,
           :issue_statuses,
           :enumerations

  self.use_transactional_tests = false

  def setup
    skip if sqlite?
    if mysql?
      connection = ActiveRecord::Base.connection_db_config.configuration_hash.deep_dup
      connection[:variables] = mysql8? ? { transaction_isolation: "READ-COMMITTED" } : { tx_isolation: "READ-COMMITTED" }
      ActiveRecord::Base.establish_connection connection
    end
    User.current = nil
    CustomField.delete_all
    Issue.delete_all
    IssueHierarchy.delete_all
  end

  def teardown
  end

  def test_concurrency
    # Generates an issue and destroys it in order
    # to load all needed classes before starting threads
    i = Issue.generate!
    i.destroy

    root = Issue.generate!
    assert_difference 'Issue.count', 60 do
      threaded(3) do
        10.times do
          i = Issue.generate! :parent_issue_id => root.id
          c1 = Issue.generate! :parent_issue_id => i.id
          c2 = Issue.generate! :parent_issue_id => i.id
          c3 = Issue.generate! :parent_issue_id => i.id
          c2.reload.destroy
          c1.reload.destroy
        end
      end
    end
  end

  def test_concurrent_subtasks_creation
    root = Issue.generate!
    assert_difference 'Issue.count', 30 do
      threaded(3) do
        10.times do
          Issue.generate! :parent_issue_id => root.id
        end
      end
    end
    root.reload
    assert_equal 30, root.descendants.count
  end

  def test_concurrent_subtask_removal
    with_settings :notified_events => [] do
      root = Issue.generate!
      60.times do
        Issue.generate! :parent_issue_id => root.id
      end
      # pick 40 random subtask ids
      child_ids = root.children.pluck(:id)
      ids_to_remove = child_ids.sample(40).shuffle
      ids_to_keep = child_ids - ids_to_remove
      # remove these from the set, using four parallel threads
      threads = []
      ids_to_remove.each_slice(10) do |ids|
        threads << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            begin
              ids.each do |id|
                Issue.find(id).update(parent_id: nil)
              end
            rescue => e
              Thread.current[:exception] = e.message
            end
          end
        end
      end
      threads.each do |thread|
        thread.join
        assert_nil thread[:exception]
      end

      Issue.where(id: ids_to_remove).each do |issue|
        assert_nil issue.parent_id
        assert issue.root?
        assert issue.leaf?
      end
      root.reload
      assert_equal 20, root.descendants.count
    end
  end

  private

  def threaded(count, &block)
    with_settings :notified_events => [] do
      threads = []
      count.times do |i|
        threads << Thread.new(i) do
          ActiveRecord::Base.connection_pool.with_connection do
            begin
              yield
            rescue => e
              Thread.current[:exception] = e.message
            end
          end
        end
      end
      threads.each do |thread|
        thread.join
        assert_nil thread[:exception]
      end
    end
  end
end
