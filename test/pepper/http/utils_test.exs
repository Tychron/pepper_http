defmodule Pepper.HTTP.UtilsTest do
  use ExUnit.Case

  alias Pepper.HTTP.Utils

  describe "safe_reduce_ets_table/3" do
    test "can reduce a bag" do
      tab = :ets.new(:my_bag, [:bag, :private])
      :ets.insert(tab, {:a, 1})
      :ets.insert(tab, {:b, 2})
      :ets.insert(tab, {:c, 3})
      :ets.insert(tab, {:d, 5})
      :ets.insert(tab, {:d, 4})
      :ets.insert(tab, {:d, 5})

      try do
        assert [
          {:d, 5},
          {:d, 4},
          {:c, 3},
          {:b, 2},
          {:a, 1},
        ] = Utils.safe_reduce_ets_table(tab, [], fn item, acc ->
          [item | acc]
        end)
      after
        :ets.delete(tab)
      end
    end

    test "can reduce a duplicate_bag" do
      tab = :ets.new(:my_bag, [:duplicate_bag, :private])
      :ets.insert(tab, {:a, 1})
      :ets.insert(tab, {:b, 2})
      :ets.insert(tab, {:c, 3})
      :ets.insert(tab, {:d, 5})
      :ets.insert(tab, {:d, 4})
      :ets.insert(tab, {:d, 5})

      try do
        assert [
          {:d, 4},
          {:d, 5},
          {:d, 5},
          {:c, 3},
          {:b, 2},
          {:a, 1},
        ] = Utils.safe_reduce_ets_table(tab, [], fn item, acc ->
          [item | acc]
        end)
      after
        :ets.delete(tab)
      end
    end
  end
end
