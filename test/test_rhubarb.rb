# Test cases for Rhubarb, which is is a simple persistence layer for
# Ruby objects and SQLite.
#
# Copyright (c) 2009 Red Hat, Inc.
#
# Author:  William Benton (willb@redhat.com)
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0

require 'helper'
require 'fileutils'

Customer = Struct.new(:name, :address)
SQLITE_13 = ::Rhubarb::Persistence::sqlite_13
CONSTRAINT_EXCEPTION = SQLITE_13 ? SQLite3::ConstraintException : SQLite3::SQLException

BFB_MAX = 512

class ParityTest
  include Rhubarb::Persisting
  declare_column :number, :integer
  declare_column :parity, :boolean
end

class TestClass 
  include Rhubarb::Persisting  
  declare_column :foo, :integer
  declare_column :bar, :string
end

module RhubarbNamespace
  class NMTC
    include Rhubarb::Persisting  
    declare_column :foo, :integer
    declare_column :bar, :string
  end

  class NMTC2
    include Rhubarb::Persisting  
    declare_column :foo, :integer
    declare_column :bar, :string
    declare_table_name('namespacetestcase')
  end
end

class TestClass2 
  include Rhubarb::Persisting  
  declare_column :fred, :integer
  declare_column :barney, :string
  declare_index_on :fred
end

class TC3 
  include Rhubarb::Persisting  
  declare_column :ugh, :datetime
  declare_column :yikes, :integer
  declare_constraint :yikes_pos, check("yikes >= 0")
end

class TC4 
  include Rhubarb::Persisting  
  declare_column :t1, :integer, references(TestClass)
  declare_column :t2, :integer, references(TestClass2)
  declare_column :enabled, :boolean, :default, :true
end

class SelfRef 
  include Rhubarb::Persisting  
  declare_column :one, :integer, references(SelfRef)
end

class CustomQueryTable 
  include Rhubarb::Persisting  
  declare_column :one, :integer
  declare_column :two, :integer
  declare_query :ltcols, "one < two"
  declare_query :ltvars, "one < ? and two < ?"
  declare_custom_query :cltvars, "select * from __TABLE__ where one < ? and two < ?"
end

class ToRef 
  include Rhubarb::Persisting  
  declare_column :foo, :string
end

class FromRef
  include Rhubarb::Persisting 
  declare_column :t, :integer, references(ToRef, :on_delete=>:cascade)
  declare_query :to_is, "t = ?"
  declare_query :to_is_hash, "t = :t"
end

class FreshTestTable 
  include Rhubarb::Persisting
  declare_column :fee, :integer
  declare_column :fie, :integer
  declare_column :foe, :integer
  declare_column :fum, :integer
  declare_column :foo, :integer
  declare_column :bar, :integer
  
  def <=>(other)
    [:fie,:foe,:fum,:foo,:bar].each do |msg|
      tmpresult = self.send(msg) <=> other.send(msg)
      return tmpresult unless tmpresult == 0
    end
    return 0
  end
end

class BlobTestTable 
  include Rhubarb::Persisting
  declare_column :info, :blob
end

class ZBlobTestTable 
  include Rhubarb::Persisting
  declare_column :info, :zblob
end

class ObjectTestTable 
  include Rhubarb::Persisting
  declare_column :otype, :string
  declare_column :obj, :object
end

class NoColumnsTestTable
  include Rhubarb::Persisting
end

class Create
  include Rhubarb::Persisting
  declare_column :name, :string
end

class Group
  include Rhubarb::Persisting
  declare_column :other, :int, references(Create, :on_delete=>:cascade)
end

class Order
  include Rhubarb::Persisting
  declare_column :group, :int
end

