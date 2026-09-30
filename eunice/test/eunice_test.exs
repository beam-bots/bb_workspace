defmodule EuniceTest do
  use ExUnit.Case
  doctest Eunice

  test "greets the world" do
    assert Eunice.hello() == :world
  end
end
