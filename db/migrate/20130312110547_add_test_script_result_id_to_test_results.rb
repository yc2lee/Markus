class AddTestScriptResultIdToTestResults < ActiveRecord::Migration
  def self.up
    add_column :test_results, :test_run, :integer
  end

  def self.down
    remove_column :test_results, :test_run
  end
end