class NoPreparedStmtBackendTests < Test::Unit::TestCase  
  def dbfile
    ENV['RHUBARB_TEST_DB'] || ":memory:"
  end
  
  def use_prepared
    false
  end

  def setup
    unless dbfile == ":memory:"
      FileUtils::safe_unlink(dbfile)
    end

    Rhubarb::Persistence::open(dbfile, :default, use_prepared)
    klasses = []
    klasses << TestClass
    klasses << TestClass2
    klasses << TC3
    klasses << TC4
    klasses << SelfRef
    klasses << CustomQueryTable
    klasses << ToRef
    klasses << FromRef
    klasses << FreshTestTable
    klasses << BlobTestTable
    klasses << ZBlobTestTable
    klasses << ObjectTestTable
    klasses << RhubarbNamespace::NMTC
    klasses << RhubarbNamespace::NMTC2
    klasses << ParityTest
    klasses.each { |klass| klass.create_table }

    @flist = []
  end

  def teardown
    Rhubarb::Persistence::close()
  end

  def test_boolean_find_by
    # believe me, I chuckled while writing this
    bit_parity = Proc.new do |k|
      k.to_s(2).split("0").join.size.even?
    end
    
    expected_numbers = Set.new

    BFB_MAX.times do |i|
      ParityTest.create(:number=>i, :parity=>bit_parity.call(i))
      expected_numbers << i
    end
    
    even = ParityTest.find_by(:parity=>true)
    odd = ParityTest.find_by(:parity=>false)

    assert_equal(BFB_MAX, even.size+odd.size)
    {even=>true, odd=>false}.each do |collection, par|
      collection.each do |pt|
        assert_equal(bit_parity.call(pt.number), pt.parity)
        assert_equal(par, pt.parity)
        expected_numbers.delete(pt.number)
      end
    end

    assert_equal(0, expected_numbers.size)
  end

  def test_reserved_word_table
    assert_nothing_raised do
      Create.create_table
      Create.create(:name=>"bar")
      c = Create.find_first_by_name("bar")
      c.name = "blah"
      c.name = "bar"
      assert(c.name == "bar")
      c.delete
    end
  end
  
  def test_reserved_word_column
    assert_nothing_raised do
      Order.create_table
      Order.create(:group=>42)
      o = Order.find_first_by_group(42)
      o.group = 37
      assert(o.group == 37)
    end
  end

  def test_reserved_word_fk_table
    assert_nothing_raised do
      Create.create_table
      Group.create_table
      Create.create(:name=>"bar")
      Group.create(:other=>Create.create(:name=>"blah"))
      assert(Group.find_all[0].other.name=="blah")
    end
  end

  def test_no_columns_table
    assert_nothing_raised do
      NoColumnsTestTable.create_table      
    end
  end

  def test_persistence_setup
    assert Rhubarb::Persistence::db.type_translation, "type translation not enabled for db"
    assert Rhubarb::Persistence::db.results_as_hash, "rows-as-hashes not enabled for db"
  end

  def test_reference_ctor_klass
    r = Rhubarb::Reference.new(TestClass)
    assert(r.referent == TestClass, "Referent of managed reference instance incorrect")
    assert(r.column == "row_id", "Column of managed reference instance incorrect")
    assert(r.to_s == "references TestClass(row_id)", "string representation of managed reference instance incorrect")
    assert(r.managed_ref?, "managed reference should return true for managed_ref?")
  end

  def test_namespace_table_name
    assert_equal "nmtc", RhubarbNamespace::NMTC.table_name
  end

  def test_set_table_name
    assert_equal "namespacetestcase", RhubarbNamespace::NMTC2.table_name
  end

  def test_reference_ctor_string
    r = Rhubarb::Reference.new("TestClass")
    assert(r.referent == "TestClass", "Referent of string-backed reference instance incorrect")
    assert(r.column == "row_id", "Column of string-backed reference instance incorrect")
    assert(r.to_s == "references TestClass(row_id)", "string representation of string-backed reference instance incorrect")
    assert(r.managed_ref? == false, "unmanaged reference should return false for managed_ref?")
  end

  def test_instance_methods
    ["foo", "bar"].each do |prefix|
      ["#{prefix}", "#{prefix}="].each do |m|
        assert TestClass.method_defined?(m), "#{m} method not declared in TestClass"
      end
    end
  end

  def test_instance_methods2
    ["fred", "barney"].each do |prefix|
      ["#{prefix}", "#{prefix}="].each do |m|
        assert TestClass2.method_defined?(m), "#{m} method not declared in TestClass2"
      end
    end
  end

  def test_instance_methods_neg
    ["fred", "barney"].each do |prefix|
      ["#{prefix}", "#{prefix}="].each do |m|
        bogus_include = TestClass.method_defined? m
        assert(bogus_include == false, "#{m} method declared in TestClass; shouldn't be")
      end
    end
  end
  
  def test_to_hash
    (0..5).each do |foo|
      ("A".."C").each do |bar|
        TestClass.create(:foo=>foo, :bar=>bar)
      end
    end
    
    TestClass.find_all.each do |tc|
      tch = tc.to_hash
      [:foo,:bar,:created,:updated].each do |msg|
        assert_equal(tch[msg], tc.send(msg))
      end
    end      
  end
  
  def test_delete_where
    (0..10).each do |foo|
      ("A".."G").each do |bar|
        TestClass.create(:foo=>foo, :bar=>bar)
      end
    end
    
    old_count = TestClass.count
    
    TestClass.delete_where(:foo=>1, :bar=>"B")
    
    assert_equal(old_count - 1, TestClass.count)
    assert_equal([], TestClass.find_by(:foo=>1, :bar=>"B"))
    
    TestClass.delete_where(:bar=>"C")
    assert_equal(old_count - 12, TestClass.count)
    assert_equal([], TestClass.find_by(:bar=>"C"))
    
  end

  def test_instance_methods_dont_include_class_methods
    ["foo", "bar"].each do |prefix|
      ["find_by_#{prefix}", "find_first_by_#{prefix}"].each do |m|
        bogus_include = TestClass.method_defined? m
        assert(bogus_include == false, "#{m} method declared in TestClass; shouldn't be")
      end
    end
  end

  def test_delete_all
    freshness_query_fixture
    assert(FreshTestTable.find_all.size > 0)
    FreshTestTable.delete_all
    assert_equal([], FreshTestTable.find_all)
  end

  def test_class_methods
    ["foo", "bar"].each do |prefix|
      ["find_by_#{prefix}", "find_first_by_#{prefix}"].each do |m|
        klass = class << TestClass; self end
        assert klass.method_defined?(m), "#{m} method not declared in TestClass' eigenclass"
      end
    end
  end
  
  def test_class_methods2
    ["fred", "barney"].each do |prefix|
      ["find_by_#{prefix}", "find_first_by_#{prefix}"].each do |m|
        klass = class << TestClass2; self end
        assert klass.method_defined?(m), "#{m} method not declared in TestClass2's eigenclass"
      end
    end
  end
    
  def test_table_class_methods_neg
    ["foo", "bar", "fred", "barney"].each do |prefix|
      ["find_by_#{prefix}", "find_first_by_#{prefix}"].each do |m|
        klass = Class.new

        klass.class_eval do
          include Rhubarb::Persisting
        end

        bogus_include = klass.method_defined?(m)
        assert(bogus_include == false, "#{m} method declared in eigenclass of class including Rhubarb::Persisting; shouldn't be")
      end
    end
  end

  def test_class_methods_neg
    ["fred", "barney"].each do |prefix|
      ["find_by_#{prefix}", "find_first_by_#{prefix}"].each do |m|
        klass = class << TestClass; self end
        bogus_include = klass.method_defined?(m)
        assert(bogus_include == false, "#{m} method declared in TestClass' eigenclass; shouldn't be")
      end
    end
  end

  def test_column_size
    assert(TestClass.columns.size == 5, "TestClass has wrong number of columns")
  end

  def test_tc2_column_size
    assert(TestClass2.columns.size == 5, "TestClass2 has wrong number of columns")
  end

  def test_table_column_size
    klass = Class.new
    klass.class_eval do
      include Rhubarb::Persisting
    end
    if klass.respond_to? :columns
      assert(Frotz.columns.size == 0, "A persisting class with no declared columns has the wrong number of columns")
    end
  end

  def test_constraints_size
    k = Class.new
    
    k.class_eval do
      include Rhubarb::Persisting
    end
    
    {k => 0, TestClass => 0, TestClass2 => 0, TC3 => 1}.each do |klass, cts|
      if klass.respond_to? :constraints
        assert(klass.constraints.size == cts, "#{klass} has wrong number of constraints")
      end
    end
  end

  def test_cols_and_constraints_understood
    [TestClass, TestClass2, TC3, TC4].each do |klass|
      assert(klass.respond_to?(:constraints), "#{klass} should have accessor for constraints")
      assert(klass.respond_to?(:columns), "#{klass} should have accessor for columns")
    end
  end

  def test_column_contents
    [:row_id, :foo, :bar].each do |col|
      assert(TestClass.columns.map{|c| c.name}.include?(col), "TestClass doesn't contain column #{col}")
    end
  end
  
  def test_create_proper_type
    tc = TestClass.create(:foo => 1, :bar => "argh")
    assert(tc.class == TestClass, "TestClass.create should return an instance of TestClass")
  end

  def test_create_multiples
    tc_list = [nil]
    1.upto(9) do |num|
      tc_list.push TestClass.create(:foo => num, :bar => "argh#{num}")
    end

    1.upto(9) do |num|
      assert(tc_list[num].foo == num, "multiple TestClass.create invocations should return records with proper foo values")
      assert(tc_list[num].bar == "argh#{num}", "multiple TestClass.create invocations should return records with proper bar values")

      tmp = TestClass.find(num)

      assert(tmp.foo == num, "multiple TestClass.create invocations should add records with proper foo values to the db")
      assert(tmp.bar == "argh#{num}", "multiple TestClass.create invocations should add records with proper bar values to the db")
    end
  end

  def test_delete
    range = []
    1.upto(9) do |num|
      range << num
      TestClass.create(:foo => num, :bar => "argh#{num}")
    end
    
    assert(TestClass.count == range.size, "correct number of rows inserted prior to delete")

    TestClass.find(2).delete

    assert(TestClass.count == range.size - 1, "correct number of rows inserted after delete")
  end

  def test_delete_2
    TestClass.create(:foo => 42, :bar => "Wait, what was the question?")
    tc1 = TestClass.find_first_by_foo(42)
    tc2 = TestClass.find_first_by_foo(42)
    
    [tc1,tc2].each do |obj|
      assert obj
      assert_kind_of TestClass, obj
      assert_equal false, obj.instance_eval {needs_refresh?}
    end
    
    [:foo, :bar, :row_id].each do |msg|
      assert_equal tc1.send(msg), tc2.send(msg)
    end
    
    tc1.delete
    
    tc3 = TestClass.find_by_foo(42)
    assert_equal [], tc3

    tc3 = TestClass.find_first_by_foo(42)
    assert_equal nil, tc3
    
    [tc1, tc2].each do |obj|
      assert obj.deleted?
      [:foo, :bar, :row_id].each do |msg|
        assert_equal nil, obj.send(msg)
      end
    end
  end

  def test_count_base
    assert(TestClass.count == 0, "a new table should have no rows")
  end

  def test_count_inc
    1.upto(9) do |num|
      TestClass.create(:foo => num, :bar => "argh#{num}")
      assert(TestClass.count == num, "table row count should increment after each row create")
    end
  end

  def test_create_proper_values
    vals = {:foo => 1, :bar => "argh"}
    tc = TestClass.create(vals)
    assert(tc.foo == 1, "tc.foo (newly-created) should have the value 1")
    assert(tc.bar == "argh", "tc.bar (newly-created) should have the value \"argh\"")
  end
  
  def test_create_and_find_by_id
    vals = {:foo => 2, :bar => "argh"}
    TestClass.create(vals)
    
    tc = TestClass.find(1)
    assert(tc.foo == 2, "tc.foo (found by id) should have the value 2")
    assert(tc.bar == "argh", "tc.bar (found by id) should have the value \"argh\"")
  end

  def test_find_by_id_bogus
    tc = TestClass.find(1)
    assert(tc == nil, "TestClass table should be empty")
  end

  def test_create_and_find_by_foo
    vals = {:foo => 2, :bar => "argh"}
    TestClass.create(vals)
    
    result = TestClass.find_by_foo(2)
    tc = result[0]
    assert_equal(1, result.size, "TestClass.find_by_foo(2) should return exactly one result")
    assert_equal(2, tc.foo, "tc.foo (found by foo) should have the value 2")
    assert_equal("argh", tc.bar, "tc.bar (found by foo) should have the value \"argh\"")
  end

  def test_create_and_find_first_by_foo
    vals = {:foo => 2, :bar => "argh"}
    TestClass.create(vals)
    
    tc = (TestClass.find_first_by_foo(2))
    assert(tc.foo == 2, "tc.foo (found by foo) should have the value 2")
    assert(tc.bar == "argh", "tc.bar (found by foo) should have the value \"argh\"")
  end

  def test_create_and_find_by_bar
    vals = {:foo => 2, :bar => "argh"}
    TestClass.create(vals)
    result = TestClass.find_by_bar("argh")
    tc = result[0]
    assert(result.size == 1, "TestClass.find_by_bar(\"argh\") should return exactly one result")
    assert(tc.foo == 2, "tc.foo (found by bar) should have the value 2")
    assert(tc.bar == "argh", "tc.bar (found by bar) should have the value \"argh\"")
  end
  
  def test_create_and_find_first_by_bar
    vals = {:foo => 2, :bar => "argh"}
    TestClass.create(vals)
    
    tc = (TestClass.find_first_by_bar("argh"))
    assert(tc.foo == 2, "tc.foo (found by bar) should have the value 2")
    assert(tc.bar == "argh", "tc.bar (found by bar) should have the value \"argh\"")
  end
  
  def test_create_and_update_modifies_object
    vals = {:foo => 1, :bar => "argh"}
    TestClass.create(vals)
    
    tc = TestClass.find(1)
    tc.foo = 2
    assert("#{tc.foo}" == "2", "tc.foo should have the value 2 after modifying object")
  end
  
  def test_create_and_update_modifies_db
    vals = {:foo => 1, :bar => "argh"}
    TestClass.create(vals)
    
    tc = TestClass.find(1)
    tc.foo = 2
    
    tc_fresh = TestClass.find(1)
    assert(tc_fresh.foo == 2, "foo value in first row of db should have the value 2 after modifying tc object")
  end
  
  def test_create_and_update_freshen
    vals = {:foo => 1, :bar => "argh"}
    TestClass.create(vals)
    
    tc_fresh = TestClass.find(1)    
    tc = TestClass.find(1)
    
    tc.foo = 2
    
    assert(tc_fresh.foo == 2, "object backed by db row isn't freshened")
  end
  
  def test_reference_tables
    assert(TC4.refs.size == 2, "TC4 should have 2 refs, instead has #{TC4.refs.size}")
  end

  def test_reference_classes
    t_vals = []
    t2_vals = []
    
    1.upto(9) do |n| 
      t_vals.push({:foo => n, :bar => "item-#{n}"})
      TestClass.create t_vals[-1]
    end

    9.downto(1) do |n| 
      t2_vals.push({:fred => n, :barney => "barney #{n}"})
      TestClass2.create t2_vals[-1]
    end

    1.upto(9) do |n|
      m = 10-n
      k = TC4.create(:t1 => n, :t2 => m)
      assert(k.t1.class == TestClass, "k.t1.class is #{k.t1.class}; should be TestClass")
      assert(k.t2.class == TestClass2, "k.t2.class is #{k.t2.class}; should be TestClass2")
      assert(k.enabled)
      k.enabled = false
      assert(k.enabled==false)
    end
  end

  def test_references_simple
    t_vals = []
    t2_vals = []
    
    1.upto(9) do |n| 
      t_vals.push({:foo => n, :bar => "item-#{n}"})
      TestClass.create t_vals[-1]
    end

    9.downto(1) do |n| 
      t2_vals.push({:fred => n, :barney => "barney #{n}"})
      TestClass2.create t2_vals[-1]
    end

    1.upto(9) do |n|
      k = TC4.create(:t1 => n, :t2 => (10 - n))
      assert(k.t1.foo == k.t2.fred, "references don't work")
    end
  end

  def test_references_sameclass
    SelfRef.create :one => nil
    1.upto(3) do |num|
      SelfRef.create :one => num
    end
    4.downto(2) do |num|
      sr = SelfRef.find num
      assert(sr.one.class == SelfRef, "SelfRef with row ID #{num} should have a one field of type SelfRef; is #{sr.one.class} instead")
      assert(sr.one.row_id == sr.row_id - 1, "SelfRef with row ID #{num} should have a one field with a row id of #{sr.row_id - 1}; is #{sr.one.row_id} instead")
    end
  end
  
  def test_references_circular_id
    sr = SelfRef.create :one => nil
    sr.one = sr.row_id
    assert(sr == sr.one, "self-referential rows should work; instead #{sr} isn't the same as #{sr.one}")
  end

  def test_references_circular_obj
    sr = SelfRef.create :one => nil
    sr.one = sr
    assert(sr == sr.one, "self-referential rows should work; instead #{sr} isn't the same as #{sr.one}")
  end

  def test_referential_integrity
    assert_raise CONSTRAINT_EXCEPTION do
      FromRef.create(:t => 42)
    end
    
    assert_nothing_thrown do
      1.upto(20) do |x|
        ToRef.create(:foo => "#{x}")
        FromRef.create(:t => x)
        assert_equal ToRef.count, FromRef.count
      end
    end
    
    20.downto(1) do |x|
      ct = ToRef.count
      tr = ToRef.find(x)
      tr.delete
      assert_equal ToRef.count, ct - 1
      assert_equal ToRef.count, FromRef.count
    end
  end

  def test_custom_query
    colresult = 0
    varresult = 0
    
    1.upto(20) do |i|
      1.upto(20) do |j|
        CustomQueryTable.create(:one => i, :two => j)
        colresult = colresult.succ if i < j
        varresult = varresult.succ if i < 5 && j < 7
      end
    end

    f = CustomQueryTable.ltcols
    assert(f.size() == colresult, "f.size() should equal colresult, but #{f.size()} != #{colresult}")
    f.each {|r| assert(r.one < r.two, "#{r.one}, #{r.two} should only be in ltcols custom query if #{r.one} < #{r.two}") }

    f = CustomQueryTable.ltvars 5, 7
    f2 = CustomQueryTable.cltvars 5, 7
    
    [f,f2].each do |obj|
      assert(obj.size() == varresult, "query result size should equal varresult, but #{obj.size()} != #{varresult}")
      obj.each {|r| assert(r.one < 5 && r.two < 7, "#{r.one}, #{r.two} should only be in ltvars/cltvars custom query if #{r.one} < 5 && #{r.two} < 7") }
    end
    
  end
  
  def test_equality
    tc1 = TestClass.create(:foo=>1, :bar=>"hello")
    tc2 = TestClass.create(:foo=>1, :bar=>"hello")
    tc3 = TestClass.create(:foo=>2, :bar=>"goodbye")
    
    tc1p = TestClass.find(tc1.row_id)
    
    assert_equal(tc1, tc1)         # equality is reflexive
    assert_equal(tc1p, tc1)        # even after find operations
    assert_equal(tc1, tc1p)        # ... and it should be symmetric

    assert_equal(tc1.hash, tc1p.hash)
    assert_not_equal(tc2.hash, tc1p.hash)

    assert_not_equal(tc1, tc2)     # these are not identical
    assert_not_equal(tc1p, tc2)    # even after find operations
    assert_not_equal(tc2, tc1p)    # ... and it should be symmetric
    assert_not_same(tc1, tc2)      # but these are not identical
    assert_not_equal(tc1, tc3)     # these aren't even equal!
    assert_not_equal(tc2, tc3)     # neither are these
    assert_not_equal(tc3, tc1)     # and inequality should hold
    assert_not_equal(tc3, tc2)     #   under symmetry
  end

  def freshness_query_fixture
    @flist = []
    @fresh_fields = [:fee,:fie,:foe,:fum,:foo,:bar,:created,:updated,:row_id]
    @ffcounts = {:fie=>2, :foe=>3, :fum=>4, :foo=>5, :bar=>6}  
    
    x = 0
    
    2.times do
      @ffcounts[:fie].times do |fie|
        @ffcounts[:foe].times do |foe|
          @ffcounts[:fum].times do |fum|
            @ffcounts[:foo].times do |foo|
              @ffcounts[:bar].times do |bar|
                row = FreshTestTable.create(:fee=>@flist.size, :fie=>fie, :foe=>foe, :fum=>fum, :foo=>foo, :bar=>bar)
                assert(row != nil)
                @flist << row
              end
            end
          end
        end
      end
    end
    
    @fcount = @flist.size
    @ffcounts[:fee] = @fcount
  end

  def test_freshness_query_basic
    freshness_query_fixture
    # basic test
    basic = FreshTestTable.find_freshest(:group_by=>[:fee])
    
    assert_equal(@flist.size, basic.size)
    0.upto(@fcount - 1) do |x|
      @fresh_fields.each do |msg|
        assert_equal(@flist[x].send(msg), basic[x].send(msg))
      end
    end
  end

  def test_freshness_query_basic_restricted
    freshness_query_fixture
    # basic test

    basic = FreshTestTable.find_freshest(:group_by=>[:fee], :version=>@flist[30].created, :debug=>true)
    
    assert_equal(31, basic.size)
    0.upto(30) do |x|
      @fresh_fields.each do |msg|
        assert_equal(@flist[x].send(msg), basic[x].send(msg))
      end
    end
  end

  def test_freshness_query_basic_select
    freshness_query_fixture
    # basic test

    ffc = @ffcounts[:fie]

    basic = FreshTestTable.find_freshest(:group_by=>[:fee], :select_by=>{:fie=>0}, :debug=>true).sort_by {|x| x.fee}

    expected_ct = @fcount/ffc
    expected_rows = @flist.select{|tup| tup.fie == 0}.sort_by{|tup| tup.fee}

    assert_equal(expected_ct, basic.size)

    0.upto(expected_ct - 1) do |x|
      @fresh_fields.each do |msg|
        assert_equal(expected_rows[x].send(msg), basic[x].send(msg))
      end
    end
  end

  def test_freshness_query_group_single
    freshness_query_fixture
    # more basic tests
    pairs = @ffcounts.dup
    pairs.delete(:fee)
    
    pairs.each do |col,ct|
      basic = FreshTestTable.find_freshest(:group_by=>[col])
      assert_equal(ct,basic.size)

      expected_objs = {}

      needed_vals = Set[*(0..ct).to_a]

      @flist.reverse_each do |row|
        break if needed_vals.empty?
        
        colval = row.send(col)
        if needed_vals.include? colval
          expected_objs[colval] = row
          needed_vals.delete(colval)
        end
      end

      basic.each do |row|
        res = expected_objs[row.send(col)]
        puts expected_objs.keys.inspect if res.nil?
        @fresh_fields.each do |msg|
          assert_equal(res.send(msg), row.send(msg))
        end
      end
    end
  end
  
  def test_freshness_query_group_powerset
    freshness_query_fixture
    # more basic tests
    
    pairs = @ffcounts.dup
    pairs.delete(:fee)
    pairs_powerset = pairs.to_a.inject([[]]){|c,y|r=[];c.each{|i|r<<i;r<<i+[y]};r}.map {|h| h.transpose}
    pairs_powerset.shift
    
    pairs_powerset.each do |cols,cts|
      expected_ct = cts.inject(1){|x,acc| acc * x}
      basic = FreshTestTable.find_freshest(:group_by=>cols)
      
      assert_equal(expected_ct,basic.size)

      # XXX:  test identities, too
    end
  end
  
  def test_blob_data
    words = %w{the quick brown fox jumps over a lazy dog now is time for all good men to come aid party jackdaws love my big sphinx of quartz}
    text = ""
    (0..300).each do 
      text << words[rand(words.length)] << " "
    end
    
    compressed_text = Zlib::Deflate.deflate(text)
    
    row = BlobTestTable.create(:info => text)
    
    crow = BlobTestTable.create(:info => compressed_text)
    
    btrow = BlobTestTable.find(row.row_id)
    cbtrow = BlobTestTable.find(crow.row_id)
    
    assert_equal(text, btrow.info)
    assert_equal(text, Zlib::Inflate.inflate(cbtrow.info))
  end

  def test_zblob_data
    words = %w{the quick brown fox jumps over a lazy dog now is time for all good men to come aid party jackdaws love my big sphinx of quartz}
    text = ""
    (0..300).each do 
      text << words[rand(words.length)] << " "
    end
    
    compressed_text = Zlib::Deflate.deflate(text)
    
    row = ZBlobTestTable.create(:info => text)
    crow = ZBlobTestTable.create(:info => compressed_text)
    
    btrow = ZBlobTestTable.find(row.row_id)
    cbtrow = ZBlobTestTable.find(crow.row_id)
    
    assert_equal(text, btrow.info)
    assert_equal(text, Zlib::Inflate.inflate(cbtrow.info))
  end

  def test_mutable_object_data
    things = []
    
    words = %w{It is a truth universally acknowledged that a single man in possession of a good fortune must be in want of a wife}
    
    100.times do
      things << words.sort_by {rand}
    end
    
    things.each_with_index do |thing, idx|
      ObjectTestTable.create(:otype=>thing.class.name.to_s, :obj=>thing)
    end
    
    otts = ObjectTestTable.find_all
    
    assert_equal otts.size, things.size
    
    things.zip(otts) do |thing, ott|
      assert_equal thing.class.name.to_s, ott.otype
      assert_equal thing, ott.obj      
    end
    
    otts.each_with_index do |ott, i|
      obj = ott.obj.reverse
      ott.obj = obj.dup
      assert_equal obj, ott.obj
      assert_equal obj, ObjectTestTable.find(ott.row_id).obj
      things[i].reverse!
    end
    
    things.zip(otts) do |thing, ott|
      assert_equal thing.class.name.to_s, ott.otype
      assert_equal thing, ott.obj      
    end
  end


  def test_object_data
    things = []
    things << "foo"
    things << {"foo"=>"bar"}
    things << ["a", "b", "c", "d"]
    things << [1]
    things << {"augh"=>1, "blaugh"=>"quux"}
    things << [] # empty list
    things << {} # empty hash
    things << 49 # int
    things << {"blah"=>{"foo"=>"bar"}, "argh"=>123, "yuck"=>[1,1,2,3,5,[8]]} # heterogeneous and nested hash
    things << 0.618  # float
    things << 99**99  # bignum
    things << [1,[2,[3,4,[5,6,[7,[8,9,10,[11,12,[13]]]]]]]] # ludicrous list nesting
    things << {"a"=>{"b"=>{"c"=>{"d"=>{"e"=>["f","g","h","i",{"j"=>["k","l",{"m"=>"n"}]}]}}}}} # ludicrous hash nesting
    things << Time.now.utc # time
    things << %w{foo bar blah}.to_set
    things << Customer.new("Barney Rubble", "303 Cobblestone Way")
    things << /[1-3]+[A-Z]/
    
    things.each_with_index do |thing, idx|
      ObjectTestTable.create(:otype=>thing.class.name.to_s, :obj=>thing)
    end
    
    otts = ObjectTestTable.find_all
    
    assert_equal otts.size, things.size
    
    things.zip(otts) do |thing, ott|
      assert_equal thing.class.name.to_s, ott.otype
      assert_equal thing, ott.obj      
    end
  end
  
  [true, false].each do |create_uses_rowid|
    [true, false].each do |lookup_uses_rowid|
      [true, false].each do |to_is_hash|
  
        define_method("test_reference_params_in_#{to_is_hash ? "hashed_" : ""}custom_queries_#{create_uses_rowid ? "createUsesRowID" : "createUsesObject"}_#{lookup_uses_rowid ? "lookupUsesRowID" : "lookupUsesObject"}".to_sym) do
          to_refs = %w{foo bar blah}.map {|s| ToRef.create(:foo=>s)}
          to_refs.each {}
          to_refs.each {|tr| FromRef.create(:t=>create_uses_rowid ? tr.row_id : tr)}
  
          to_refs.each do |tr|
            frs = to_is_hash ? FromRef.to_is_hash(:t=>lookup_uses_rowid ? tr.row_id : tr) : FromRef.to_is(lookup_uses_rowid ? tr.row_id : tr)
            assert_equal frs.size, 1
            assert_equal frs[0].t, tr
          end
        end
      end
    end
  end
end

unless SQLITE_13
  class PreparedStmtBackendTests < NoPreparedStmtBackendTests  
    def use_prepared
      true
    end
  end
end
