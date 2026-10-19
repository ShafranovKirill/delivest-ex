defmodule Delivest.SlugTest do
  use ExUnit.Case, async: true

  alias Delivest.Slug

  test "transliterates Russian to Latin" do
    assert Slug.slugify("Хинкали") == "hinkali"
    assert Slug.slugify("Хинкали с бараниной") == "hinkali-s-baraninoy"
    assert Slug.slugify("Щи «Ёжик» 500 г") == "schi-ezhik-500-g"
    assert Slug.slugify("Чизбургер XL") == "chizburger-xl"
  end

  test "drops accents and symbols, collapses separators" do
    assert Slug.slugify("  Crème brûlée!!  ") == "creme-brulee"
    assert Slug.slugify("a -- b") == "a-b"
  end

  test "returns nil when nothing remains" do
    assert Slug.slugify("🔥🔥") == nil
    assert Slug.slugify("") == nil
    assert Slug.slugify(nil) == nil
  end

  test "unique adds a numeric suffix" do
    taken = MapSet.new(["hinkali", "hinkali-2"])
    assert Slug.unique("hinkali", &MapSet.member?(taken, &1)) == "hinkali-3"
    assert Slug.unique("plov", &MapSet.member?(taken, &1)) == "plov"
  end
end
